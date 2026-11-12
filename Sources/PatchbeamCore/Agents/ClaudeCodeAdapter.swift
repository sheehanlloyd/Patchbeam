import Foundation

/// Converts Claude Code's documented `--output-format stream-json --verbose` lines into
/// normalized `AgentEvent`s. Unknown message types are ignored rather than guessed at.
/// Contract-tested against a stream captured from Claude Code 2.1.252.
public struct ClaudeStreamParser: Sendable {
    public let capsuleID: UUID
    public let worktree: URL
    private var tools: [String: (name: String, path: String?)] = [:]
    private var sawEdit = false
    private var assistantError: String?
    public private(set) var sessionID: String?
    public private(set) var sawResult = false
    public private(set) var malformedLines = 0

    public init(capsuleID: UUID, worktree: URL) {
        self.capsuleID = capsuleID
        self.worktree = worktree
    }

    static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    func relative(_ path: String?) -> String? {
        guard let path else { return nil }
        let root = PathSafety.canonical(worktree).path + "/"
        let canonical = PathSafety.canonical(URL(fileURLWithPath: path)).path
        if canonical.hasPrefix(root) { return String(canonical.dropFirst(root.count)) }
        if path.hasPrefix(worktree.path + "/") { return String(path.dropFirst(worktree.path.count + 1)) }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func event(_ kind: AgentEvent.Kind, _ phase: AgentEvent.Phase, _ summary: String, id: String? = nil, _ meta: [String: String] = [:]) -> AgentEvent {
        AgentEvent(capsuleID: capsuleID, kind: kind, phase: phase, summary: summary, providerEventID: id, metadata: meta)
    }

    private var phase: AgentEvent.Phase { sawEdit ? .editing : .diagnosing }

    public mutating func consume(line raw: String) -> [AgentEvent] {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return [] }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            malformedLines += 1
            return []
        }
        switch type {
        case "system":
            guard obj["subtype"] as? String == "init" else { return [] }
            sessionID = obj["session_id"] as? String
            let model = obj["model"] as? String ?? "unknown model"
            let version = obj["claude_code_version"] as? String ?? "?"
            let tools = (obj["tools"] as? [String])?.sorted().joined(separator: ",") ?? ""
            return [event(.sessionStarted, .diagnosing, "Claude Code \(version) session started",
                          id: "init:\(sessionID ?? "")",
                          ["model": model, "permissionMode": obj["permissionMode"] as? String ?? "", "tools": tools])]
        case "assistant":
            if let err = obj["error"] as? String { assistantError = err }
            guard let message = obj["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { return [] }
            let messageID = message["id"] as? String ?? UUID().uuidString
            var out: [AgentEvent] = []
            for (i, block) in content.enumerated() {
                switch block["type"] as? String {
                case "text":
                    let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, assistantError == nil else { continue }
                    out.append(event(.message, phase, String(text.prefix(600)), id: "\(messageID):\(i)"))
                case "thinking", "redacted_thinking":
                    out.append(event(.thinking, phase, "Reasoning…", id: "\(messageID):\(i)"))
                case "tool_use":
                    let toolID = block["id"] as? String ?? "\(messageID):\(i)"
                    let name = block["name"] as? String ?? "tool"
                    let input = block["input"] as? [String: Any] ?? [:]
                    let path = relative((input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String)
                    tools[toolID] = (name, path)
                    let isEdit = Self.editTools.contains(name)
                    if isEdit { sawEdit = true }
                    let summary: String = switch name {
                    case "Read": "Reading \(path ?? "a file")"
                    case _ where isEdit: "Editing \(path ?? "a file")"
                    case "Glob", "Grep": "Searching the worktree"
                    default: "Using \(name)"
                    }
                    var meta = ["tool": name]
                    if let path { meta["path"] = path }
                    out.append(event(.toolStarted, isEdit ? .editing : phase, summary, id: toolID, meta))
                default:
                    continue
                }
            }
            return out
        case "user":
            guard let message = obj["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] else { return [] }
            var out: [AgentEvent] = []
            for block in content where block["type"] as? String == "tool_result" {
                let toolID = block["tool_use_id"] as? String ?? UUID().uuidString
                let tool = tools[toolID] ?? ("tool", nil)
                let isError = block["is_error"] as? Bool ?? false
                // The provider reports tool success/failure but no process exit code here,
                // so none is invented (PRD §10.3).
                var meta = ["tool": tool.name, "status": isError ? "error" : "ok"]
                if let p = tool.path { meta["path"] = p }
                let label = tool.path.map { "\(tool.name) \($0)" } ?? tool.name
                out.append(event(.toolFinished, Self.editTools.contains(tool.name) ? .editing : phase,
                                 isError ? "\(label) reported an error" : "\(label) finished", id: "result:\(toolID)", meta))
                if !isError, Self.editTools.contains(tool.name) {
                    out.append(event(.editObserved, .editing, "Changed \(tool.path ?? "a file")", id: "edit:\(toolID)", ["path": tool.path ?? ""]))
                }
            }
            return out
        case "result":
            sawResult = true
            var out: [AgentEvent] = []
            if let denials = obj["permission_denials"] as? [[String: Any]] {
                for (i, denial) in denials.enumerated() {
                    let name = denial["tool_name"] as? String ?? "a tool"
                    out.append(event(.message, phase,
                        "Claude Code denied \(name) under Patchbeam's policy. Approve this action in Claude Code's own terminal; Patchbeam can't grant it.",
                        id: "denial:\(i)", ["approvalUnsupported": "true", "tool": name]))
                }
            }
            let isError = obj["is_error"] as? Bool ?? false
            let subtype = obj["subtype"] as? String ?? ""
            let resultText = (obj["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var meta: [String: String] = ["subtype": subtype]
            if let cost = obj["total_cost_usd"] as? Double { meta["costUSD"] = String(format: "%.4f", cost) }
            if let turns = obj["num_turns"] as? Int { meta["turns"] = String(turns) }
            if let ms = obj["duration_ms"] as? Int { meta["durationMs"] = String(ms) }
            if assistantError == "authentication_failed" || resultText.localizedCaseInsensitiveContains("not logged in") {
                meta["reason"] = "notAuthenticated"
                out.append(event(.failed, .done, "Sign in with your provider CLI first (claude auth login).", id: "result", meta))
            } else if isError || subtype != "success" {
                meta["reason"] = assistantError ?? subtype
                let detail = resultText.isEmpty ? subtype.replacingOccurrences(of: "_", with: " ") : String(resultText.prefix(300))
                out.append(event(.failed, .done, "Agent couldn't complete this step: \(detail)", id: "result", meta))
            } else {
                // The final assistant text already appears as a `message` event, so the terminal event stays
                // short; the full text is carried for the capsule's "agent summary" (model text, not proof).
                var parts = ["Agent finished"]
                if let turns = meta["turns"] { parts.append("\(turns) turns") }
                if let cost = meta["costUSD"] { parts.append("$\(cost)") }
                if !resultText.isEmpty { meta["resultText"] = String(resultText.prefix(4000)) }
                out.append(event(.completed, .verifying, parts.joined(separator: " · "), id: "result", meta))
            }
            return out
        default:
            return []  // stream_event, rate_limit and future types: ignored, not guessed.
        }
    }

    /// Called when the process exits. Produces a terminal event if the stream never did.
    public func finish(exitCode: Int32?, signal: Int32?, cancelled: Bool, timedOut: Bool, stderrTail: String) -> [AgentEvent] {
        var out: [AgentEvent] = []
        if malformedLines > 0 {
            out.append(event(.message, phase, "Ignored \(malformedLines) unparseable line(s) from the provider.", id: "malformed"))
        }
        guard !sawResult else { return out }
        if cancelled {
            out.append(event(.cancelled, .done, "Agent stopped by user.", id: "result"))
        } else if timedOut {
            out.append(event(.failed, .done, "Agent hit Patchbeam's time limit and was stopped.", id: "result", ["reason": "timeout"]))
        } else {
            let how = exitCode.map { "exit code \($0)" } ?? "signal \(signal ?? 0)"
            let tail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(event(.failed, .done, "Agent exited without a result (\(how)).\(tail.isEmpty ? "" : " \(tail.suffix(300))")", id: "result",
                             ["reason": "transport"]))
        }
        return out
    }
}

/// Real provider: Claude Code in headless print mode (ADR-0002).
/// Scope: `--tools Read,Edit,Write` (no shell), `acceptEdits`, `--restricted` (file tools
/// confined to the worktree), no MCP, no user settings, budget cap, wall-clock timeout.
/// Approvals are not bridged, so `capabilities.approve == false`.
public struct ClaudeCodeAdapter: AgentAdapter {
    public static let id = "claude-code"
    public static let testedVersion = "2.1.252"
    public var searchPath: [String]
    public var model: String?

    public init(searchPath: [String] = MinimalEnvironment.defaultSearchPath, model: String? = nil) {
        self.searchPath = searchPath
        self.model = model
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(id: Self.id, displayName: "Claude Code", isScripted: false)
    }

    static let capabilities = ProviderCapabilities(run: true, stream: true, approve: false, resume: false)

    public func probe() async -> ProviderAvailability {
        guard let exe = ExecutableLocator.find("claude", searchPath: searchPath) else {
            return ProviderAvailability(state: .notInstalled, version: nil, executablePath: nil, capabilities: Self.capabilities,
                                        message: "Install a supported coding agent to run a real repair.",
                                        setupHint: "Install Claude Code (https://docs.claude.com/en/docs/claude-code), then run `claude auth login`.")
        }
        let runner = ProcessRunner()
        let env = MinimalEnvironment.make(searchPath: searchPath)
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let versionResult = try? await runner.run(ProcessSpec(executable: exe, arguments: ["--version"], workingDirectory: home, environment: env, timeout: .seconds(15)))
        guard let versionResult, versionResult.succeeded else {
            return ProviderAvailability(state: .broken("`claude --version` failed"), version: nil, executablePath: exe.path, capabilities: Self.capabilities,
                                        message: "Claude Code is installed but didn't start.",
                                        setupHint: versionResult?.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let version = versionResult.stdoutString.split(separator: " ").first.map(String.init) ?? versionResult.stdoutString
        // `claude auth status --json` reports login state without exposing credentials.
        let auth = try? await runner.run(ProcessSpec(executable: exe, arguments: ["auth", "status", "--json"], workingDirectory: home, environment: env, timeout: .seconds(15)))
        var loggedIn: Bool?
        if let data = auth?.stdout, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            loggedIn = obj["loggedIn"] as? Bool
        }
        if loggedIn == false {
            return ProviderAvailability(state: .notAuthenticated, version: version, executablePath: exe.path, capabilities: Self.capabilities,
                                        message: "Sign in with your provider CLI first.", setupHint: "Run `claude auth login` in Terminal, then re-check.")
        }
        let note = version == Self.testedVersion ? "" : " (Patchbeam was tested with \(Self.testedVersion))"
        return ProviderAvailability(state: .ready, version: version, executablePath: exe.path, capabilities: Self.capabilities,
                                    message: "Claude Code \(version) ready\(note). Approvals happen in Claude Code, not Patchbeam.")
    }

    public func arguments(budgetUSD: Double) -> [String] {
        var args = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--tools", "Read,Edit,Write",
            "--allowedTools", "Read,Edit,Write",
            "--permission-mode", "acceptEdits",
            "--restricted",
            "--strict-mcp-config",
            "--setting-sources", "",
            "--no-session-persistence",
            "--max-budget-usd", String(format: "%.2f", budgetUSD),
        ]
        if let model { args += ["--model", model] }
        return args
    }

    public func start(_ request: AgentRunRequest) async throws -> any AgentSession {
        guard let exe = ExecutableLocator.find("claude", searchPath: searchPath) else {
            throw PatchbeamError(.providerMissing, "Install a supported coding agent to run a real repair.")
        }
        let spec = ProcessSpec(
            executable: exe,
            arguments: arguments(budgetUSD: request.budgetUSD),
            workingDirectory: request.worktree,
            environment: MinimalEnvironment.make(searchPath: searchPath),
            stdin: Data(RepairPrompt.make(request).utf8),  // via stdin, not argv (not visible in `ps`)
            timeout: request.timeout,
            outputLimitBytes: 8 * 1024 * 1024,
            streamOutput: true
        )
        let process = try ProcessRunner().start(spec)
        return ClaudeCodeSession(process: process, request: request)
    }
}

final class ClaudeCodeSession: AgentSession, @unchecked Sendable {
    let events: AsyncStream<AgentEvent>
    private let process: RunningProcess

    init(process: RunningProcess, request: AgentRunRequest) {
        self.process = process
        var c: AsyncStream<AgentEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        let continuation = c!
        let transcriptURL = request.logDirectory.appendingPathComponent("agent-stream-\(Int(Date().timeIntervalSince1970)).jsonl")
        try? FileManager.default.createDirectory(at: request.logDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: transcriptURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let transcript = try? FileHandle(forWritingTo: transcriptURL)

        Task.detached {
            var parser = ClaudeStreamParser(capsuleID: request.capsuleID, worktree: request.worktree)
            var buffer = Data()
            // The terminal event is held until the process exits so it is always the last event.
            var terminalEvent: AgentEvent?
            let maxLine = 4 * 1024 * 1024
            func deliver(_ events: [AgentEvent]) {
                for e in events {
                    if [.completed, .failed, .cancelled].contains(e.kind) {
                        if terminalEvent == nil { terminalEvent = e }
                    } else if terminalEvent == nil {
                        continuation.yield(e)
                    }
                }
            }
            for await chunk in process.output where chunk.stream == .stdout {
                try? transcript?.write(contentsOf: chunk.data)
                buffer.append(chunk.data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    deliver(parser.consume(line: String(decoding: lineData, as: UTF8.self)))
                }
                if buffer.count > maxLine { buffer.removeAll() }  // pathological line; drop it
            }
            if !buffer.isEmpty { deliver(parser.consume(line: String(decoding: buffer, as: UTF8.self))) }
            let result = await process.waitForExit()
            try? transcript?.close()
            let tail = parser.finish(exitCode: result.exitCode, signal: result.signal, cancelled: result.cancelled,
                                     timedOut: result.timedOut, stderrTail: String(result.stderrString.suffix(400)))
            for e in tail where ![.completed, .failed, .cancelled].contains(e.kind) { continuation.yield(e) }
            if result.cancelled, terminalEvent?.kind != .failed {
                terminalEvent = AgentEvent(capsuleID: request.capsuleID, kind: .cancelled, phase: .done, summary: "Agent stopped by user.")
            }
            if let final = terminalEvent ?? tail.first(where: { [.completed, .failed, .cancelled].contains($0.kind) }) {
                continuation.yield(final)
            }
            continuation.finish()
        }
    }

    func respond(to providerRequestID: String, decision: ApprovalDecision) async throws {
        throw PatchbeamError(.approvalUnsupported, "Approve this action in Claude Code's terminal.",
                             recovery: "Patchbeam doesn't bridge Claude Code approvals in v1.")
    }

    func cancel() async {
        process.cancel()
    }
}

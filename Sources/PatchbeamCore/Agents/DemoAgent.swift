import Foundation

/// Deterministic, scripted adapter for the bundled `broken-python` fixture. It walks the
/// same lifecycle as a real provider and makes a **real** edit in the worktree, but it never
/// contacts a model and is labeled as a scripted demo everywhere (PRD §12.1, PB-021).
public struct DemoAgentAdapter: AgentAdapter {
    public enum Scenario: String, Sendable, CaseIterable {
        /// Correct one-line fix.
        case fix
        /// First attempt makes a wrong fix (check fails); the user-approved retry fixes it.
        case wrongFixThenFix
        /// Asks permission to run the tests before editing (exercises the approval UI).
        case approval
    }

    public static let id = "demo"
    public var scenario: Scenario
    public var stepDelay: Duration
    public var approvalTimeout: Duration

    public init(scenario: Scenario = .fix, stepDelay: Duration = .milliseconds(650), approvalTimeout: Duration = .seconds(120)) {
        self.scenario = scenario
        self.stepDelay = stepDelay
        self.approvalTimeout = approvalTimeout
    }

    public var descriptor: ProviderDescriptor {
        ProviderDescriptor(id: Self.id, displayName: "DemoAgent (scripted, no model)", isScripted: true)
    }

    public func probe() async -> ProviderAvailability {
        ProviderAvailability(
            state: .ready, version: "1", executablePath: nil,
            capabilities: ProviderCapabilities(run: true, stream: true, approve: true, resume: false),
            message: "Demo — no model used. Repairs only the bundled broken-python fixture."
        )
    }

    public func start(_ request: AgentRunRequest) async throws -> any AgentSession {
        let session = DemoAgentSession(request: request, scenario: scenario, delay: stepDelay, approvalTimeout: approvalTimeout)
        session.begin()
        return session
    }
}

final class DemoAgentSession: AgentSession, @unchecked Sendable {
    let events: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    private let request: AgentRunRequest
    private let scenario: DemoAgentAdapter.Scenario
    private let delay: Duration
    private let approvalTimeout: Duration
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var pendingApproval: (id: String, continuation: CheckedContinuation<ApprovalDecision, Never>)?

    static let buggyLine = "return round(base - tax, 2)"
    static let fixedLine = "return round(base + tax, 2)"
    static let wrongLine = "return round(base + tax * 2, 2)"

    init(request: AgentRunRequest, scenario: DemoAgentAdapter.Scenario, delay: Duration, approvalTimeout: Duration) {
        self.request = request
        self.scenario = scenario
        self.delay = delay
        self.approvalTimeout = approvalTimeout
        var c: AsyncStream<AgentEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        continuation = c
    }

    func begin() {
        task = Task { [self] in
            do {
                try await script()
            } catch is CancellationError {
                emit(.cancelled, .done, "DemoAgent stopped by user.")
            } catch let e as PatchbeamError {
                emit(.failed, .done, e.message, ["code": e.code.rawValue])
            } catch {
                emit(.failed, .done, "DemoAgent failed: \(error)")
            }
            continuation.finish()
        }
    }

    private func emit(_ kind: AgentEvent.Kind, _ phase: AgentEvent.Phase, _ summary: String, _ meta: [String: String] = [:]) {
        continuation.yield(AgentEvent(capsuleID: request.capsuleID, kind: kind, phase: phase, summary: summary, metadata: meta.merging(["scripted": "true"]) { a, _ in a }))
    }

    private func pause() async throws {
        try await Task.sleep(for: delay)
        try Task.checkCancellation()
    }

    private func script() async throws {
        let file = request.worktree.appendingPathComponent("calculator.py")
        guard PathSafety.isContained(file, in: request.worktree) else {
            throw PatchbeamError(.pathEscape, "DemoAgent refused a path outside the worktree.")
        }
        emit(.sessionStarted, .diagnosing, "DemoAgent started — scripted demo, no model used")
        try await pause()
        let isRetry = request.previousFailure != nil
        emit(.thinking, .diagnosing, isRetry ? "Reading the failed check output from the previous attempt" : "Reading the diagnostic: \(DiagnosticIntake.inferTitle(request.diagnostic))")
        try await pause()
        emit(.toolStarted, .diagnosing, "Reading calculator.py", ["tool": "read", "path": "calculator.py"])
        guard let source = try? String(contentsOf: file, encoding: .utf8),
              source.contains(Self.buggyLine) || source.contains(Self.wrongLine) else {
            throw PatchbeamError(.providerFailed, "DemoAgent only repairs the bundled broken-python fixture.",
                                 recovery: "Connect a real provider for other repositories.")
        }
        emit(.toolFinished, .diagnosing, "Read calculator.py", ["tool": "read", "status": "ok"])
        try await pause()
        emit(.message, .diagnosing, "Root cause: total() subtracts the tax from the subtotal instead of adding it.")
        try await pause()

        if scenario == .approval && !isRetry {
            let requestID = "demo-approval-\(request.capsuleID.uuidString.prefix(8))"
            let command = FixtureLibrary.checkCommand
            continuation.yield(AgentEvent(
                capsuleID: request.capsuleID, kind: .approvalRequested, phase: .diagnosing,
                summary: "DemoAgent wants to run the test suite before editing",
                providerEventID: requestID,
                metadata: ["requestID": requestID, "command": command.joined(separator: " "), "cwd": request.worktree.path,
                           "reason": "Reproduce the failure before changing code.", "scope": "Runs tests inside the repair worktree only.",
                           "risk": ApprovalRisk.low.rawValue, "expiresIn": "\(approvalTimeout.components.seconds)", "scripted": "true"]
            ))
            let decision = await waitForApproval(id: requestID)
            try Task.checkCancellation()
            if decision == .allowOnce {
                emit(.toolStarted, .diagnosing, "Running \(command.joined(separator: " "))", ["tool": "exec"])
                let exe = ExecutableLocator.find(command[0]) ?? URL(fileURLWithPath: "/usr/bin/python3")
                let result = try await ProcessRunner().run(ProcessSpec(
                    executable: exe, arguments: Array(command.dropFirst()), workingDirectory: request.worktree,
                    environment: MinimalEnvironment.make(extra: ["PYTHONDONTWRITEBYTECODE": "1"]), timeout: .seconds(60)))
                let code = result.exitCode.map(String.init) ?? "signal \(result.signal ?? 0)"
                emit(.toolFinished, .diagnosing, "Tests exited \(code) — failure reproduced", ["tool": "exec", "exitCode": code])
            } else {
                emit(.message, .diagnosing, "Command was denied; continuing without running it.")
            }
            try await pause()
        }

        emit(.toolStarted, .editing, "Editing calculator.py", ["tool": "edit", "path": "calculator.py"])
        try await pause()
        let useWrongFix = scenario == .wrongFixThenFix && !isRetry
        let replacement = useWrongFix ? Self.wrongLine : Self.fixedLine
        let edited = source
            .replacingOccurrences(of: Self.buggyLine, with: replacement)
            .replacingOccurrences(of: Self.wrongLine, with: replacement)
        try Data(edited.utf8).write(to: file, options: .atomic)
        emit(.editObserved, .editing, "Changed calculator.py (1 line)", ["path": "calculator.py"])
        emit(.toolFinished, .editing, "Edit applied to calculator.py", ["tool": "edit", "status": "ok"])
        try await pause()
        emit(.completed, .verifying, useWrongFix
            ? "Scripted attempt finished (intentionally imperfect for the retry demo). Patchbeam will now run the check."
            : "Scripted fix finished: total() now adds tax. Patchbeam will now run the check.")
    }

    private func waitForApproval(id: String) async -> ApprovalDecision {
        let timeout = approvalTimeout
        return await withCheckedContinuation { (c: CheckedContinuation<ApprovalDecision, Never>) in
            lock.lock()
            pendingApproval = (id, c)
            lock.unlock()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                // Expired requests resolve as deny and become un-actionable (PRD §6 Journey B).
                self?.resolve(id: id, decision: .deny)
            }
        }
    }

    @discardableResult
    private func resolve(id: String, decision: ApprovalDecision) -> Bool {
        lock.lock()
        guard let pending = pendingApproval, pending.id == id else { lock.unlock(); return false }
        pendingApproval = nil
        lock.unlock()
        pending.continuation.resume(returning: decision)
        return true
    }

    func respond(to providerRequestID: String, decision: ApprovalDecision) async throws {
        guard resolve(id: providerRequestID, decision: decision) else {
            throw PatchbeamError(.approvalStale, "That request is no longer pending.")
        }
    }

    func cancel() async {
        task?.cancel()
        if let pendingID = lock.withLock({ pendingApproval?.id }) { resolve(id: pendingID, decision: .deny) }
    }
}

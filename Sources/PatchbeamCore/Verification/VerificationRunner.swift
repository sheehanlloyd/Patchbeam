import Foundation

/// Opportunistic parsers for common test runners. The exit code always stays authoritative;
/// counts are shown only when a parser actually recognized the output (PRD §13.4).
public enum TestOutputParser {
    public static func parse(_ output: String) -> ParsedTestSummary? {
        unittest(output) ?? pytest(output) ?? jest(output) ?? cargo(output) ?? xctest(output) ?? swiftTesting(output)
    }

    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        let ns = text as NSString
        guard let m = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static func count(_ label: String, in text: String) -> Int? {
        firstMatch(#"(\d+) "# + label, in: text).flatMap { Int($0[1]) }
    }

    static func unittest(_ s: String) -> ParsedTestSummary? {
        guard let ran = firstMatch(#"^Ran (\d+) tests? in [\d.]+s"#, in: s), let total = Int(ran[1]) else { return nil }
        var failures = 0, errors = 0, skipped = 0
        if let tail = firstMatch(#"^(?:OK|FAILED)(?: \((.*)\))?\s*$"#, in: s), tail.count > 1 {
            let detail = tail[1]
            failures = Int(firstMatch(#"failures=(\d+)"#, in: detail)?[1] ?? "") ?? 0
            errors = Int(firstMatch(#"errors=(\d+)"#, in: detail)?[1] ?? "") ?? 0
            skipped = Int(firstMatch(#"skipped=(\d+)"#, in: detail)?[1] ?? "") ?? 0
        }
        return ParsedTestSummary(framework: "unittest", total: total, passed: max(0, total - failures - errors - skipped),
                                 failed: failures, errors: errors, skipped: skipped, noTestsRan: total == 0)
    }

    static func pytest(_ s: String) -> ParsedTestSummary? {
        if firstMatch(#"^=+ no tests ran"#, in: s) != nil {
            return ParsedTestSummary(framework: "pytest", total: 0, passed: 0, failed: 0, errors: 0, skipped: 0, noTestsRan: true)
        }
        guard let line = firstMatch(#"^=+ (.*(?:passed|failed|error).*) in [\d.]+s"#, in: s)?[1] else { return nil }
        let passed = count("passed", in: line) ?? 0
        let failed = count("failed", in: line) ?? 0
        let errors = count("errors?", in: line) ?? 0
        let skipped = count("skipped", in: line) ?? 0
        return ParsedTestSummary(framework: "pytest", total: passed + failed + errors + skipped, passed: passed, failed: failed,
                                 errors: errors, skipped: skipped, noTestsRan: passed + failed + errors == 0)
    }

    static func jest(_ s: String) -> ParsedTestSummary? {
        guard let line = firstMatch(#"^Tests:\s+(.*\d+ total)"#, in: s)?[1] else { return nil }
        let total = count("total", in: line) ?? 0
        return ParsedTestSummary(framework: "jest", total: total, passed: count("passed", in: line) ?? 0, failed: count("failed", in: line) ?? 0,
                                 errors: nil, skipped: count("skipped", in: line), noTestsRan: total == 0)
    }

    static func cargo(_ s: String) -> ParsedTestSummary? {
        guard let m = firstMatch(#"^test result: (?:ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored"#, in: s) else { return nil }
        let p = Int(m[1]) ?? 0, f = Int(m[2]) ?? 0, i = Int(m[3]) ?? 0
        return ParsedTestSummary(framework: "cargo", total: p + f + i, passed: p, failed: f, errors: nil, skipped: i, noTestsRan: p + f == 0)
    }

    static func xctest(_ s: String) -> ParsedTestSummary? {
        guard let m = firstMatch(#"Executed (\d+) tests?, with (\d+) failures?"#, in: s) else { return nil }
        let t = Int(m[1]) ?? 0, f = Int(m[2]) ?? 0
        return ParsedTestSummary(framework: "XCTest", total: t, passed: t - f, failed: f, errors: nil, skipped: nil, noTestsRan: t == 0)
    }

    static func swiftTesting(_ s: String) -> ParsedTestSummary? {
        guard let m = firstMatch(#"Test run with (\d+) tests? (?:in \d+ suites? )?(passed|failed)"#, in: s) else { return nil }
        let t = Int(m[1]) ?? 0
        let failedRun = m[2] == "failed"
        return ParsedTestSummary(framework: "Swift Testing", total: t, passed: failedRun ? nil : t, failed: nil, errors: nil, skipped: nil, noTestsRan: t == 0)
    }
}

/// Runs an approved recipe inside a worktree without a shell and records evidence.
public struct VerificationRunner: Sendable {
    private let runner = ProcessRunner()
    public var searchPath: [String]

    public init(searchPath: [String] = MinimalEnvironment.defaultSearchPath) {
        self.searchPath = searchPath
    }

    /// Resolve argv[0]: bare names via PATH; paths relative to the worktree must stay inside it.
    public func resolveExecutable(_ name: String, worktree: URL) throws -> URL {
        if name.hasPrefix("/") {
            guard FileManager.default.isExecutableFile(atPath: name) else {
                throw PatchbeamError(.commandNotFound, "“\(name)” isn't an executable file.")
            }
            return URL(fileURLWithPath: name)
        }
        if name.contains("/") {
            let url = worktree.appendingPathComponent(name)
            guard PathSafety.isContained(url, in: worktree) else {
                throw PatchbeamError(.pathEscape, "“\(name)” points outside the repair worktree.")
            }
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw PatchbeamError(.commandNotFound, "“\(name)” isn't executable in the worktree.", recovery: "chmod +x it in your repository, or call it via its interpreter.")
            }
            return url
        }
        guard let url = ExecutableLocator.find(name, searchPath: searchPath) else {
            throw PatchbeamError(.commandNotFound, "Couldn't find “\(name)” on Patchbeam's PATH.",
                                 recovery: "Use an absolute path, e.g. /usr/bin/python3.", detail: searchPath.joined(separator: ":"))
        }
        return url
    }

    public func run(
        recipe: VerificationRecipe,
        capsuleID: UUID,
        kind: VerificationRecord.Kind,
        worktree: URL,
        logDirectory: URL,
        patchFingerprint: String?,
        cancellation: (@Sendable (RunningProcess) -> Void)? = nil
    ) async -> VerificationRecord {
        let started = Date()
        let id = UUID()
        var record = VerificationRecord(
            id: id, capsuleID: capsuleID, kind: kind, patchFingerprint: patchFingerprint, argv: recipe.argv,
            executablePath: nil, cwd: worktree.path, startedAt: started, endedAt: started, exitCode: nil, signal: nil,
            stdoutLogPath: nil, stderrLogPath: nil, outputTail: "", parsed: nil, result: .launchFailed, warnings: []
        )
        guard recipe.isApproved else {
            record.warnings.append("Check command was not approved.")
            record.outputTail = "Patchbeam will not run an unapproved command."
            return record
        }
        do {
            guard let program = recipe.argv.first else { throw PatchbeamError(.commandRequired, "The chosen check requires a command.") }
            let exe = try resolveExecutable(program, worktree: worktree)
            record.executablePath = exe.path
            let spec = ProcessSpec(
                executable: exe,
                arguments: Array(recipe.argv.dropFirst()),
                workingDirectory: worktree,
                environment: MinimalEnvironment.make(searchPath: searchPath, extra: ["PYTHONDONTWRITEBYTECODE": "1", "CI": "1"]),
                timeout: .seconds(recipe.timeoutSeconds),
                outputLimitBytes: 2 * 1024 * 1024
            )
            let process = try runner.start(spec)
            cancellation?(process)
            let result = await withTaskCancellationHandler { await process.waitForExit() } onCancel: { process.cancel() }

            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let stamp = "\(kind.rawValue)-\(id.uuidString.prefix(8).lowercased())"
            let outURL = logDirectory.appendingPathComponent("verify-\(stamp)-stdout.log")
            let errURL = logDirectory.appendingPathComponent("verify-\(stamp)-stderr.log")
            try result.stdout.write(to: outURL)
            try result.stderr.write(to: errURL)
            record.stdoutLogPath = outURL.path
            record.stderrLogPath = errURL.path
            record.exitCode = result.exitCode
            record.signal = result.signal
            record.endedAt = Date()

            let combined = TerminalTextSanitizer.sanitize(result.stdoutString + "\n" + result.stderrString)
            record.outputTail = String(combined.suffix(6000)).trimmingCharacters(in: .whitespacesAndNewlines)
            record.parsed = TestOutputParser.parse(combined)
            if result.stdoutTruncated || result.stderrTruncated { record.warnings.append("Output exceeded 2 MB and was truncated in the log.") }

            if result.timedOut {
                record.result = .timedOut
            } else if result.cancelled {
                record.result = .cancelled
            } else if result.exitCode == 0 {
                if record.parsed?.noTestsRan == true {
                    record.result = .inconclusive
                    record.warnings.append("Command exited 0 but no tests ran.")
                } else {
                    record.result = .passed
                    if record.parsed == nil { record.warnings.append("Unrecognized test output; result is based on exit code 0 only.") }
                }
            } else {
                record.result = .failed
            }
        } catch let error as PatchbeamError {
            record.endedAt = Date()
            record.outputTail = error.description
            record.result = .launchFailed
        } catch {
            record.endedAt = Date()
            record.outputTail = String(describing: error)
            record.result = .launchFailed
        }
        return record
    }
}

import Foundation
import PatchbeamCore

/// Headless driver for the same core the app uses. Exit codes: 0 ok, 1 assertion/run
/// failure, 2 usage error. It never applies a patch unless `--apply` is passed.
@main
struct PatchbeamCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { usage(); exit(2) }
        args.removeFirst()
        do {
            switch command {
            case "demo": exit(try await demo(args))
            case "probe": exit(await probe())
            case "run": exit(try await run(args))
            case "-h", "--help", "help": usage(); exit(0)
            default: usage(); exit(2)
            }
        } catch let e as PatchbeamError {
            fputs("error: \(e.description)\n", stderr)
            exit(1)
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func usage() {
        print("""
        patchbeam-cli — headless driver for Patchbeam's repair pipeline

          demo --headless [--scenario fix|wrongFixThenFix|approval] [--keep] [--home DIR]
              Create a fresh broken-python fixture repo in a temp dir, repair it with the scripted
              DemoAgent (no model), verify red→green, apply, and assert every safety invariant.
          probe
              Report provider availability (no secrets are read).
          run --provider claude-code --repo PATH --diagnostic-file FILE [--check "CMD"] --yes [--apply] [--budget USD]
              Live repair with a real provider in an app-owned worktree. Requires --yes.
              Never applies unless --apply is given and the selected checks passed.
        """)
    }

    static func value(_ flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func line(_ s: String = "") { print(s); fflush(stdout) }

    static func printEvents(_ orchestrator: RepairOrchestrator, _ id: UUID) async -> Task<Void, Never> {
        let updates = await orchestrator.updates()
        return Task {
            for await u in updates {
                switch u {
                case .event(let e) where e.capsuleID == id:
                    let tag = e.metadata["scripted"] == "true" ? "demo" : e.kind == .host ? "host" : "agent"
                    line("  [\(tag)] \(e.kind.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) \(e.summary)")
                case .capsule(let c) where c.id == id:
                    line("  ── status: \(c.status.rawValue) — \(c.status.label)")
                default: break
                }
            }
        }
    }

    // MARK: demo

    static func demo(_ args: [String]) async throws -> Int32 {
        guard args.contains("--headless") else {
            fputs("demo currently requires --headless (the GUI demo is in the app).\n", stderr)
            return 2
        }
        let scenario = value("--scenario", in: args).flatMap(DemoAgentAdapter.Scenario.init(rawValue:)) ?? .fix
        let base = URL(fileURLWithPath: value("--home", in: args) ?? NSTemporaryDirectory())
            .appendingPathComponent("patchbeam-demo-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let paths = AppPaths(root: base.appendingPathComponent("Application Support/Patchbeam"))
        let git = try GitClient.locate()
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) {
            line("  \(ok ? "✔" : "✘") \(what)")
            if !ok { failures.append(what) }
        }

        line("Patchbeam headless fixture demo — DemoAgent (scripted, no model used)")
        line("Workspace: \(base.path)")
        let repo = try await FixtureLibrary.makeBrokenPythonRepo(in: base, git: git)
        line("Fixture repo: \(repo.path)")
        let headBefore = try await git.checked(["rev-parse", "HEAD"], in: repo)

        let python = ExecutableLocator.find("python3") ?? URL(fileURLWithPath: "/usr/bin/python3")
        func unittest(_ dir: URL) async throws -> ProcessResult {
            try await ProcessRunner().run(ProcessSpec(executable: python, arguments: ["-m", "unittest", "-v"], workingDirectory: dir,
                                                      environment: MinimalEnvironment.make(extra: ["PYTHONDONTWRITEBYTECODE": "1"])))
        }
        line("\n1. Source baseline")
        let sourceBefore = try await unittest(repo)
        check(sourceBefore.exitCode == 1, "source `python3 -m unittest -v` exits 1 (got \(sourceBefore.exitCode.map(String.init) ?? "signal"))")

        let adapter = DemoAgentAdapter(scenario: scenario, stepDelay: .milliseconds(120), approvalTimeout: .seconds(30))
        let orchestrator = try await RepairOrchestrator(paths: paths, adapters: [adapter])
        let recipe = VerificationRecipe(argv: FixtureLibrary.checkCommand, display: "python3 -m unittest -v").approving()
        let capsule = try await orchestrator.createCapsule(RepairDraft(diagnostic: FixtureLibrary.sampleTraceback, repoRoot: repo,
                                                                        providerID: DemoAgentAdapter.id, recipe: recipe))
        line("\n2. Repair capsule \(capsule.shortID): “\(capsule.title)”")
        let printer = await printEvents(orchestrator, capsule.id)
        var approvalTask: Task<Void, Never>?
        if scenario == .approval {
            let updates = await orchestrator.updates()
            approvalTask = Task {
                for await u in updates {
                    if case .capsule(let c) = u, c.id == capsule.id, c.status == .awaitingApproval {
                        line("  (headless: allowing once — `\(c.pendingApproval?.command ?? "")`)")
                        try? await orchestrator.respond(c.id, decision: .allowOnce)
                        return
                    }
                }
            }
        }
        try await orchestrator.start(capsule.id)
        await orchestrator.waitUntilIdle(capsule.id)
        if scenario == .wrongFixThenFix, await orchestrator.capsule(capsule.id)?.status == .reviewReadyFailed {
            line("  (headless: approving the single retry with failure evidence)")
            try await orchestrator.retry(capsule.id)
            await orchestrator.waitUntilIdle(capsule.id)
        }
        try await Task.sleep(for: .milliseconds(100))
        approvalTask?.cancel()

        guard let done = await orchestrator.capsule(capsule.id) else { return 1 }
        let records = try await orchestrator.verifications(capsule.id)
        line("\n3. Evidence")
        if let b = records.first(where: { $0.kind == .baseline }) {
            line("  baseline: \(b.headline) · \(b.parsed?.line ?? "-") · \(String(format: "%.2fs", b.durationSeconds))")
        }
        if let p = records.last(where: { $0.kind == .patch }) {
            line("  patch:    \(p.headline) · \(p.parsed?.line ?? "-") · \(String(format: "%.2fs", p.durationSeconds))")
            line("  command:  \(p.argv.joined(separator: " "))  (exe \(p.executablePath ?? "?"))")
            line("  cwd:      \(p.cwd)")
            line("  logs:     \(p.stderrLogPath ?? "-")")
        }
        if let patch = done.patch {
            line("  patch:    \(patch.statsLine) · fingerprint \(patch.fingerprint.prefix(16))…")
            if let diff = try? String(contentsOfFile: patch.diffPath, encoding: .utf8) {
                line(diff.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
            }
        }
        check(records.first { $0.kind == .baseline }?.exitCode == 1, "red before: baseline check in the worktree exited 1")
        check(records.last { $0.kind == .patch }?.exitCode == 0, "green after: patch check exited 0")
        check(done.status == .reviewReadyVerified, "status is reviewReadyVerified (\(done.status.label))")
        check(done.verifiedFingerprint == done.patch?.fingerprint, "proof fingerprint matches the current patch")
        let sourceStill = try await unittest(repo)
        check(sourceStill.exitCode == 1, "source checkout is still red before approval")

        line("\n4. Explicit apply (headless stands in for the user's click)")
        let outcome = try await orchestrator.apply(capsule.id)
        line("  applied: \(outcome.appliedFiles.joined(separator: ", ")) · undo: \(outcome.rollbackCommand.joined(separator: " "))")
        let sourceAfter = try await unittest(repo)
        check(sourceAfter.exitCode == 0, "source `python3 -m unittest -v` exits 0 after apply")
        check(try await git.checked(["rev-parse", "HEAD"], in: repo) == headBefore, "HEAD unchanged — nothing committed")
        check(try await git.checked(["diff", "--cached", "--name-only"], in: repo).isEmpty, "index untouched — nothing staged")
        check(try await git.checked(["status", "--porcelain"], in: repo) == " M calculator.py", "only calculator.py modified in the working tree")

        if !args.contains("--keep") {
            try await orchestrator.cleanUpWorktree(capsule.id)
            check(try await git.checked(["worktree", "list", "--porcelain"], in: repo).components(separatedBy: "worktree ").count == 2,
                  "app-owned worktree removed")
        }
        printer.cancel()
        line(failures.isEmpty ? "\nRESULT: PASS — deterministic red→green fixture repair verified." : "\nRESULT: FAIL — \(failures.count) check(s) failed.")
        return failures.isEmpty ? 0 : 1
    }

    // MARK: probe

    static func probe() async -> Int32 {
        for adapter in [ClaudeCodeAdapter() as any AgentAdapter, DemoAgentAdapter()] {
            let p = await adapter.probe()
            let caps = p.capabilities
            line("\(adapter.descriptor.displayName)")
            line("  state:   \(p.state)")
            line("  version: \(p.version ?? "-")  path: \(p.executablePath ?? "-")")
            line("  caps:    run=\(caps.run) stream=\(caps.stream) approve=\(caps.approve) resume=\(caps.resume)")
            line("  message: \(p.message)\(p.setupHint.map { "\n  setup:   \($0)" } ?? "")")
        }
        return 0
    }

    // MARK: run (live provider)

    static func run(_ args: [String]) async throws -> Int32 {
        guard let repoPath = value("--repo", in: args), let diagPath = value("--diagnostic-file", in: args) else { usage(); return 2 }
        let providerID = value("--provider", in: args) ?? ClaudeCodeAdapter.id
        let repo = URL(fileURLWithPath: repoPath)
        let diag = try DiagnosticIntake.fromFile(URL(fileURLWithPath: diagPath))
        let recipe = try value("--check", in: args).map { cmd in
            VerificationRecipe(argv: try CommandLineParser.parse(cmd), display: cmd).approving()
        }
        let budget = Double(value("--budget", in: args) ?? "1.0") ?? 1.0
        let paths = AppPaths.standard()
        let orchestrator = try await RepairOrchestrator(paths: paths, adapters: [ClaudeCodeAdapter(), DemoAgentAdapter()])
        let snapshot = try await orchestrator.inspect(repo)
        line("Plan — nothing has run yet:")
        line("  provider:  \(providerID)  (budget cap $\(String(format: "%.2f", budget)))")
        line("  repo:      \(snapshot.root.path) @ \(snapshot.shortHead)\(snapshot.isDirty ? "  ⚠︎ uncommitted edits are NOT included" : "")")
        line("  worktree:  \(paths.worktrees.path)/<capsule-id>")
        line("  check:     \(recipe?.display ?? "none — result will be Not verified")")
        line("  sends:     the diagnostic below (\(diag.byteCount) bytes) to the provider; it may read files in the worktree")
        if !diag.findings.isEmpty { line("  ⚠︎ possible secrets in diagnostic: \(Set(diag.findings).sorted().joined(separator: ", ")) — redacted before sending") }
        guard args.contains("--yes") else {
            line("\nRe-run with --yes to start.")
            return 2
        }
        let text = SecretScanner().redact(diag.text)
        let capsule = try await orchestrator.createCapsule(RepairDraft(diagnostic: text, repoRoot: repo, providerID: providerID,
                                                                        recipe: recipe, budgetUSD: budget))
        let printer = await printEvents(orchestrator, capsule.id)
        try await orchestrator.start(capsule.id)
        await orchestrator.waitUntilIdle(capsule.id)
        try await Task.sleep(for: .milliseconds(100))
        printer.cancel()
        guard let done = await orchestrator.capsule(capsule.id) else { return 1 }
        line("\nFinal: \(done.status.label)\(done.patch.map { " · \($0.statsLine)" } ?? "")")
        if let p = done.patch, let diff = try? String(contentsOfFile: p.diffPath, encoding: .utf8) { line(diff) }
        if let err = done.lastError { line("Error: \(err.message)") }
        if args.contains("--apply") {
            guard done.status == .reviewReadyVerified else {
                line("Not applying: selected checks did not pass.")
                return 1
            }
            let outcome = try await orchestrator.apply(capsule.id)
            line("Applied to working tree (not committed). Undo: \(outcome.rollbackCommand.joined(separator: " "))")
        } else if let wt = done.worktreePath {
            line("Review the worktree at \(wt). Nothing was applied to your branch.")
        }
        return done.status == .reviewReadyVerified ? 0 : 1
    }
}

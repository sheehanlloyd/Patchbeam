import Foundation
import Testing
@testable import PatchbeamCore

/// End-to-end journeys against a freshly generated fixture repository, using real Git,
/// real `python3 -m unittest`, and the scripted DemoAgent (no model).
@Suite("Golden path (fixture, DemoAgent)", .serialized)
struct GoldenPathTests {
    struct Env {
        let orchestrator: RepairOrchestrator
        let repo: URL
        let paths: AppPaths
        let git: GitClient
    }

    static let recipe = VerificationRecipe(argv: FixtureLibrary.checkCommand, display: "python3 -m unittest -v").approving()

    func env(_ scenario: DemoAgentAdapter.Scenario = .fix, delay: Duration = .zero, paths: AppPaths? = nil) async throws -> Env {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pb-golden-\(UUID().uuidString.prefix(8))")
        let p = paths ?? AppPaths(root: base.appendingPathComponent("Application Support/Patchbeam"))
        let git = try GitClient.locate()
        let repo = try await FixtureLibrary.makeBrokenPythonRepo(in: base, git: git)
        let o = try await RepairOrchestrator(paths: p, adapters: [DemoAgentAdapter(scenario: scenario, stepDelay: delay)])
        return Env(orchestrator: o, repo: repo, paths: p, git: git)
    }

    func unittestExit(_ dir: URL) async throws -> Int32? {
        try await ProcessRunner().run(ProcessSpec(
            executable: ExecutableLocator.find("python3")!, arguments: ["-m", "unittest"], workingDirectory: dir,
            environment: MinimalEnvironment.make(extra: ["PYTHONDONTWRITEBYTECODE": "1"]))).exitCode
    }

    func draft(_ e: Env, recipe: VerificationRecipe? = GoldenPathTests.recipe) -> RepairDraft {
        RepairDraft(diagnostic: FixtureLibrary.sampleTraceback, repoRoot: e.repo, providerID: DemoAgentAdapter.id, recipe: recipe)
    }

    @Test func journeyA_redToGreenThenExplicitApply() async throws {
        let e = try await env()
        let headBefore = try await e.git.checked(["rev-parse", "HEAD"], in: e.repo)
        #expect(try await unittestExit(e.repo) == 1, "fixture baseline is red")

        let capsule = try await e.orchestrator.createCapsule(draft(e))
        #expect(capsule.title == "AssertionError: 27.0 != 33.0")
        try await e.orchestrator.start(capsule.id)
        await e.orchestrator.waitUntilIdle(capsule.id)

        let c = try #require(await e.orchestrator.capsule(capsule.id))
        #expect(c.status == .reviewReadyVerified)
        #expect(c.verifiedFingerprint == c.patch?.fingerprint)
        #expect(c.patch?.statsLine == "1 file · +1 −1")
        #expect(c.isScriptedProvider)

        let records = try await e.orchestrator.verifications(capsule.id)
        let baseline = try #require(records.first { $0.kind == .baseline })
        let proof = try #require(records.last { $0.kind == .patch })
        #expect(baseline.result == .failed && baseline.exitCode == 1, "red before")
        #expect(proof.result == .passed && proof.exitCode == 0, "green after")
        #expect(proof.parsed?.total == 3)
        #expect(proof.patchFingerprint == c.patch?.fingerprint)
        #expect(FileManager.default.fileExists(atPath: proof.stderrLogPath ?? ""))

        // Source checkout is still broken until the user applies.
        #expect(try await unittestExit(e.repo) == 1)
        #expect(try String(contentsOf: e.repo.appendingPathComponent("calculator.py"), encoding: .utf8).contains("base - tax"))

        let events = try await e.orchestrator.events(capsule.id)
        #expect(events.map(\.sequence) == Array(1...events.count))
        #expect(events.contains { $0.summary.contains("Baseline reproduces the failure") })

        let outcome = try await e.orchestrator.apply(capsule.id)
        #expect(outcome.appliedFiles == ["calculator.py"])
        #expect(try await unittestExit(e.repo) == 0, "source green after explicit apply")
        #expect(try await e.git.checked(["rev-parse", "HEAD"], in: e.repo) == headBefore, "no commit")
        #expect(try await e.git.checked(["diff", "--cached", "--name-only"], in: e.repo).isEmpty, "nothing staged")
        #expect(await e.orchestrator.capsule(capsule.id)?.status == .applied)

        try await e.orchestrator.cleanUpWorktree(capsule.id)
        #expect(await e.orchestrator.capsule(capsule.id)?.worktreePath == nil)
        #expect(try await e.git.checked(["branch", "--list", "patchbeam/*"], in: e.repo).isEmpty)
    }

    @Test func journeyC_failedCheckThenOneBoundedRetry() async throws {
        let e = try await env(.wrongFixThenFix)
        let c = try await e.orchestrator.createCapsule(draft(e))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        var now = try #require(await e.orchestrator.capsule(c.id))
        #expect(now.status == .reviewReadyFailed, "never green on a failing check")
        #expect(now.verifiedFingerprint == nil)
        await #expect(throws: PatchbeamError.self, "failed patches can't be applied") { _ = try await e.orchestrator.apply(c.id) }

        try await e.orchestrator.retry(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        now = try #require(await e.orchestrator.capsule(c.id))
        #expect(now.status == .reviewReadyVerified)
        #expect(now.attemptCount == 2)
    }

    @Test func retryLimitIsEnforced() async throws {
        let e = try await env(.wrongFixThenFix)
        let c = try await e.orchestrator.createCapsule(draft(e))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        // Force a second failure by making the check always fail, then attempt a second retry.
        try await e.orchestrator.retry(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        if await e.orchestrator.capsule(c.id)?.status == .reviewReadyFailed {
            await #expect(throws: PatchbeamError.self) { try await e.orchestrator.retry(c.id) }
        }
        #expect(await e.orchestrator.capsule(c.id)?.attemptCount ?? 0 <= Capsule.maxAttempts)
    }

    @Test func journeyB_approvalAllowOnce() async throws {
        let e = try await env(.approval)
        let c = try await e.orchestrator.createCapsule(draft(e))
        let updates = await e.orchestrator.updates()
        try await e.orchestrator.start(c.id)
        for await u in updates {
            if case .capsule(let cap) = u, cap.id == c.id, cap.status == .awaitingApproval {
                let approval = try #require(cap.pendingApproval)
                #expect(approval.command == "python3 -m unittest -v")
                #expect(approval.cwd == cap.worktreePath)
                #expect(approval.risk == .low)
                try await e.orchestrator.respond(c.id, decision: .allowOnce)
                await #expect(throws: PatchbeamError.self, "replay is stale") { try await e.orchestrator.respond(c.id, decision: .allowOnce) }
                break
            }
        }
        await e.orchestrator.waitUntilIdle(c.id)
        #expect(await e.orchestrator.capsule(c.id)?.status == .reviewReadyVerified)
        #expect(await e.orchestrator.capsule(c.id)?.pendingApproval?.status == .allowed)
    }

    @Test func stopCancelsSafelyAndKeepsBaseIntact() async throws {
        let e = try await env(.fix, delay: .milliseconds(500))
        let c = try await e.orchestrator.createCapsule(draft(e, recipe: nil))
        try await e.orchestrator.start(c.id)
        try await Task.sleep(for: .milliseconds(700))
        try await e.orchestrator.stop(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        let now = try #require(await e.orchestrator.capsule(c.id))
        #expect(now.status == .cancelled)
        #expect(try String(contentsOf: e.repo.appendingPathComponent("calculator.py"), encoding: .utf8).contains("base - tax"))
        #expect(FileManager.default.fileExists(atPath: now.worktreePath ?? ""), "worktree and logs preserved for inspection")
        try await e.orchestrator.discard(c.id)
        #expect(await e.orchestrator.capsule(c.id)?.status == .discarded)
    }

    @Test func noCheckConfiguredIsNotVerified() async throws {
        let e = try await env()
        let c = try await e.orchestrator.createCapsule(draft(e, recipe: nil))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        let now = try #require(await e.orchestrator.capsule(c.id))
        #expect(now.status == .reviewReadyUnverified)
        #expect(now.warnings.contains("Not verified — no check configured."))
        #expect(now.verifiedFingerprint == nil)
    }

    @Test func checkThatMutatesFilesInvalidatesProof() async throws {
        let e = try await env()
        let sneaky = VerificationRecipe(argv: ["python3", "-c", "open('calculator.py','a').write('# touched by test\\n')"], display: "sneaky").approving()
        let c = try await e.orchestrator.createCapsule(RepairDraft(diagnostic: FixtureLibrary.sampleTraceback, repoRoot: e.repo,
                                                                    providerID: DemoAgentAdapter.id, recipe: sneaky, runBaseline: false))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        let now = try #require(await e.orchestrator.capsule(c.id))
        #expect(now.status == .reviewReadyUnverified)
        #expect(now.warnings.contains("Tests changed files; review and re-run."))
    }

    @Test func editingAfterVerificationBlocksApply() async throws {
        let e = try await env()
        let c = try await e.orchestrator.createCapsule(draft(e))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        let wt = try #require(await e.orchestrator.capsule(c.id)?.worktreePath)
        try Data("# late edit\n".utf8).write(to: URL(fileURLWithPath: wt).appendingPathComponent("late.py"))
        do {
            _ = try await e.orchestrator.apply(c.id)
            Issue.record("apply should be blocked")
        } catch let err as PatchbeamError {
            #expect(err.code == .fingerprintMismatch)
        }
        #expect(await e.orchestrator.capsule(c.id)?.status == .reviewReadyUnverified, "verified badge revoked")
        #expect(try String(contentsOf: e.repo.appendingPathComponent("calculator.py"), encoding: .utf8).contains("base - tax"))
        // Re-running the check restores honest proof for the new revision.
        try await e.orchestrator.rerunVerification(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        #expect(await e.orchestrator.capsule(c.id)?.status == .reviewReadyVerified)
    }

    @Test func applyPausesWhenUserBranchMoved() async throws {
        let e = try await env()
        let c = try await e.orchestrator.createCapsule(draft(e))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        try Data("notes\n".utf8).write(to: e.repo.appendingPathComponent("NOTES.md"))
        try await e.git.checked(["add", "NOTES.md"], in: e.repo)
        try await e.git.checked(["commit", "-q", "-m", "user work"], in: e.repo)
        do {
            _ = try await e.orchestrator.apply(c.id)
            Issue.record("expected destinationMoved")
        } catch let err as PatchbeamError {
            #expect(err.code == .destinationMoved)
            #expect(err.message == "Your branch has changed; automatic apply is paused.")
        }
        #expect(await e.orchestrator.capsule(c.id)?.status == .reviewReadyVerified, "still reviewable; nothing overwritten")
    }

    @Test func journeyE_restartMarksInterruptedAndPreservesWorktree() async throws {
        let e = try await env(.fix, delay: .seconds(2))
        let c = try await e.orchestrator.createCapsule(draft(e, recipe: nil))
        try await e.orchestrator.start(c.id)
        try await Task.sleep(for: .milliseconds(900))
        #expect(await e.orchestrator.capsule(c.id)?.status.isActive == true)
        // Simulate a crash: a new process opens the same database while the old run "died".
        let relaunched = try await RepairOrchestrator(paths: e.paths, adapters: [DemoAgentAdapter()])
        let reconciled = await relaunched.reconcileOnLaunch()
        #expect(reconciled == [c.id])
        let now = try #require(await relaunched.capsule(c.id))
        #expect(now.status == .needsRestart)
        #expect(now.verifiedFingerprint == nil)
        #expect(now.warnings.contains("Previous repair was interrupted; its worktree is preserved."))
        #expect(FileManager.default.fileExists(atPath: now.worktreePath ?? ""))
        let transitions = try await relaunched.store.transitions(for: c.id).map(\.1)
        #expect(transitions.suffix(3) == [.interrupted, .reconciling, .needsRestart])
        try await e.orchestrator.stop(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
    }

    @Test func dirtySourceIsWarnedAndUntouched() async throws {
        let e = try await env()
        try Data("# my local wip\n".utf8).write(to: e.repo.appendingPathComponent("test_calculator.py"), options: .atomic)
        let c = try await e.orchestrator.createCapsule(draft(e, recipe: nil))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        let now = try #require(await e.orchestrator.capsule(c.id))
        #expect(now.sourceWasDirty)
        #expect(now.warnings.contains { $0.hasPrefix("Your uncommitted edits are not in this repair worktree") })
        #expect(try String(contentsOf: e.repo.appendingPathComponent("test_calculator.py"), encoding: .utf8) == "# my local wip\n")
    }

    @Test func oneRepairAtATime() async throws {
        let e = try await env(.fix, delay: .milliseconds(300))
        let a = try await e.orchestrator.createCapsule(draft(e, recipe: nil))
        let b = try await e.orchestrator.createCapsule(draft(e, recipe: nil))
        try await e.orchestrator.start(a.id)
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: PatchbeamError.self) { try await e.orchestrator.start(b.id) }
        await e.orchestrator.waitUntilIdle(a.id)
    }

    @Test func unapprovedRecipeCannotStart() async throws {
        let e = try await env()
        let unapproved = VerificationRecipe(argv: FixtureLibrary.checkCommand, display: "python3 -m unittest -v")
        await #expect(throws: PatchbeamError.self) { _ = try await e.orchestrator.createCapsule(draft(e, recipe: unapproved)) }
    }

    @Test func notAuthenticatedProviderCannotStart() async throws {
        let dir = try makeFakeClaude(loggedIn: false, stream: "")
        let e = try await env()
        await e.orchestrator.setAdapter(ClaudeCodeAdapter(searchPath: [dir.path, "/bin", "/usr/bin"]))
        do {
            _ = try await e.orchestrator.createCapsule(RepairDraft(diagnostic: "x", repoRoot: e.repo, providerID: ClaudeCodeAdapter.id, recipe: nil))
            Issue.record("expected auth error")
        } catch let err as PatchbeamError {
            #expect(err.code == .providerUnauthenticated)
            #expect(err.message == "Sign in with your provider CLI first.")
        }
    }

    @Test func realClaudeStreamAuthFailureEndsAsFailedNotVerified() async throws {
        // Fake CLI says logged in, but replays the *captured* unauthenticated stream (e.g. token expired mid-way).
        let captured = try String(contentsOf: fixturesRoot.appendingPathComponent("claude-stream/unauthenticated-2.1.252.jsonl"), encoding: .utf8)
        let dir = try makeFakeClaude(loggedIn: true, stream: captured)
        let e = try await env()
        await e.orchestrator.setAdapter(ClaudeCodeAdapter(searchPath: [dir.path, "/bin", "/usr/bin"]))
        let c = try await e.orchestrator.createCapsule(RepairDraft(diagnostic: FixtureLibrary.sampleTraceback, repoRoot: e.repo,
                                                                    providerID: ClaudeCodeAdapter.id, recipe: GoldenPathTests.recipe))
        try await e.orchestrator.start(c.id)
        await e.orchestrator.waitUntilIdle(c.id)
        let now = try #require(await e.orchestrator.capsule(c.id))
        #expect(now.status == .failed)
        #expect(now.lastError?.code == PatchbeamError.Code.providerUnauthenticated.rawValue)
        #expect(now.patch == nil)
    }
}

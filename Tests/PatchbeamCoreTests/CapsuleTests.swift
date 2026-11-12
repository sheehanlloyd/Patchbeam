import Foundation
import Testing
@testable import PatchbeamCore

func makeCapsule(status: CapsuleStatus = .draft) -> Capsule {
    var c = Capsule(projectID: UUID(), repoRoot: "/tmp/repo", repoDisplayName: "repo", title: "AssertionError",
                    sanitizedDiagnostic: "trace", providerID: "demo", providerDisplayName: "DemoAgent",
                    isScriptedProvider: true, recipe: nil)
    c.status = status
    return c
}

func passingProof(for c: Capsule, fingerprint: String) -> VerificationRecord {
    VerificationRecord(id: UUID(), capsuleID: c.id, kind: .patch, patchFingerprint: fingerprint, argv: ["python3"],
                       executablePath: "/usr/bin/python3", cwd: "/tmp", startedAt: Date(), endedAt: Date(),
                       exitCode: 0, signal: nil, stdoutLogPath: nil, stderrLogPath: nil, outputTail: "OK",
                       parsed: nil, result: .passed, warnings: [])
}

func patch(_ fp: String) -> PatchArtifact {
    PatchArtifact(baseCommit: "abc", fingerprint: fp, changedFiles: [ChangedFile(path: "a.py", kind: .modified, additions: 1, deletions: 1, isBinary: false)],
                  diffPath: "/tmp/d", diffByteCount: 10, generatedAt: Date())
}

@Suite("Capsule state machine")
struct StateMachineTests {
    @Test func goldenPathTransitionsAreLegal() throws {
        var c = makeCapsule()
        for s: CapsuleStatus in [.ready, .preparingWorktree, .queued, .running, .verifying] {
            try CapsuleStateMachine.transition(&c, to: s)
        }
        c.patch = patch("fp1")
        try CapsuleStateMachine.transition(&c, to: .reviewReadyVerified, proof: passingProof(for: c, fingerprint: "fp1"))
        #expect(c.verifiedFingerprint == "fp1")
        try CapsuleStateMachine.transition(&c, to: .applied)
        #expect(c.disposition == .applied)
    }

    @Test func illegalTransitionsThrow() {
        var c = makeCapsule()
        #expect(throws: PatchbeamError.self) { try CapsuleStateMachine.transition(&c, to: .applied) }
        var done = makeCapsule(status: .discarded)
        #expect(throws: PatchbeamError.self) { try CapsuleStateMachine.transition(&done, to: .running) }
    }

    @Test func verifiedRequiresHostProofNotModelText() {
        var c = makeCapsule(status: .verifying)
        c.patch = patch("fp1")
        // No proof at all (e.g. the model said "all tests pass").
        #expect(throws: PatchbeamError.self) { try CapsuleStateMachine.transition(&c, to: .reviewReadyVerified) }
        // Proof for a different patch revision.
        #expect(throws: PatchbeamError.self) {
            try CapsuleStateMachine.transition(&c, to: .reviewReadyVerified, proof: passingProof(for: c, fingerprint: "stale"))
        }
        // A failing proof.
        var failing = passingProof(for: c, fingerprint: "fp1")
        failing.result = .failed
        failing.exitCode = 1
        #expect(throws: PatchbeamError.self) { try CapsuleStateMachine.transition(&c, to: .reviewReadyVerified, proof: failing) }
        // A baseline record can never verify the patch.
        var baseline = passingProof(for: c, fingerprint: "fp1")
        baseline.kind = .baseline
        #expect(throws: PatchbeamError.self) { try CapsuleStateMachine.transition(&c, to: .reviewReadyVerified, proof: baseline) }
        // Proof from another capsule.
        let other = makeCapsule()
        #expect(throws: PatchbeamError.self) {
            try CapsuleStateMachine.transition(&c, to: .reviewReadyVerified, proof: passingProof(for: other, fingerprint: "fp1"))
        }
        #expect(c.status == .verifying)
    }

    @Test func reverifyingInvalidatesPriorProof() throws {
        var c = makeCapsule(status: .verifying)
        c.patch = patch("fp1")
        try CapsuleStateMachine.transition(&c, to: .reviewReadyVerified, proof: passingProof(for: c, fingerprint: "fp1"))
        try CapsuleStateMachine.transition(&c, to: .verifying)
        #expect(c.verifiedFingerprint == nil)
    }

    @Test func retryIsBoundedToOne() throws {
        var c = makeCapsule(status: .reviewReadyFailed)
        c.attemptCount = 1
        #expect(c.canRetry)
        try CapsuleStateMachine.transition(&c, to: .retrying)
        #expect(c.attemptCount == 2)
        try CapsuleStateMachine.transition(&c, to: .running)
        try CapsuleStateMachine.transition(&c, to: .verifying)
        try CapsuleStateMachine.transition(&c, to: .reviewReadyFailed)
        #expect(!c.canRetry)
    }

    @Test func everyActiveStateCanBeInterrupted() {
        for s in CapsuleStatus.allCases where s.isActive && s != .reconciling {
            #expect(CapsuleStateMachine.canTransition(from: s, to: .interrupted), "\(s)")
        }
    }

    @Test func transitionIsIdempotent() throws {
        var c = makeCapsule(status: .running)
        try CapsuleStateMachine.transition(&c, to: .running)
        #expect(c.status == .running)
    }

    @Test func recipeApprovalIsTiedToExactArgv() {
        var r = VerificationRecipe(argv: ["python3", "-m", "unittest"], display: "python3 -m unittest").approving()
        #expect(r.isApproved)
        r.argv.append("-v")
        #expect(!r.isApproved, "editing the command requires re-approval")
    }
}

@Suite("CapsuleStore")
struct StoreTests {
    func tempStore() throws -> (CapsuleStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pb-store-\(UUID().uuidString)")
        return (try CapsuleStore(path: dir.appendingPathComponent("db.sqlite")), dir)
    }

    @Test func migratesToLatestSchema() async throws {
        let (store, _) = try tempStore()
        #expect(try await store.schemaVersionInstalled() == CapsuleStore.schemaVersion)
    }

    @Test func migrationsAreIdempotentAcrossReopen() async throws {
        let (store, dir) = try tempStore()
        let c = makeCapsule()
        try await store.save(c)
        let reopened = try CapsuleStore(path: dir.appendingPathComponent("db.sqlite"))
        #expect(try await reopened.capsule(c.id) == c)
        #expect(try await reopened.schemaVersionInstalled() == CapsuleStore.schemaVersion)
    }

    @Test func savesCapsuleAndTransitionAudit() async throws {
        let (store, _) = try tempStore()
        var c = makeCapsule()
        try await store.save(c)
        let from = c.status
        try CapsuleStateMachine.transition(&c, to: .ready)
        try await store.save(c, transitionFrom: from)
        let loaded = try await store.capsule(c.id)
        #expect(loaded?.status == .ready)
        let audit = try await store.transitions(for: c.id)
        #expect(audit.count == 1 && audit[0].0 == .draft && audit[0].1 == .ready)
    }

    @Test func duplicateEventsAreIgnored() async throws {
        let (store, _) = try tempStore()
        let id = UUID()
        let e = AgentEvent(capsuleID: id, sequence: 1, kind: .message, phase: .diagnosing, summary: "hi")
        #expect(try await store.append(e))
        #expect(try await !store.append(e))
        #expect(try await store.events(for: id).count == 1)
        #expect(try await store.nextSequence(for: id) == 2)
    }

    @Test func deleteAllClearsHistory() async throws {
        let (store, _) = try tempStore()
        try await store.save(makeCapsule())
        try await store.upsert(Project(canonicalRoot: "/r", displayName: "r"))
        try await store.deleteAll()
        #expect(try await store.allCapsules().isEmpty)
        #expect(try await store.recentProjects().isEmpty)
    }

    @Test func projectUpsertKeysOnCanonicalRoot() async throws {
        let (store, _) = try tempStore()
        var p = Project(canonicalRoot: "/r", displayName: "r")
        try await store.upsert(p)
        p.recipe = VerificationRecipe(argv: ["make"], display: "make")
        try await store.upsert(p)
        #expect(try await store.recentProjects().count == 1)
        #expect(try await store.project(root: "/r")?.recipe?.argv == ["make"])
    }
}

@Suite("Event normalization")
struct EventSequencerTests {
    @Test func dedupesByProviderIDAndOrders() {
        var seq = EventSequencer()
        let id = UUID()
        let a = AgentEvent(capsuleID: id, kind: .toolStarted, phase: .editing, summary: "a", providerEventID: "p1")
        let b = AgentEvent(capsuleID: id, kind: .toolFinished, phase: .editing, summary: "b", providerEventID: "p2")
        let out = [a, b, a, b].compactMap { seq.accept($0) }
        #expect(out.map(\.sequence) == [1, 2])
        #expect(out.map(\.summary) == ["a", "b"])
    }

    @Test func eventsWithoutProviderIDAreKept() {
        var seq = EventSequencer(startingAt: 10)
        let id = UUID()
        let e = AgentEvent(capsuleID: id, kind: .heartbeat, phase: .editing, summary: "tick")
        #expect(seq.accept(e)?.sequence == 10)
        #expect(seq.accept(e)?.sequence == 11)
    }
}

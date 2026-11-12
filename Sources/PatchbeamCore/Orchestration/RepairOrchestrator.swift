import Foundation

public struct RepairDraft: Sendable {
    public var diagnostic: String
    public var title: String?
    public var userGoal: String?
    public var repoRoot: URL
    public var providerID: String
    public var recipe: VerificationRecipe?
    /// Run the check on the untouched base first to record red-before evidence (PRD §13).
    public var runBaseline: Bool
    public var budgetUSD: Double
    public var timeout: Duration

    public init(diagnostic: String, title: String? = nil, userGoal: String? = nil, repoRoot: URL, providerID: String,
                recipe: VerificationRecipe?, runBaseline: Bool = true, budgetUSD: Double = 1.0, timeout: Duration = .seconds(900)) {
        self.diagnostic = diagnostic
        self.title = title
        self.userGoal = userGoal
        self.repoRoot = repoRoot
        self.providerID = providerID
        self.recipe = recipe
        self.runBaseline = runBaseline
        self.budgetUSD = budgetUSD
        self.timeout = timeout
    }
}

public enum OrchestratorUpdate: Sendable {
    case capsule(Capsule)
    case event(AgentEvent)
    case verification(VerificationRecord)
    case removed(UUID)
}

/// Coordinates the golden path. Owns all capsule state changes; adapters only emit events.
/// Every transition is persisted before it is published to the UI.
public actor RepairOrchestrator {
    public let paths: AppPaths
    public let store: CapsuleStore
    public let git: GitClient
    private let inspector: RepositoryInspector
    private let worktrees: WorktreeManager
    private let diffs: DiffService
    private let verifier: VerificationRunner
    private let applier: ApplyService
    private var adapters: [String: any AgentAdapter]

    private var cache: [UUID: Capsule] = [:]
    private var drafts: [UUID: RepairDraft] = [:]
    private var sessions: [UUID: any AgentSession] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var sequencers: [UUID: EventSequencer] = [:]
    private var subscribers: [UUID: AsyncStream<OrchestratorUpdate>.Continuation] = [:]

    public init(paths: AppPaths = .standard(), adapters: [any AgentAdapter], verifier: VerificationRunner = VerificationRunner()) async throws {
        try paths.ensureExists()
        self.paths = paths
        self.store = try CapsuleStore(path: paths.database)
        self.git = try GitClient.locate()
        self.inspector = RepositoryInspector(git: git)
        self.worktrees = WorktreeManager(git: git, paths: paths)
        self.diffs = DiffService(git: git)
        self.verifier = verifier
        self.applier = ApplyService(git: git)
        self.adapters = Dictionary(adapters.map { ($0.descriptor.id, $0) }, uniquingKeysWith: { a, _ in a })
        for c in try await store.allCapsules() { cache[c.id] = c }
    }

    // MARK: Subscriptions

    public func updates() -> AsyncStream<OrchestratorUpdate> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<OrchestratorUpdate>.makeStream(bufferingPolicy: .unbounded)
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }

    private func publish(_ update: OrchestratorUpdate) {
        for c in subscribers.values { c.yield(update) }
    }

    // MARK: Queries

    public func allCapsules() -> [Capsule] { cache.values.sorted { $0.updatedAt > $1.updatedAt } }
    public func capsule(_ id: UUID) -> Capsule? { cache[id] }
    public func events(_ id: UUID) async throws -> [AgentEvent] { try await store.events(for: id) }
    public func verifications(_ id: UUID) async throws -> [VerificationRecord] { try await store.verifications(for: id) }
    public func adapter(_ id: String) -> (any AgentAdapter)? { adapters[id] }
    public func providerDescriptors() -> [ProviderDescriptor] { adapters.values.map(\.descriptor).sorted { $0.isScripted && !$1.isScripted ? false : $0.id < $1.id } }
    public func setAdapter(_ adapter: any AgentAdapter) { adapters[adapter.descriptor.id] = adapter }

    public func probe(_ providerID: String) async -> ProviderAvailability? {
        guard let a = adapters[providerID] else { return nil }
        return await a.probe()
    }

    public func inspect(_ folder: URL) async throws -> RepositorySnapshot {
        try await inspector.inspect(folder)
    }

    public func recentProjects() async throws -> [Project] { try await store.recentProjects() }

    /// The user explicitly authorized this repository root (PB-003).
    @discardableResult
    public func authorizeProject(_ snapshot: RepositorySnapshot, recipe: VerificationRecipe?) async throws -> Project {
        var project = try await store.project(root: snapshot.root.path) ?? Project(canonicalRoot: snapshot.root.path, displayName: snapshot.displayName)
        if let recipe { project.recipe = recipe }
        project.lastUsed = Date()
        try await store.upsert(project)
        return project
    }

    // MARK: State helpers

    private func persist(_ c: Capsule, from: CapsuleStatus?) async throws {
        try await store.save(c, transitionFrom: from)
        cache[c.id] = c
        publish(.capsule(c))
    }

    private func mutate(_ id: UUID, _ body: (inout Capsule) throws -> Void) async throws {
        guard var c = cache[id] else { throw PatchbeamError(.notFound, "That repair no longer exists.") }
        let from = c.status
        try body(&c)
        c.updatedAt = Date()
        try await persist(c, from: from)
    }

    private func move(_ id: UUID, to status: CapsuleStatus, proof: VerificationRecord? = nil, _ extra: ((inout Capsule) -> Void)? = nil) async throws {
        try await mutate(id) { c in
            extra?(&c)
            try CapsuleStateMachine.transition(&c, to: status, proof: proof)
        }
    }

    private func record(_ id: UUID, _ raw: AgentEvent) async {
        var seq: EventSequencer
        if let existing = sequencers[id] {
            seq = existing
        } else {
            seq = EventSequencer(startingAt: (try? await store.nextSequence(for: id)) ?? 1)
        }
        guard let e = seq.accept(raw) else { sequencers[id] = seq; return }
        sequencers[id] = seq
        _ = try? await store.append(e)
        publish(.event(e))
    }

    private func host(_ id: UUID, _ phase: AgentEvent.Phase, _ summary: String, _ meta: [String: String] = [:]) async {
        await record(id, AgentEvent(capsuleID: id, kind: .host, phase: phase, summary: summary, metadata: meta))
    }

    private func status(_ id: UUID) -> CapsuleStatus? { cache[id]?.status }
    private func isCancelling(_ id: UUID) -> Bool { status(id) == .cancelling }

    private func fail(_ id: UUID, _ error: PatchbeamError) async {
        await host(id, .done, error.message, ["code": error.code.rawValue])
        if status(id) == .cancelling {
            try? await move(id, to: .cancelled)
            return
        }
        try? await move(id, to: .failed) { $0.lastError = PatchbeamErrorInfo(error) }
    }

    // MARK: Lifecycle

    public func createCapsule(_ draft: RepairDraft) async throws -> Capsule {
        guard let adapter = adapters[draft.providerID] else {
            throw PatchbeamError(.providerMissing, "Unknown provider \(draft.providerID).")
        }
        let availability = await adapter.probe()
        guard availability.isReady else {
            throw PatchbeamError(availability.state == .notAuthenticated ? .providerUnauthenticated : .providerMissing,
                                 availability.message, recovery: availability.setupHint)
        }
        let diag = try DiagnosticIntake.fromText(draft.diagnostic)
        let snapshot = try await inspector.inspect(draft.repoRoot)
        guard snapshot.head != nil else {
            throw PatchbeamError(.unbornHead, "This repository has no commits yet, so there's no base to repair from.",
                                 recovery: "Make a first commit, then try again.")
        }
        if let recipe = draft.recipe, !recipe.isApproved {
            throw PatchbeamError(.commandNotApproved, "Approve the check command before starting.")
        }
        let project = try await authorizeProject(snapshot, recipe: draft.recipe)
        var c = Capsule(projectID: project.id, repoRoot: snapshot.root.path, repoDisplayName: snapshot.displayName,
                        title: draft.title ?? DiagnosticIntake.inferTitle(diag.text), sanitizedDiagnostic: diag.text,
                        userGoal: draft.userGoal, providerID: adapter.descriptor.id, providerDisplayName: adapter.descriptor.displayName,
                        isScriptedProvider: adapter.descriptor.isScripted, recipe: draft.recipe)
        if draft.recipe == nil { c.warnings.append("Not verified — no check configured.") }
        if diag.truncated { c.warnings.append("The diagnostic was over \(DiagnosticIntake.maxBytes / 1000) KB; the middle was omitted.") }
        try CapsuleStateMachine.transition(&c, to: .ready)
        try await persist(c, from: nil)
        drafts[c.id] = draft
        await host(c.id, .preparing, "Repair created for \(snapshot.displayName) with \(adapter.descriptor.displayName)")
        return c
    }

    /// Begin the run in the background. Returns once the task is scheduled.
    public func start(_ id: UUID) async throws {
        guard let c = cache[id], c.status == .ready else {
            throw PatchbeamError(.invalidTransition, "This repair can't be started from its current state.")
        }
        if let other = cache.values.first(where: { $0.id != id && $0.status.isActive }) {
            throw PatchbeamError(.invalidTransition, "Another repair (\(other.repoDisplayName)) is already running.",
                                 recovery: "Patchbeam v1 runs one repair at a time. Stop it or wait for review.")
        }
        tasks[id] = Task { await self.runPipeline(id, retryEvidence: nil) }
    }

    /// Wait for the background task of a capsule (used by the CLI and tests).
    public func waitUntilIdle(_ id: UUID) async {
        while let t = tasks[id] {
            await t.value
            if tasks[id] == t { tasks[id] = nil }
        }
    }

    private func runPipeline(_ id: UUID, retryEvidence: String?) async {
        defer { tasks[id] = nil; sessions[id] = nil }
        do {
            if retryEvidence == nil {
                try await prepareWorktree(id)
            }
            guard !isCancelling(id) else { try await move(id, to: .cancelled); return }
            try await runAgent(id, retryEvidence: retryEvidence)
            guard let s = status(id), s == .running else {
                if isCancelling(id) { try await move(id, to: .cancelled) }
                return
            }
            try await snapshotAndVerify(id)
        } catch let e as PatchbeamError {
            await fail(id, e)
        } catch is CancellationError {
            try? await move(id, to: .cancelled)
        } catch {
            await fail(id, PatchbeamError(.providerFailed, "The repair stopped unexpectedly.", detail: String(describing: error)))
        }
    }

    private func prepareWorktree(_ id: UUID) async throws {
        try await move(id, to: .preparingWorktree)
        guard let c = cache[id] else { return }
        let snapshot = try await inspector.inspect(URL(fileURLWithPath: c.repoRoot))
        guard let head = snapshot.head else {
            throw PatchbeamError(.unbornHead, "This repository has no commits yet, so there's no base to repair from.")
        }
        if snapshot.isDirty {
            await host(id, .preparing, "Your uncommitted edits are not in this repair worktree.", ["dirtyFiles": String(snapshot.dirtyPaths.count)])
        }
        let wt = try await worktrees.create(repoRoot: snapshot.root, capsuleID: id, baseCommit: head)
        try await mutate(id) { c in
            c.baseCommit = head
            c.baseBranch = snapshot.branch
            c.sourceWasDirty = snapshot.isDirty
            c.worktreePath = wt.path
            c.branchName = wt.branch
            if snapshot.isDirty && !c.warnings.contains(where: { $0.hasPrefix("Your uncommitted edits") }) {
                c.warnings.append("Your uncommitted edits are not in this repair worktree (it starts from \(snapshot.shortHead)).")
            }
        }
        await host(id, .preparing, "Created worktree on \(wt.branch) from \(String(head.prefix(8)))", ["path": wt.path])
        try await move(id, to: .queued)

        if let recipe = cache[id]?.recipe, recipe.isApproved, drafts[id]?.runBaseline ?? true {
            await host(id, .diagnosing, "Running baseline check on the untouched base: \(recipe.display)")
            let baseline = await verifier.run(recipe: recipe, capsuleID: id, kind: .baseline, worktree: URL(fileURLWithPath: wt.path),
                                              logDirectory: paths.capsuleDirectory(id), patchFingerprint: nil)
            try await store.save(baseline)
            publish(.verification(baseline))
            try await mutate(id) { $0.baselineResult = baseline.result }
            let summary: String = switch baseline.result {
            case .failed: "Baseline reproduces the failure: \(baseline.headline)"
            case .passed: "Baseline already passes — the reported failure may not reproduce with this check."
            default: "Baseline: \(baseline.headline)"
            }
            await host(id, .diagnosing, summary, ["exitCode": baseline.exitCode.map(String.init) ?? "none"])
            // The baseline must not leave changes behind that would leak into the patch.
            let after = try await diffs.snapshot(worktree: URL(fileURLWithPath: wt.path), baseCommit: head, outputDirectory: paths.capsuleDirectory(id))
            if !after.artifact.isEmpty {
                try await mutate(id) { $0.warnings.append("The baseline check modified files; those changes are part of the patch.") }
            }
        }
    }

    private func runAgent(_ id: UUID, retryEvidence: String?) async throws {
        guard let c = cache[id], let adapter = adapters[c.providerID], let wt = c.worktreePath else {
            throw PatchbeamError(.notFound, "Repair is missing its worktree or provider.")
        }
        guard !isCancelling(id) else { return }
        try await move(id, to: .running) { c in if retryEvidence == nil { c.attemptCount = max(c.attemptCount, 1) } }
        let draft = drafts[id]
        let request = AgentRunRequest(
            capsuleID: id, worktree: URL(fileURLWithPath: wt), diagnostic: c.sanitizedDiagnostic, userGoal: c.userGoal,
            verificationDisplay: c.recipe?.display, previousFailure: retryEvidence,
            timeout: draft?.timeout ?? .seconds(900), budgetUSD: draft?.budgetUSD ?? 1.0, logDirectory: paths.capsuleDirectory(id))
        await host(id, .diagnosing, "Starting \(adapter.descriptor.displayName)\(retryEvidence == nil ? "" : " (retry with failure evidence)")")
        let session = try await adapter.start(request)
        sessions[id] = session
        if isCancelling(id) { await session.cancel() }

        var terminal: AgentEvent?
        for await event in session.events {
            // A pending approval is resolved by any later event (allow/deny/expiry on the provider side).
            if status(id) == .awaitingApproval && event.kind != .approvalRequested {
                try await move(id, to: .running) { c in
                    if c.pendingApproval?.status == .pending { c.pendingApproval?.status = .expired }
                }
            }
            await record(id, event)
            switch event.kind {
            case .sessionStarted:
                if let sid = event.metadata["sessionID"] { try await mutate(id) { $0.agentSessionID = sid } }
            case .approvalRequested:
                let approval = ApprovalRequest(
                    id: UUID(), capsuleID: id, providerRequestID: event.metadata["requestID"] ?? event.providerEventID ?? UUID().uuidString,
                    requester: c.providerDisplayName, command: event.metadata["command"], cwd: event.metadata["cwd"],
                    reason: event.metadata["reason"] ?? event.summary, scope: event.metadata["scope"] ?? "Repair worktree",
                    risk: ApprovalRisk(rawValue: event.metadata["risk"] ?? "") ?? .medium, createdAt: Date(),
                    expiresAt: event.metadata["expiresIn"].flatMap(Double.init).map { Date().addingTimeInterval($0) },
                    status: .pending, respondedAt: nil)
                if status(id) == .running {
                    try await move(id, to: .awaitingApproval) { $0.pendingApproval = approval }
                }
            case .completed:
                terminal = event
                try await mutate(id) { $0.agentSummary = event.summary }
            case .failed, .cancelled:
                terminal = event
            default:
                break
            }
        }
        sessions[id] = nil

        switch terminal?.kind {
        case .completed:
            return
        case .cancelled:
            if status(id) == .cancelling || status(id) == .running || status(id) == .awaitingApproval {
                if status(id) != .cancelling { try await move(id, to: .cancelling) }
                try await move(id, to: .cancelled)
            }
        default:
            if isCancelling(id) { try await move(id, to: .cancelled); return }
            let reason = terminal?.metadata["reason"]
            let code: PatchbeamError.Code = reason == "notAuthenticated" ? .providerUnauthenticated : .providerFailed
            throw PatchbeamError(code, terminal?.summary ?? "The agent ended without reporting a result.")
        }
    }

    private func snapshotAndVerify(_ id: UUID) async throws {
        guard let c = cache[id], let wt = c.worktreePath, let base = c.baseCommit else { return }
        let snap = try await diffs.snapshot(worktree: URL(fileURLWithPath: wt), baseCommit: base, outputDirectory: paths.capsuleDirectory(id))
        try await mutate(id) { $0.patch = snap.artifact }
        if snap.artifact.isEmpty {
            throw PatchbeamError(.noChanges, "The agent finished without changing any files.", recovery: "Review its message in Activity.")
        }
        await host(id, .reviewing, "Patch: \(snap.artifact.statsLine)", ["fingerprint": String(snap.artifact.fingerprint.prefix(12))])
        try await verifyCurrentPatch(id)
    }

    /// Host-owned proof: run the approved check against the exact current patch revision.
    private func verifyCurrentPatch(_ id: UUID) async throws {
        guard let c = cache[id], let wt = c.worktreePath, let base = c.baseCommit, let patch = c.patch else { return }
        guard let recipe = c.recipe, recipe.isApproved else {
            try await move(id, to: .reviewReadyUnverified)
            await host(id, .done, "Not verified — no check configured.")
            return
        }
        try await move(id, to: .verifying)
        await host(id, .verifying, "Running \(recipe.display) in the worktree")
        let worktreeURL = URL(fileURLWithPath: wt)
        var record = await verifier.run(recipe: recipe, capsuleID: id, kind: .patch, worktree: worktreeURL,
                                        logDirectory: paths.capsuleDirectory(id), patchFingerprint: patch.fingerprint)
        if isCancelling(id) || Task.isCancelled {
            record.result = .cancelled
            try await store.save(record)
            publish(.verification(record))
            if isCancelling(id) { try await move(id, to: .cancelled) }
            return
        }
        // Did the check itself change the files it was proving?
        let after = try await diffs.snapshot(worktree: worktreeURL, baseCommit: base, outputDirectory: paths.capsuleDirectory(id))
        if after.artifact.fingerprint != patch.fingerprint {
            record.result = .inconclusive
            record.warnings.append("Tests changed files; review and re-run.")
            try await mutate(id) { $0.patch = after.artifact }
        }
        try await store.save(record)
        publish(.verification(record))
        let detail = record.parsed.map { " · \($0.line)" } ?? ""
        await host(id, .verifying, "\(record.headline)\(detail)", ["exitCode": record.exitCode.map(String.init) ?? "none", "result": record.result.rawValue])

        switch record.result {
        case .passed:
            try await move(id, to: .reviewReadyVerified, proof: record)
        case .failed, .timedOut, .launchFailed:
            try await move(id, to: .reviewReadyFailed)
        case .inconclusive:
            try await move(id, to: .reviewReadyUnverified) { c in
                for w in record.warnings where !c.warnings.contains(w) { c.warnings.append(w) }
            }
        case .cancelled:
            try await move(id, to: .cancelling)
            try await move(id, to: .cancelled)
        }
    }

    // MARK: User actions

    public func stop(_ id: UUID) async throws {
        guard let s = status(id), [.preparingWorktree, .queued, .running, .awaitingApproval, .verifying, .retrying].contains(s) else { return }
        try await move(id, to: .cancelling) { c in
            if c.pendingApproval?.status == .pending { c.pendingApproval?.status = .denied }
        }
        await host(id, .done, "Stop requested — stopping the agent process group")
        if let session = sessions[id] { await session.cancel() }
        tasks[id]?.cancel()
    }

    public func respond(_ id: UUID, decision: ApprovalDecision) async throws {
        guard let c = cache[id], c.status == .awaitingApproval, var approval = c.pendingApproval, approval.status == .pending else {
            throw PatchbeamError(.approvalStale, "That request is no longer pending.")
        }
        guard let adapter = adapters[c.providerID], await adapter.probe().capabilities.approve else {
            throw PatchbeamError(.approvalUnsupported, "Approve this action in \(c.providerDisplayName)'s terminal.")
        }
        if approval.isExpired() {
            approval.status = .expired
            try await mutate(id) { $0.pendingApproval = approval }
            throw PatchbeamError(.approvalStale, "That request expired and was denied automatically.")
        }
        guard let session = sessions[id] else { throw PatchbeamError(.approvalStale, "The agent session has ended.") }
        approval.status = decision == .allowOnce ? .allowed : .denied
        approval.respondedAt = Date()
        try await move(id, to: .running) { $0.pendingApproval = approval }
        await host(id, .diagnosing, decision == .allowOnce ? "You allowed once: \(approval.command ?? approval.reason)" : "You denied: \(approval.command ?? approval.reason)")
        try await session.respond(to: approval.providerRequestID, decision: decision)
    }

    /// One user-approved follow-up with the failed check's output (PRD §6 Journey C).
    public func retry(_ id: UUID) async throws {
        guard let c = cache[id], c.canRetry else {
            throw PatchbeamError(.retryLimit, "This repair already used its one retry.", recovery: "Review the changes or start a new repair.")
        }
        let failure = try await store.verifications(for: id).last(where: { $0.kind == .patch })?.outputTail ?? "The check failed."
        try await move(id, to: .retrying)
        await host(id, .diagnosing, "Retry \(c.attemptCount + 1) of \(Capsule.maxAttempts) approved by you")
        tasks[id] = Task { await self.runPipeline(id, retryEvidence: failure) }
    }

    public func rerunVerification(_ id: UUID) async throws {
        guard let c = cache[id], [.reviewReadyVerified, .reviewReadyFailed, .reviewReadyUnverified, .kept].contains(c.status),
              let wt = c.worktreePath, let base = c.baseCommit, FileManager.default.fileExists(atPath: wt) else {
            throw PatchbeamError(.invalidTransition, "Nothing to re-verify.")
        }
        let snap = try await diffs.snapshot(worktree: URL(fileURLWithPath: wt), baseCommit: base, outputDirectory: paths.capsuleDirectory(id))
        if snap.artifact.fingerprint != c.patch?.fingerprint {
            await host(id, .reviewing, "Files changed since the last check; new patch \(snap.artifact.statsLine)")
        }
        try await mutate(id) { $0.patch = snap.artifact }
        tasks[id] = Task {
            do { try await self.verifyCurrentPatch(id) } catch let e as PatchbeamError { await self.fail(id, e) } catch {}
            self.clearTask(id)
        }
    }

    private func clearTask(_ id: UUID) { tasks[id] = nil }

    public func apply(_ id: UUID) async throws -> ApplyOutcome {
        guard let c = cache[id], c.status == .reviewReadyVerified || c.status == .reviewReadyUnverified,
              let wt = c.worktreePath, let base = c.baseCommit, let patch = c.patch else {
            throw PatchbeamError(.invalidTransition, "Only a reviewed, non-failing patch can be applied.")
        }
        // Re-derive the patch now; it must be the exact revision that was reviewed/verified.
        let snap = try await diffs.snapshot(worktree: URL(fileURLWithPath: wt), baseCommit: base, outputDirectory: paths.capsuleDirectory(id))
        if snap.artifact.fingerprint != patch.fingerprint {
            try await mutate(id) { c in
                c.patch = snap.artifact
                if c.status == .reviewReadyVerified { try CapsuleStateMachine.transition(&c, to: .reviewReadyUnverified) }
                c.warnings.append("Previous checks no longer match these files.")
            }
            throw PatchbeamError(.fingerprintMismatch, "Previous checks no longer match these files.", recovery: "Re-run verification, then apply.")
        }
        if c.status == .reviewReadyVerified, c.verifiedFingerprint != patch.fingerprint {
            throw PatchbeamError(.fingerprintMismatch, "Previous checks no longer match these files.", recovery: "Re-run verification.")
        }
        do {
            let outcome = try await applier.apply(patchFile: URL(fileURLWithPath: patch.diffPath), changedFiles: patch.changedFiles,
                                                  repoRoot: URL(fileURLWithPath: c.repoRoot), expectedBase: base)
            try await move(id, to: .applied) { $0.rollbackCommand = outcome.rollbackCommand }
            await host(id, .done, "Applied \(patch.statsLine) to \(c.repoDisplayName)'s working tree. Nothing was committed.",
                       ["undo": outcome.rollbackCommand.joined(separator: " ")])
            return outcome
        } catch let e as PatchbeamError {
            await host(id, .reviewing, e.message, ["code": e.code.rawValue])
            try? await mutate(id) { $0.lastError = PatchbeamErrorInfo(e) }
            throw e
        }
    }

    public func keep(_ id: UUID) async throws {
        try await move(id, to: .kept)
        await host(id, .done, "Kept for manual review. The worktree stays at \(cache[id]?.worktreePath ?? "?")")
    }

    /// Remove the app-owned worktree (patch, logs and evidence are retained in the capsule).
    public func discard(_ id: UUID) async throws {
        guard let c = cache[id] else { return }
        if c.status.isActive { throw PatchbeamError(.invalidTransition, "Stop the repair before discarding it.") }
        if let wt = c.worktreePath, let branch = c.branchName, let base = c.baseCommit {
            let result = try await worktrees.remove(repoRoot: URL(fileURLWithPath: c.repoRoot), info: WorktreeInfo(path: wt, branch: branch, baseCommit: base))
            await host(id, .done, result.note ?? "Removed the repair worktree\(result.deletedBranch ? " and branch \(branch)" : "")")
        }
        if c.status != .discarded {
            try await move(id, to: .discarded) { $0.worktreePath = nil }
        }
    }

    /// After an apply, optionally remove the now-redundant worktree without changing status.
    public func cleanUpWorktree(_ id: UUID) async throws {
        guard let c = cache[id], c.status == .applied, let wt = c.worktreePath, let branch = c.branchName, let base = c.baseCommit else { return }
        let result = try await worktrees.remove(repoRoot: URL(fileURLWithPath: c.repoRoot), info: WorktreeInfo(path: wt, branch: branch, baseCommit: base))
        try await mutate(id) { $0.worktreePath = nil }
        await host(id, .done, result.note ?? "Removed the repair worktree")
    }

    /// Delete a capsule's local record and files. Refuses while the worktree still exists.
    public func deleteRecord(_ id: UUID) async throws {
        guard let c = cache[id] else { return }
        if c.status.isActive || (c.worktreePath.map { FileManager.default.fileExists(atPath: $0) } ?? false) {
            throw PatchbeamError(.invalidTransition, "Discard the worktree before deleting this record.")
        }
        try await store.deleteCapsule(id)
        try? FileManager.default.removeItem(at: paths.capsuleDirectory(id))
        cache[id] = nil
        publish(.removed(id))
    }

    /// Journey E: nothing is live right after launch, so active capsules can't be proven
    /// running. Mark them interrupted, keep their worktree, and never claim success.
    @discardableResult
    public func reconcileOnLaunch() async -> [UUID] {
        var touched: [UUID] = []
        for c in cache.values where c.status.isActive && sessions[c.id] == nil && tasks[c.id] == nil {
            do {
                if c.status != .reconciling { try await move(c.id, to: .interrupted) }
                try await move(c.id, to: .reconciling)
                let preserved = c.worktreePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
                try await move(c.id, to: .needsRestart) { c in
                    c.pendingApproval?.status = .expired
                    c.warnings.append(preserved ? "Previous repair was interrupted; its worktree is preserved." : "Previous repair was interrupted before a worktree existed.")
                }
                await host(c.id, .done, "Previous repair was interrupted; marked for restart (no success assumed).")
                touched.append(c.id)
            } catch {
                continue
            }
        }
        return touched
    }

    /// "Start New Attempt from same base": a fresh capsule with the same inputs.
    public func duplicate(_ id: UUID) async throws -> Capsule {
        guard let c = cache[id] else { throw PatchbeamError(.notFound, "That repair no longer exists.") }
        return try await createCapsule(RepairDraft(diagnostic: c.sanitizedDiagnostic, title: c.title, userGoal: c.userGoal,
                                                   repoRoot: URL(fileURLWithPath: c.repoRoot), providerID: c.providerID, recipe: c.recipe))
    }
}

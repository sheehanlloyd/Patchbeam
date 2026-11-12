import AppKit
import Observation
import PatchbeamCore
import SwiftUI

enum CockpitTab: String, CaseIterable, Identifiable {
    case activity = "Activity", changes = "Changes", proof = "Proof"
    var id: String { rawValue }
}

struct UserMessage: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var detail: String?
    var isError: Bool
}

/// Form state for S4 intake.
struct IntakeState {
    var diagnostic = ""
    var sourceName: String?
    var repo: RepositorySnapshot?
    var repoError: String?
    var providerID = DemoAgentAdapter.id
    var checkCommand = ""
    var checkApproved = false
    /// The exact command text last approved for this repository, so re-filling it keeps approval.
    var approvedCommand: String?
    var goal = ""
    var runBaseline = true
    var showAdvanced = false
    var isDemo = false

    var draft: DiagnosticDraft? { try? DiagnosticIntake.fromText(diagnostic, sourceName: sourceName) }
    var parsedCheck: Result<[String], PatchbeamError> {
        let trimmed = checkCommand.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .success([]) }
        do { return .success(try CommandLineParser.parse(trimmed)) } catch let e as PatchbeamError { return .failure(e) } catch {
            return .failure(PatchbeamError(.commandUnsupportedSyntax, "Couldn't read that command."))
        }
    }
}

/// UI state on the main actor. Services run in `RepairOrchestrator`; this type only reflects
/// their published updates and forwards user intent.
@MainActor
@Observable
final class AppModel {
    var presentation: PanelPresentation = .dormant {
        didSet { if oldValue != presentation { onPresentationChange?(presentation) } }
    }
    @ObservationIgnored var onPresentationChange: ((PanelPresentation) -> Void)?
    @ObservationIgnored var onRequestKeyFocus: (() -> Void)?

    var capsules: [Capsule] = []
    var selectedID: UUID?
    var events: [UUID: [AgentEvent]] = [:]
    var verifications: [UUID: [VerificationRecord]] = [:]
    var providers: [String: ProviderAvailability] = [:]
    var descriptors: [ProviderDescriptor] = []
    var recentProjects: [Project] = []
    var intake = IntakeState()
    var tab: CockpitTab = .activity
    var message: UserMessage?
    var dropTargeted = false
    var isBusy = false
    var startupError: String?
    var hotKeyStatus: String?
    var pendingConfirmation: Confirmation?

    struct Confirmation: Identifiable {
        enum Kind { case apply(unverified: Bool), discard(hasChanges: Bool), deleteAll }
        let id = UUID()
        var kind: Kind
        var capsuleID: UUID?
    }

    @ObservationIgnored private(set) var orchestrator: RepairOrchestrator?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    let paths = AppPaths.standard()

    var selected: Capsule? {
        if let selectedID, let c = capsules.first(where: { $0.id == selectedID }) { return c }
        return capsules.first
    }

    var activeCapsule: Capsule? { capsules.first { $0.status.isActive || $0.status == .awaitingApproval } }
    var attentionCapsule: Capsule? { capsules.first { $0.status == .awaitingApproval } }

    /// The capsule the collapsed island summarizes: something live, else the newest reviewable.
    var glanceCapsule: Capsule? {
        activeCapsule ?? capsules.first { $0.status.isReviewReady || $0.status == .needsRestart || $0.status == .failed }
    }

    // MARK: Startup

    func bootstrap() async {
        do {
            let o = try await RepairOrchestrator(paths: paths, adapters: [ClaudeCodeAdapter(), DemoAgentAdapter()])
            orchestrator = o
            let stream = await o.updates()
            updatesTask = Task { [weak self] in
                for await update in stream { self?.apply(update) }
            }
            await o.reconcileOnLaunch()
            capsules = await o.allCapsules()
            descriptors = await o.providerDescriptors()
            for c in capsules.prefix(20) { await loadDetails(c.id) }
            recentProjects = (try? await o.recentProjects()) ?? []
            await refreshProviders()
        } catch let e as PatchbeamError {
            startupError = e.message + (e.recovery.map { " " + $0 } ?? "")
        } catch {
            startupError = "Patchbeam couldn't open its local database: \(error)"
        }
    }

    func refreshProviders() async {
        guard let o = orchestrator else { return }
        for d in descriptors {
            if let a = await o.probe(d.id) { providers[d.id] = a }
        }
        if providers[ClaudeCodeAdapter.id]?.isReady == true, !intake.isDemo { intake.providerID = ClaudeCodeAdapter.id }
    }

    private func apply(_ update: OrchestratorUpdate) {
        switch update {
        case .capsule(let c):
            let previous = capsules.first { $0.id == c.id }?.status
            if let i = capsules.firstIndex(where: { $0.id == c.id }) { capsules[i] = c } else { capsules.insert(c, at: 0) }
            capsules.sort { $0.updatedAt > $1.updatedAt }
            if previous != c.status { announce(c) }
            if c.status.isReviewReady && previous != c.status && selectedID == c.id {
                tab = c.status == .reviewReadyFailed ? .proof : .changes
            }
        case .event(let e):
            events[e.capsuleID, default: []].append(e)
        case .verification(let v):
            var list = verifications[v.capsuleID, default: []]
            if let i = list.firstIndex(where: { $0.id == v.id }) { list[i] = v } else { list.append(v) }
            verifications[v.capsuleID] = list
        case .removed(let id):
            capsules.removeAll { $0.id == id }
            events[id] = nil
            verifications[id] = nil
        }
    }

    /// VoiceOver feedback only while Patchbeam is foregrounded (PRD §7.3).
    private func announce(_ c: Capsule) {
        guard presentation == .expanded || presentation == .intake else { return }
        let text: String? = switch c.status {
        case .reviewReadyVerified: "Selected checks passed for \(c.repoDisplayName)"
        case .reviewReadyFailed: "Verification failed for \(c.repoDisplayName)"
        case .awaitingApproval: "Agent needs your approval"
        case .failed: "Repair failed"
        default: nil
        }
        guard let text else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func loadDetails(_ id: UUID) async {
        guard let o = orchestrator else { return }
        events[id] = (try? await o.events(id)) ?? []
        verifications[id] = (try? await o.verifications(id)) ?? []
    }

    // MARK: Presentation

    func toggleFromHotKey() {
        switch presentation {
        case .dormant, .glance:
            if capsules.isEmpty || activeCapsule == nil && selected?.status.isTerminal != false { beginIntake() } else { open(.expanded) }
        case .expanded, .intake:
            collapse()
        }
    }

    func open(_ p: PanelPresentation) {
        presentation = p
        if p == .expanded || p == .intake { onRequestKeyFocus?() }
    }

    func collapse() {
        presentation = .dormant
        dropTargeted = false
    }

    /// Escape dismisses only the frontmost transient state, never an active agent (PRD §22).
    func escape() {
        if pendingConfirmation != nil { pendingConfirmation = nil; return }
        if message != nil { message = nil; return }
        if presentation == .intake && !capsules.isEmpty { presentation = .expanded; return }
        collapse()
    }

    func select(_ id: UUID) {
        selectedID = id
        Task { await loadDetails(id) }
    }

    // MARK: Intake

    func beginIntake(prefill text: String? = nil, sourceName: String? = nil) {
        if let text {
            intake.diagnostic = text
            intake.sourceName = sourceName
        }
        if intake.repo == nil, let recent = recentProjects.first {
            Task { await chooseRepository(URL(fileURLWithPath: recent.canonicalRoot), recipe: recent.recipe) }
        }
        open(.intake)
    }

    func loadDiagnosticFile(_ url: URL) {
        do {
            let d = try DiagnosticIntake.fromFile(url)
            intake.diagnostic = d.text
            intake.sourceName = d.sourceName
            if d.truncated { show("Large log trimmed", "Patchbeam kept the beginning and end (\(d.byteCount / 1000) KB).", error: false) }
        } catch let e as PatchbeamError {
            show(e.message, e.recovery, error: true)
        } catch {
            show("Couldn't read that file.", nil, error: true)
        }
    }

    func pasteFromClipboard() {
        // Read only on explicit user action; Patchbeam never watches the clipboard.
        if let s = NSPasteboard.general.string(forType: .string) { intake.diagnostic = s; intake.sourceName = "Clipboard" }
    }

    func redactDiagnostic() {
        intake.diagnostic = SecretScanner().redact(intake.diagnostic)
    }

    func chooseRepository(_ url: URL, recipe: VerificationRecipe? = nil) async {
        guard let o = orchestrator else { return }
        do {
            let snap = try await o.inspect(url)
            intake.repo = snap
            intake.repoError = snap.head == nil ? "This repository has no commits yet, so there's no base to repair from." : nil
            var known = recipe
            if known == nil {
                known = (try? await o.recentProjects())?.first(where: { $0.canonicalRoot == snap.root.path })?.recipe
            }
            if let known {
                intake.checkCommand = known.display
                intake.checkApproved = known.isApproved
                intake.approvedCommand = known.isApproved ? known.display : nil
            } else if intake.checkCommand.isEmpty {
                intake.checkCommand = CommandLineParser.suggestions(forRepositoryAt: snap.root).first ?? ""
                intake.checkApproved = false
            }
        } catch let e as PatchbeamError {
            intake.repo = nil
            intake.repoError = e.message
        } catch {
            intake.repoError = "Choose a folder containing a Git repository."
        }
    }

    func pickRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Repository"
        panel.message = "Choose the Git repository to repair. Patchbeam only reads it and creates a separate worktree."
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            Task { await chooseRepository(url) }
        }
        onRequestKeyFocus?()
    }

    func pickLogFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .log, .text]
        panel.prompt = "Inspect Log"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { loadDiagnosticFile(url) }
        onRequestKeyFocus?()
    }

    var canStart: Bool {
        guard let repo = intake.repo, repo.head != nil, intake.draft != nil, !isBusy else { return false }
        guard providers[intake.providerID]?.isReady == true else { return false }
        switch intake.parsedCheck {
        case .failure: return false
        case .success(let argv): return argv.isEmpty || intake.checkApproved
        }
    }

    func startRepair() async {
        guard canStart, let o = orchestrator, let repo = intake.repo else { return }
        isBusy = true
        defer { isBusy = false }
        var recipe: VerificationRecipe?
        if case .success(let argv) = intake.parsedCheck, !argv.isEmpty {
            recipe = VerificationRecipe(argv: argv, display: CommandLineParser.display(argv))
            if intake.checkApproved { recipe = recipe?.approving() }
        }
        do {
            let draft = RepairDraft(diagnostic: intake.diagnostic, userGoal: intake.goal.isEmpty ? nil : intake.goal, repoRoot: repo.root,
                                    providerID: intake.providerID, recipe: recipe, runBaseline: intake.runBaseline,
                                    budgetUSD: UserDefaults.standard.object(forKey: "budgetUSD") as? Double ?? 1.0)
            let c = try await o.createCapsule(draft)
            selectedID = c.id
            events[c.id] = (try? await o.events(c.id)) ?? []
            try await o.start(c.id)
            tab = .activity
            presentation = .expanded
            recentProjects = (try? await o.recentProjects()) ?? recentProjects
            intake = IntakeState(providerID: intake.providerID)
        } catch let e as PatchbeamError {
            show(e.message, e.recovery, error: true)
        } catch {
            show("Couldn't start the repair.", String(describing: error), error: true)
        }
    }

    /// Journey D: a real, local, model-free demo on a freshly generated fixture repository.
    func prepareDemo() async {
        guard let o = orchestrator else { return }
        do {
            let parent = paths.root.appendingPathComponent("DemoRepos", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let name = "broken-python-\(Int(Date().timeIntervalSince1970))"
            let repo = try await FixtureLibrary.makeBrokenPythonRepo(in: parent, repoName: name, git: o.git)
            intake = IntakeState()
            intake.isDemo = true
            intake.diagnostic = FixtureLibrary.sampleTraceback
            intake.sourceName = "broken-python fixture"
            intake.providerID = DemoAgentAdapter.id
            await chooseRepository(repo)
            intake.checkCommand = FixtureLibrary.checkCommand.joined(separator: " ")
            intake.checkApproved = false
            open(.intake)
        } catch let e as PatchbeamError {
            show(e.message, e.recovery, error: true)
        } catch {
            show("Couldn't create the demo repository.", String(describing: error), error: true)
        }
    }

    // MARK: Capsule actions

    func perform(_ action: @escaping (RepairOrchestrator) async throws -> Void) {
        guard let o = orchestrator else { return }
        Task {
            do { try await action(o) } catch let e as PatchbeamError {
                show(e.message, e.recovery ?? e.detail, error: true)
            } catch {
                show("That action failed.", String(describing: error), error: true)
            }
        }
    }

    func stop(_ c: Capsule) { perform { try await $0.stop(c.id) } }
    func retry(_ c: Capsule) { perform { try await $0.retry(c.id) }; tab = .activity }
    func rerun(_ c: Capsule) { perform { try await $0.rerunVerification(c.id) } }
    func keep(_ c: Capsule) { perform { try await $0.keep(c.id) } }
    func respond(_ c: Capsule, _ d: ApprovalDecision) { perform { try await $0.respond(c.id, decision: d) } }
    func startNewAttempt(_ c: Capsule) {
        perform { o in
            let n = try await o.duplicate(c.id)
            await MainActor.run { self.selectedID = n.id }
            try await o.start(n.id)
        }
    }

    func requestApply(_ c: Capsule) {
        pendingConfirmation = Confirmation(kind: .apply(unverified: c.status != .reviewReadyVerified), capsuleID: c.id)
    }

    func requestDiscard(_ c: Capsule) {
        pendingConfirmation = Confirmation(kind: .discard(hasChanges: !(c.patch?.isEmpty ?? true)), capsuleID: c.id)
    }

    func confirm() {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        switch pending.kind {
        case .apply:
            guard let id = pending.capsuleID else { return }
            perform { o in
                let outcome = try await o.apply(id)
                await MainActor.run {
                    self.show("Applied to your working tree", "\(outcome.appliedFiles.count) file(s) changed. Nothing was committed. Undo: \(outcome.rollbackCommand.joined(separator: " "))", error: false)
                }
            }
        case .discard:
            guard let id = pending.capsuleID else { return }
            perform { try await $0.discard(id) }
        case .deleteAll:
            Task { await deleteAllHistory() }
        }
    }

    func deleteAllHistory() async {
        guard let o = orchestrator else { return }
        for c in capsules {
            if c.status.isActive { continue }
            if c.worktreePath != nil { try? await o.discard(c.id) }
            try? await o.deleteRecord(c.id)
        }
        show("Local history deleted", "Active repairs were left running.", error: false)
    }

    func openInEditor(_ c: Capsule) {
        guard let wt = c.worktreePath, FileManager.default.fileExists(atPath: wt) else {
            show("The repair worktree no longer exists.", nil, error: true); return
        }
        EditorLauncher.open(URL(fileURLWithPath: wt), files: c.patch?.changedFiles.map(\.path) ?? [])
    }

    func revealInFinder(_ c: Capsule) {
        if let wt = c.worktreePath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wt)]) }
    }

    func copySummary(_ c: Capsule) {
        let proof = verifications[c.id]?.last { $0.kind == .patch }
        let baseline = verifications[c.id]?.first { $0.kind == .baseline }
        var lines = [
            "## Patchbeam repair — \(c.title)",
            "- Repository: \(c.repoDisplayName) @ \(c.baseCommit.map { String($0.prefix(10)) } ?? "?") (\(c.baseBranch ?? "detached"))",
            "- Provider: \(c.providerDisplayName)\(c.isScriptedProvider ? " — scripted demo, no model used" : "")",
            "- Status: \(c.status.label)",
        ]
        if let p = c.patch { lines.append("- Patch: \(p.statsLine) — \(p.changedFiles.map(\.path).joined(separator: ", "))") }
        if let baseline { lines.append("- Before: `\(baseline.argv.joined(separator: " "))` → \(baseline.headline)") }
        if let proof { lines.append("- After: `\(proof.argv.joined(separator: " "))` → \(proof.headline)\(proof.parsed.map { " (\($0.line))" } ?? "")") }
        for w in c.warnings { lines.append("- ⚠︎ \(w)") }
        lines.append("\n_Passing selected checks does not prove the fix is complete._")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        show("Summary copied", nil, error: false)
    }

    func show(_ title: String, _ detail: String?, error: Bool) {
        message = UserMessage(title: title, detail: detail, isError: error)
        if !error {
            let id = message?.id
            Task { try? await Task.sleep(for: .seconds(4)); if self.message?.id == id { self.message = nil } }
        }
    }

    // MARK: Drag & drop

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let item = providers.first else { return false }
        if item.hasItemConformingToTypeIdentifier("public.file-url") {
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    self.loadDiagnosticFile(url)
                    self.beginIntake()
                }
            }
            return true
        }
        if item.canLoadObject(ofClass: String.self) {
            _ = item.loadObject(ofClass: String.self) { text, _ in
                guard let text else { return }
                Task { @MainActor in self.beginIntake(prefill: text, sourceName: "Dropped text") }
            }
            return true
        }
        return false
    }
}

/// Opens a worktree in the user's editor. Detection is by bundle identifier; nothing is installed.
enum EditorLauncher {
    static let known: [(name: String, bundleID: String)] = [
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Zed", "dev.zed.Zed"),
        ("Xcode", "com.apple.dt.Xcode"),
    ]

    static func installed() -> [(name: String, url: URL)] {
        known.compactMap { e in NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundleID).map { (e.name, $0) } }
    }

    @MainActor
    static func open(_ folder: URL, files: [String]) {
        let preferred = UserDefaults.standard.string(forKey: "editorBundleID")
        let app = preferred.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } ?? installed().first?.url
        guard let app else {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            return
        }
        let urls = [folder] + files.prefix(5).map { folder.appendingPathComponent($0) }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: config)
    }
}

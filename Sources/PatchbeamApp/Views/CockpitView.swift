import AppKit
import PatchbeamCore
import SwiftUI

/// S2/S3 expanded cockpit: header → focus card → tabs → actions (focus order per PRD §22).
struct CockpitView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            CockpitHeader(model: model)
            if let c = model.selected {
                FocusCard(model: model, capsule: c)
                if let approval = c.pendingApproval, c.status == .awaitingApproval {
                    ApprovalCard(model: model, capsule: c, approval: approval)
                }
                Picker("View", selection: $model.tab) {
                    ForEach(CockpitTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Capsule view")
                ZStack {
                    switch model.tab {
                    case .activity: ActivityList(events: model.events[c.id] ?? [], capsule: c)
                    case .changes: ChangesView(model: model, capsule: c)
                    case .proof: ProofView(model: model, capsule: c)
                    }
                }
                .frame(maxHeight: .infinity)
                ActionBar(model: model, capsule: c)
            } else {
                EmptyCockpit(model: model)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { MessageBanner(model: model).padding(.bottom, 56) }
        .overlay { ConfirmationOverlay(model: model) }
        .background(shortcuts)
    }

    /// Keyboard path: ⌘1/2/3 tabs, ⌘N new repair, ⌘W/Escape collapse.
    private var shortcuts: some View {
        ZStack {
            Button("") { model.tab = .activity }.keyboardShortcut("1", modifiers: .command)
            Button("") { model.tab = .changes }.keyboardShortcut("2", modifiers: .command)
            Button("") { model.tab = .proof }.keyboardShortcut("3", modifiers: .command)
            Button("") { model.beginIntake() }.keyboardShortcut("n", modifiers: .command)
            Button("") { model.collapse() }.keyboardShortcut("w", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

struct CockpitHeader: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            PatchbeamGlyph(size: 15)
            Text("PATCHBEAM").font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).fixedSize()
            if let c = model.selected {
                Menu {
                    ForEach(model.capsules.prefix(15)) { cap in
                        Button("\(cap.repoDisplayName) — \(cap.title) (\(cap.status.label))") { model.select(cap.id) }
                    }
                } label: {
                    Chip(text: c.repoDisplayName, symbol: "folder", tint: Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Switch capsule (\(model.capsules.count) total)")
                .accessibilityLabel("Repository \(c.repoDisplayName). \(model.capsules.count) capsules. Switch capsule")
            }
            Spacer()
            Button { model.beginIntake() } label: { Image(systemName: "plus") }
                .buttonStyle(PanelButtonStyle(kind: .quiet)).help("New repair (⌘N)").accessibilityLabel("New repair")
            Button { AppDelegate.shared?.showSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(PanelButtonStyle(kind: .quiet)).help("Settings").accessibilityLabel("Settings")
            Button { model.collapse() } label: { Image(systemName: "xmark") }
                .buttonStyle(PanelButtonStyle(kind: .quiet)).help("Close (Esc)").accessibilityLabel("Close Patchbeam")
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

struct FocusCard: View {
    var model: AppModel
    var capsule: Capsule
    @State private var showIsolation = false

    var body: some View {
        let style = StatusStyle(capsule.status)
        let lastEvent = model.events[capsule.id]?.last
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: style.symbol).foregroundStyle(style.color).font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.label).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(style.color)
                    Text(capsule.title).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                Button { showIsolation.toggle() } label: {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("What the worktree does and doesn't isolate")
                .accessibilityLabel("Worktree isolation explanation")
                .popover(isPresented: $showIsolation, arrowEdge: .bottom) { IsolationExplainer().preferredColorScheme(.dark) }
            }
            if style.isLive || capsule.status == .awaitingApproval {
                BeamRail(phase: lastEvent?.phase, live: style.isLive, color: style.color)
                if let lastEvent { Text(lastEvent.summary).font(.system(size: 11.5)).foregroundStyle(Theme.text).lineLimit(1) }
            }
            HStack(spacing: 6) {
                Group {
                    if capsule.isScriptedProvider { DemoBadge() } else { Chip(text: capsule.providerDisplayName, symbol: "cpu") }
                }
                .fixedSize()
                .layoutPriority(2)
                if let p = capsule.patch, !p.isEmpty {
                    Chip(text: p.statsLine, symbol: "plusminus", mono: true).fixedSize().layoutPriority(1)
                }
                if let b = capsule.branchName {
                    Chip(text: b, symbol: "arrow.triangle.branch", mono: true).help(b)
                }
                Spacer(minLength: 0)
            }
            ForEach(capsule.warnings.prefix(2), id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Theme.warning).lineLimit(2)
            }
            if let err = capsule.lastError, capsule.status == .failed {
                Label(err.message, systemImage: "xmark.octagon").font(.system(size: 11.5)).foregroundStyle(Theme.failed).textSelection(.enabled)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).strokeBorder(Theme.separator.opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.isLive ? "Running repair for" : "Repair for") \(capsule.repoDisplayName): \(style.label). \(capsule.title)")
    }
}

struct IsolationExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What the worktree does").font(.headline)
            Text("• The agent edits a separate Git checkout under Patchbeam's folder, on its own patchbeam/… branch.\n• Your current files, uncommitted edits and branch aren't touched until you click Apply.\n• Apply writes to your working tree only. Nothing is committed or pushed.")
            Text("What it does not do").font(.headline).padding(.top, 4)
            Text("• A worktree is **not** a sandbox. The agent's own runtime may still read other files or use the network under its provider's policy.\n• Git-tracked secrets exist in the worktree too.\n• Check commands run real code from your repository.")
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 330)
    }
}

/// Journey B: the exact command, cwd, reason, scope, requester and risk. Allow Once / Deny only.
struct ApprovalCard: View {
    var model: AppModel
    var capsule: Capsule
    var approval: ApprovalRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(approval.requester) is asking to run a command", systemImage: "hand.raised").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warning)
            if let cmd = approval.command {
                Text("$ \(cmd)").font(Theme.mono(11.5)).foregroundStyle(Theme.text).textSelection(.enabled)
            }
            Group {
                if let cwd = approval.cwd { Text("in \(cwd)").lineLimit(1).truncationMode(.middle) }
                Text("Reason: \(approval.reason)")
                Text("Scope: \(approval.scope) · Risk: \(approval.risk.rawValue)")
                if let exp = approval.expiresAt { Text("Expires \(exp, style: .relative)") }
            }
            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack {
                Spacer()
                if model.providers[capsule.providerID]?.capabilities.approve == true {
                    Button("Deny") { model.respond(capsule, .deny) }.buttonStyle(PanelButtonStyle(kind: .destructive))
                        .accessibilityLabel("Deny request")
                    Button("Allow Once") { model.respond(capsule, .allowOnce) }.buttonStyle(PanelButtonStyle(kind: .primary))
                        .accessibilityLabel("Allow request once")
                } else {
                    Text("Approve this action in \(capsule.providerDisplayName)'s terminal.").font(.system(size: 11)).foregroundStyle(Theme.warning)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(Theme.warning.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).strokeBorder(Theme.warning.opacity(0.35), lineWidth: 0.5))
    }
}

struct ActionBar: View {
    var model: AppModel
    var capsule: Capsule

    var body: some View {
        HStack(spacing: 8) {
            overflow
            Spacer()
            switch capsule.status {
            case _ where capsule.status.isActive || capsule.status == .awaitingApproval:
                Button { model.stop(capsule) } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(PanelButtonStyle(kind: .destructive)).keyboardShortcut(".", modifiers: .command)
                    .disabled(capsule.status == .cancelling).accessibilityLabel("Stop agent")
            case .reviewReadyVerified, .reviewReadyUnverified:
                Button("Open in Editor") { model.openInEditor(capsule) }.buttonStyle(PanelButtonStyle())
                Button(capsule.status == .reviewReadyVerified ? "Apply to My Branch…" : "Apply Unverified…") { model.requestApply(capsule) }
                    .buttonStyle(PanelButtonStyle(kind: .primary)).keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Apply patch")
            case .reviewReadyFailed:
                Button("Open in Editor") { model.openInEditor(capsule) }.buttonStyle(PanelButtonStyle())
                if capsule.canRetry {
                    Button("Retry with Failure Evidence") { model.retry(capsule) }.buttonStyle(PanelButtonStyle(kind: .primary))
                        .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Keep for Review") { model.keep(capsule) }.buttonStyle(PanelButtonStyle(kind: .primary))
                }
            case .needsRestart, .cancelled, .failed:
                if capsule.worktreePath != nil { Button("Open Worktree") { model.openInEditor(capsule) }.buttonStyle(PanelButtonStyle()) }
                Button("Start New Attempt") { model.startNewAttempt(capsule) }.buttonStyle(PanelButtonStyle(kind: .primary))
            case .applied:
                if capsule.worktreePath != nil {
                    Button("Remove Worktree") { model.perform { try await $0.cleanUpWorktree(capsule.id) } }.buttonStyle(PanelButtonStyle())
                }
                Button("New Repair") { model.beginIntake() }.buttonStyle(PanelButtonStyle(kind: .primary))
            default:
                Button("New Repair") { model.beginIntake() }.buttonStyle(PanelButtonStyle(kind: .primary))
            }
        }
    }

    private var overflow: some View {
        Menu {
            Button("Copy Summary") { model.copySummary(capsule) }
            if capsule.worktreePath != nil { Button("Reveal Worktree in Finder") { model.revealInFinder(capsule) } }
            if [.reviewReadyVerified, .reviewReadyFailed, .reviewReadyUnverified, .kept].contains(capsule.status) {
                Button("Run Verification Again") { model.rerun(capsule) }
                Button("Keep Capsule") { model.keep(capsule) }.disabled(capsule.status == .kept)
            }
            if !capsule.status.isActive && capsule.status != .discarded && capsule.status != .awaitingApproval {
                Divider()
                Button("Discard Worktree…", role: .destructive) { model.requestDiscard(capsule) }
            }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More actions")
    }
}

struct EmptyCockpit: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            PatchbeamGlyph(size: 34)
            Text("What broke?").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            Text("Paste a failing test or drop a .log here. Patchbeam fixes it in a separate worktree and shows you real test evidence before anything touches your branch.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            HStack {
                Button("Try the Demo") { Task { await model.prepareDemo() } }.buttonStyle(PanelButtonStyle())
                Button("New Repair") { model.beginIntake() }.buttonStyle(PanelButtonStyle(kind: .primary))
            }
            if let err = model.startupError { Text(err).font(.system(size: 11)).foregroundStyle(Theme.failed) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct MessageBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        if let m = model.message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: m.isError ? "exclamationmark.octagon" : "checkmark.circle").foregroundStyle(m.isError ? Theme.failed : Theme.ready)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                    if let d = m.detail { Text(d).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).textSelection(.enabled).lineLimit(4) }
                }
                Spacer(minLength: 4)
                Button { model.message = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSubdued).accessibilityLabel("Dismiss message")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder((m.isError ? Theme.failed : Theme.ready).opacity(0.35), lineWidth: 0.5))
            .padding(.horizontal, 14)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }
}

/// In-panel confirmation (no modal alerts that would steal focus from other apps).
struct ConfirmationOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        if let pending = model.pendingConfirmation {
            ZStack {
                Color.black.opacity(0.6).onTapGesture { model.pendingConfirmation = nil }
                VStack(alignment: .leading, spacing: 10) {
                    content(pending)
                    HStack {
                        Spacer()
                        Button("Cancel") { model.pendingConfirmation = nil }.buttonStyle(PanelButtonStyle()).keyboardShortcut(.cancelAction)
                        Button(confirmTitle(pending)) { model.confirm() }
                            .buttonStyle(PanelButtonStyle(kind: isDestructive(pending) ? .destructive : .primary))
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
                .frame(maxWidth: 400)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
            }
        }
    }

    @ViewBuilder
    private func content(_ p: AppModel.Confirmation) -> some View {
        let c = p.capsuleID.flatMap { id in model.capsules.first { $0.id == id } }
        switch p.kind {
        case .apply(let unverified):
            Text(unverified ? "Apply an unverified patch?" : "Apply this patch to your branch?").font(.system(size: 14, weight: .semibold))
            Text("Patchbeam will check that \(c?.repoDisplayName ?? "the repository") is still at \(c?.baseCommit.map { String($0.prefix(8)) } ?? "the base commit") and that the touched files have no uncommitted edits, then write \(c?.patch?.statsLine ?? "the patch") to your **working tree**. Nothing is staged, committed or pushed. If anything changed, it stops without overwriting.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            if unverified { Label("The selected checks did not prove this revision.", systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(Theme.warning) }
        case .discard(let hasChanges):
            Text("Discard the repair worktree?").font(.system(size: 14, weight: .semibold))
            Text(hasChanges
                 ? "The worktree contains uncommitted changes (\(c?.patch?.statsLine ?? "")). Patchbeam keeps the patch file, logs and evidence, but removes the worktree folder and its patchbeam/… branch. Your own branch isn't touched."
                 : "Patchbeam removes the worktree folder and its patchbeam/… branch. Your own branch isn't touched.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        case .deleteAll:
            Text("Delete all local history?").font(.system(size: 14, weight: .semibold))
            Text("Removes every finished capsule's record, logs, patches and remaining worktrees from Patchbeam's folder. Running repairs are left alone. This can't be undone.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func confirmTitle(_ p: AppModel.Confirmation) -> String {
        switch p.kind {
        case .apply: "Apply to Working Tree"
        case .discard: "Discard Worktree"
        case .deleteAll: "Delete All"
        }
    }

    private func isDestructive(_ p: AppModel.Confirmation) -> Bool {
        if case .apply = p.kind { return false }
        return true
    }
}

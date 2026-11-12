import PatchbeamCore
import SwiftUI

struct IntakeView: View {
    @Bindable var model: AppModel
    @FocusState private var diagnosticFocused: Bool

    private var draft: DiagnosticDraft? { model.intake.draft }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PatchbeamGlyph(size: 15)
                Text("What broke?").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                if model.intake.isDemo || model.intake.providerID == DemoAgentAdapter.id { DemoBadge() }
                Spacer()
                if !model.capsules.isEmpty {
                    Button { model.presentation = .expanded } label: { Image(systemName: "rectangle.stack") }
                        .buttonStyle(PanelButtonStyle(kind: .quiet)).help("Back to repairs").accessibilityLabel("Back to repairs")
                }
                Button { model.collapse() } label: { Image(systemName: "xmark") }
                    .buttonStyle(PanelButtonStyle(kind: .quiet)).accessibilityLabel("Close")
            }
            diagnosticEditor
            repositoryRow
            providerRow
            checkRow
            DisclosureGroup(isExpanded: $model.intake.showAdvanced) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Optional note for the agent (e.g. “don't change the public API”)", text: $model.intake.goal)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11.5))
                    Toggle("Run the check on the untouched base first (red-before proof)", isOn: $model.intake.runBaseline)
                        .font(.system(size: 11.5)).toggleStyle(.checkbox)
                }
                .padding(.top, 4)
            } label: {
                Text("Advanced").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            disclosure
            HStack {
                if model.capsules.isEmpty && !model.intake.isDemo {
                    Button("Try the Demo") { Task { await model.prepareDemo() } }.buttonStyle(PanelButtonStyle(kind: .quiet))
                }
                Spacer()
                Button {
                    Task { await model.startRepair() }
                } label: {
                    Label(model.isBusy ? "Starting…" : "Start Repair", systemImage: "play.fill")
                }
                .buttonStyle(PanelButtonStyle(kind: .primary))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canStart)
                .opacity(model.canStart ? 1 : 0.45)
                .accessibilityLabel("Start repair in a separate worktree")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { MessageBanner(model: model).padding(.bottom, 50) }
        .onAppear { diagnosticFocused = model.intake.diagnostic.isEmpty }
    }

    private var diagnosticEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.intake.diagnostic)
                    .font(Theme.mono(11))
                    .scrollContentBackground(.hidden)
                    .focused($diagnosticFocused)
                    .padding(6)
                    .accessibilityLabel("Diagnostic text")
                if model.intake.diagnostic.isEmpty {
                    Text("Paste a stack trace or failing test output, or drop a .log file…")
                        .font(Theme.mono(11)).foregroundStyle(Theme.textSubdued).padding(.horizontal, 11).padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 118)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(diagnosticFocused ? Theme.accent.opacity(0.6) : Theme.separator, lineWidth: 0.75))
            HStack(spacing: 8) {
                Button("Paste") { model.pasteFromClipboard() }.buttonStyle(PanelButtonStyle(kind: .quiet)).keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Choose Log…") { model.pickLogFile() }.buttonStyle(PanelButtonStyle(kind: .quiet))
                Spacer()
                if let d = draft {
                    Text("\(d.lineCount) lines · \(ByteCountFormatter.string(fromByteCount: Int64(d.byteCount), countStyle: .file))\(d.truncated ? " · trimmed" : "")")
                        .font(Theme.mono(10.5)).foregroundStyle(Theme.textSubdued)
                    if !d.findings.isEmpty {
                        Button {
                            model.redactDiagnostic()
                        } label: {
                            Label("\(d.findings.count) possible secret\(d.findings.count == 1 ? "" : "s") — Redact", systemImage: "eye.slash")
                        }
                        .buttonStyle(PanelButtonStyle(kind: .destructive))
                        .help("Local pattern match: \(Set(d.findings).sorted().joined(separator: ", ")). The scanner can miss things.")
                    }
                }
            }
            .font(.system(size: 11))
        }
    }

    private var repositoryRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Repository").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                Button {
                    model.pickRepository()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(model.intake.repo?.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "Choose repository…")
                            .lineLimit(1).truncationMode(.head)
                    }
                    .font(.system(size: 11.5))
                }
                .buttonStyle(PanelButtonStyle())
                .help(model.intake.repo?.root.path ?? "Patchbeam only uses folders you choose")
                .accessibilityLabel("Repository: \(model.intake.repo?.displayName ?? "none chosen"). Choose repository")
                if !model.recentProjects.isEmpty {
                    Menu {
                        ForEach(model.recentProjects) { p in
                            Button(p.displayName) { Task { await model.chooseRepository(URL(fileURLWithPath: p.canonicalRoot), recipe: p.recipe) } }
                        }
                    } label: { Image(systemName: "clock") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Recent repositories")
                }
                Spacer(minLength: 0)
                if let repo = model.intake.repo, repo.head != nil {
                    Chip(text: "\(repo.branch ?? "detached") @ \(repo.shortHead)", symbol: "arrow.triangle.branch", mono: true)
                }
            }
            if let err = model.intake.repoError {
                Label(err, systemImage: "xmark.octagon").font(.system(size: 11)).foregroundStyle(Theme.failed).padding(.leading, 80)
            } else if let repo = model.intake.repo, repo.isDirty {
                Label("Your uncommitted edits (\(repo.dirtyPaths.count) file\(repo.dirtyPaths.count == 1 ? "" : "s")) are not in this repair worktree. It starts from \(repo.shortHead).",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Theme.warning).padding(.leading, 80)
            }
        }
    }

    private var providerRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Agent").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                Picker("Agent", selection: $model.intake.providerID) {
                    ForEach(model.descriptors, id: \.id) { d in
                        Text(d.isScripted ? "DemoAgent (no model)" : d.displayName).tag(d.id)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
                Spacer()
                Button { Task { await model.refreshProviders() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(PanelButtonStyle(kind: .quiet)).help("Re-check provider").accessibilityLabel("Re-check provider")
            }
            if let p = model.providers[model.intake.providerID] {
                HStack(spacing: 5) {
                    Image(systemName: p.isReady ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(p.isReady ? Theme.ready : Theme.warning)
                    Text(p.message + (p.setupHint.map { " " + $0 } ?? "")).foregroundStyle(p.isReady ? Theme.textSecondary : Theme.warning).textSelection(.enabled)
                }
                .font(.system(size: 11)).padding(.leading, 80)
            }
        }
    }

    private var checkRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Check").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                TextField("e.g. python3 -m unittest -v", text: $model.intake.checkCommand)
                    .textFieldStyle(.roundedBorder).font(Theme.mono(11.5))
                    .onChange(of: model.intake.checkCommand) { _, new in
                        if new != model.intake.approvedCommand { model.intake.checkApproved = false }
                    }
                    .accessibilityLabel("Verification command")
            }
            switch model.intake.parsedCheck {
            case .failure(let e):
                Label(e.message, systemImage: "xmark.octagon").font(.system(size: 11)).foregroundStyle(Theme.failed).padding(.leading, 80)
            case .success(let argv) where argv.isEmpty:
                Label("Not verified — no check configured. You can still review the patch.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Theme.warning).padding(.leading, 80)
            case .success(let argv):
                Toggle(isOn: $model.intake.checkApproved) {
                    Text("Approve running \(Text(argv.joined(separator: " ")).font(Theme.mono(11))) in the worktree (no shell; it runs your repo's code)")
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox).padding(.leading, 80)
                .accessibilityLabel("Approve verification command")
            }
        }
    }

    private var disclosure: some View {
        let provider = model.descriptors.first { $0.id == model.intake.providerID }
        let text = provider?.isScripted == true
            ? "Fix in a separate worktree with the scripted DemoAgent: no model is contacted and nothing leaves this Mac."
            : "Fix in a separate worktree. \(provider?.displayName ?? "The agent") receives the text above and can read and edit files in that worktree under its own account and policy. A worktree isn't a sandbox. Nothing touches your branch until you click Apply."
        return Label(text, systemImage: "shield.lefthalf.filled")
            .font(.system(size: 10.5)).foregroundStyle(Theme.textSubdued)
            .fixedSize(horizontal: false, vertical: true)
    }
}

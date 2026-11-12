import AppKit
import PatchbeamCore
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    var resetLayout: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            DisplaySettings(resetLayout: resetLayout).tabItem { Label("Display", systemImage: "display") }
            AgentSettings(model: model).tabItem { Label("Agents", systemImage: "cpu") }
            ProjectSettings(model: model).tabItem { Label("Projects", systemImage: "folder") }
            PrivacySettings(model: model).tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 400)
        .padding()
    }
}

private struct GeneralSettings: View {
    var model: AppModel
    @AppStorage("hoverToGlance") private var hoverToGlance = true
    @AppStorage("reduceMotionOverride") private var reduceMotion = false
    @AppStorage("editorBundleID") private var editor = ""

    var body: some View {
        Form {
            LabeledContent("Global shortcut") {
                VStack(alignment: .leading) {
                    Text("⌃⌥Space").font(.system(.body, design: .monospaced))
                    if let err = model.hotKeyStatus { Text(err).font(.caption).foregroundStyle(.orange) }
                }
            }
            Toggle("Hover over the notch to glance (≈200 ms dwell)", isOn: $hoverToGlance)
            Toggle("Reduce motion in Patchbeam (in addition to the system setting)", isOn: $reduceMotion)
            Picker("Open in editor", selection: $editor) {
                Text("First installed (Cursor, VS Code, Zed, Xcode) or Finder").tag("")
                ForEach(EditorLauncher.installed(), id: \.name) { e in
                    Text(e.name).tag(EditorLauncher.known.first { $0.name == e.name }?.bundleID ?? "")
                }
            }
            LabeledContent("Start at login") { Text("Off. Patchbeam doesn't install a login item.").foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaySettings: View {
    var resetLayout: () -> Void
    @AppStorage("preferredScreenID") private var preferredScreenID = ""

    var body: some View {
        Form {
            Picker("Show Patchbeam on", selection: $preferredScreenID) {
                Text("Automatic (built-in notched display)").tag("")
                ForEach(NSScreen.screens, id: \.displayID) { s in
                    Text("\(s.localizedName)\(s.descriptor.hasNotch ? " — notch" : " — floating capsule")").tag(String(s.displayID))
                }
            }
            Text("On displays without a camera notch, Patchbeam shows a small floating capsule below the menu bar. It never draws a fake notch.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Full-screen apps: the panel joins all Spaces and can appear beside full-screen windows. Use “Hide Notch Panel” in the menu bar item during screen sharing or presentations.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Reset Panel Layout") { preferredScreenID = ""; resetLayout() }
        }
        .formStyle(.grouped)
    }
}

private struct AgentSettings: View {
    var model: AppModel
    @AppStorage("budgetUSD") private var budget = 1.0

    var body: some View {
        Form {
            ForEach(model.descriptors, id: \.id) { d in
                Section(d.displayName) {
                    if let p = model.providers[d.id] {
                        LabeledContent("Status", value: p.message)
                        if let hint = p.setupHint { LabeledContent("Setup", value: hint) }
                        LabeledContent("Version", value: p.version ?? "—")
                        if let path = p.executablePath { LabeledContent("Executable", value: path).textSelection(.enabled) }
                        LabeledContent("Capabilities", value: "Run \(p.capabilities.run ? "✓" : "✗") · Stream \(p.capabilities.stream ? "✓" : "✗") · Approve \(p.capabilities.approve ? "✓" : "✗ (in provider terminal)") · Resume \(p.capabilities.resume ? "✓" : "✗")")
                    }
                }
            }
            Section("Budget") {
                Stepper(value: $budget, in: 0.25...20, step: 0.25) {
                    Text("Per-run provider spend cap: $\(String(format: "%.2f", budget)) (passed as --max-budget-usd)")
                }
                Text("You pay your provider directly. Patchbeam has no subscription and sends no telemetry.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Re-check Providers") { Task { await model.refreshProviders() } }
        }
        .formStyle(.grouped)
    }
}

private struct ProjectSettings: View {
    var model: AppModel

    var body: some View {
        Form {
            if model.recentProjects.isEmpty {
                Text("No repositories yet. Patchbeam only uses folders you choose and never scans your disk.").foregroundStyle(.secondary)
            }
            ForEach(model.recentProjects) { p in
                LabeledContent(p.displayName) {
                    VStack(alignment: .trailing) {
                        Text(p.canonicalRoot).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(p.recipe.map { "\($0.display) — \($0.isApproved ? "approved" : "not approved")" } ?? "No check configured")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    var model: AppModel

    var body: some View {
        Form {
            Section("Where your data lives") {
                LabeledContent("Local folder") {
                    Button(model.paths.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.paths.root])
                    }.buttonStyle(.link)
                }
                Text("Capsules, logs, patches and app-owned worktrees are stored only on this Mac. Telemetry: off. Patchbeam has none.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permission ledger") {
                LabeledContent("Accessibility", value: "Not requested")
                LabeledContent("Screen Recording", value: "Not requested")
                LabeledContent("Full Disk Access", value: "Not requested")
                LabeledContent("Clipboard", value: "Read only when you click Paste")
                LabeledContent("Repositories", value: "Only folders you choose")
            }
            Section {
                Button("Delete All Local History…", role: .destructive) {
                    model.pendingConfirmation = AppModel.Confirmation(kind: .deleteAll, capsuleID: nil)
                    model.open(.expanded)
                }
                Text("Secret detection before sending is a local pattern match and can miss things. Review the diagnostic preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            PatchbeamGlyph(size: 44)
            Text("Patchbeam").font(.title2.weight(.semibold))
            Text("From broken to verified, without breaking your flow.").foregroundStyle(.secondary)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · unsigned development preview")
                .font(.caption).foregroundStyle(.secondary)
            Link("Source on GitHub", destination: URL(string: "https://github.com/sheehanlloyd/Patchbeam")!)
            Link("Check GitHub Releases", destination: URL(string: "https://github.com/sheehanlloyd/Patchbeam/releases")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

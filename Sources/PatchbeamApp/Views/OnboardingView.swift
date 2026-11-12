import AppKit
import PatchbeamCore
import SwiftUI

/// First run: Welcome → layout preview → providers (no secrets read) → how proof works → try demo.
/// No account, telemetry, or macOS privacy permission is requested at any step.
struct OnboardingView: View {
    var model: AppModel
    var finish: () -> Void
    @State private var step = 0
    private let steps = ["Welcome", "Your notch", "Agents", "Proof", "Try it"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    SwiftUI.Capsule().fill(i <= step ? Theme.accent : Theme.separator).frame(height: 3)
                }
            }
            .padding(.horizontal, 28).padding(.top, 34)
            Group {
                switch step {
                case 0: welcome
                case 1: layout
                case 2: agents
                case 3: proof
                default: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            HStack {
                Button("Skip") { finish() }.buttonStyle(PanelButtonStyle(kind: .quiet))
                Spacer()
                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(PanelButtonStyle()) }
                if step < steps.count - 1 {
                    Button("Continue") { step += 1 }.buttonStyle(PanelButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { finish() }.buttonStyle(PanelButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 430)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            PatchbeamGlyph(size: 54)
            Text("Patchbeam").font(.system(size: 26, weight: .semibold))
            Text("From broken to verified, without breaking your flow.").foregroundStyle(Theme.textSecondary)
            Text("Paste a failing test. Patchbeam runs a coding agent in a **separate Git worktree**, runs **your** check command itself, and shows the real exit code and diff. Nothing touches your branch until you click Apply.")
                .multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var layout: some View {
        let screen = NSScreen.screens.first { $0.descriptor.hasNotch } ?? NSScreen.main
        let hasNotch = screen?.descriptor.hasNotch ?? false
        return VStack(alignment: .leading, spacing: 12) {
            Text("Lives in your notch").font(.title2.weight(.semibold))
            Text(hasNotch
                 ? "Detected a camera notch on “\(screen?.localizedName ?? "this display")”. Patchbeam sits around it. It never draws over the camera or the menu-bar items beside it."
                 : "No camera notch detected, so Patchbeam shows a small floating capsule below the menu bar instead.")
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 6) {
                shortcut("⌃⌥Space", "Open or close Patchbeam")
                shortcut("Hover", "Glance at the current repair")
                shortcut("Drop a .log", "Onto the notch to start a repair")
                shortcut("⌘↩", "Primary action · ⌘. Stop · ⌘1/2/3 tabs · Esc close")
            }
            if let err = model.hotKeyStatus { Text(err).font(.caption).foregroundStyle(Theme.warning) }
        }
    }

    private func shortcut(_ key: String, _ what: String) -> some View {
        HStack {
            Text(key).font(Theme.mono(12)).frame(width: 110, alignment: .leading).foregroundStyle(Theme.accent)
            Text(what).foregroundStyle(Theme.textSecondary)
        }
    }

    private var agents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agents").font(.title2.weight(.semibold))
            Text("Patchbeam doesn't include a model. It drives a coding agent CLI you already use and are signed in to. It reports sign-in status only and never reads your credentials.")
                .foregroundStyle(Theme.textSecondary)
            ForEach(model.descriptors, id: \.id) { d in
                let p = model.providers[d.id]
                HStack(alignment: .top) {
                    Image(systemName: p?.isReady == true ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(p?.isReady == true ? Theme.ready : Theme.warning)
                    VStack(alignment: .leading) {
                        Text(d.displayName).font(.system(size: 13, weight: .semibold))
                        Text(p?.message ?? "Checking…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        if let hint = p?.setupHint { Text(hint).font(Theme.mono(11)).foregroundStyle(Theme.textSubdued).textSelection(.enabled) }
                    }
                }
            }
            Button("Re-check") { Task { await model.refreshProviders() } }.buttonStyle(PanelButtonStyle())
        }
    }

    private var proof: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Proof belongs to your Mac, not the model").font(.title2.weight(.semibold))
            Text("• You choose and approve the check command (e.g. `python3 -m unittest -v`). It runs without a shell.\n• “Selected checks passed” appears only when that command exits 0 for the exact patch you're reviewing.\n• Edit the files afterwards and the green badge is revoked until you re-run.\n• A worktree isolates Git state. It isn't a security sandbox.")
                .foregroundStyle(Theme.textSecondary).font(.system(size: 13))
        }
    }

    private var tryIt: some View {
        VStack(spacing: 14) {
            Text("Try a real, offline repair").font(.title2.weight(.semibold))
            Text("Patchbeam creates a tiny broken Python project in its own folder. The scripted DemoAgent (no model) fixes it in a worktree, and your Mac runs the real tests: red, then green.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
            Button("Open the Demo in the Notch") {
                finish()
                Task { await model.prepareDemo() }
            }
            .buttonStyle(PanelButtonStyle(kind: .primary))
        }
    }
}

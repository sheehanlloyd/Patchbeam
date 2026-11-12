import PatchbeamCore
import SwiftUI

/// Root of the panel. The window may be larger than the shape while animating; the shape is
/// top-anchored and centered so it grows out of the notch.
struct NotchRootView: View {
    @Bindable var model: AppModel
    @Bindable var layout: PanelLayoutState
    @State private var hoverTask: Task<Void, Never>?

    private var notchMode: Bool { layout.geometry?.layoutMode == .notch }
    private var topInset: CGFloat { layout.geometry?.reservedTopInset ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            island
                .frame(width: max(1, layout.shapeSize.width), height: max(1, layout.shapeSize.height))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var island: some View {
        let expandedish = layout.presentation == .expanded || layout.presentation == .intake
        let shape = IslandShape(topFlare: notchMode ? (layout.presentation == .dormant ? 6 : 10) : 0,
                                bottomRadius: layout.presentation == .dormant ? (notchMode ? 10 : 13) : (expandedish ? Theme.panelRadius : 18))
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if !notchMode {
                // Floating capsule on non-notched displays: no fake camera cutout, subtle edge.
                shape.stroke(Theme.separator.opacity(0.8), lineWidth: 0.5)
            }
            content
                .padding(.top, layout.presentation == .dormant ? 0 : topInset)
                .padding(.horizontal, notchMode ? 10 : 0)
                .transition(.opacity)
                .id(layout.presentation)
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(layout.presentation == .dormant ? 0 : 0.45), radius: 14, y: 6)
        .overlay(alignment: .bottom) {
            if model.dropTargeted {
                SwiftUI.Capsule().fill(Theme.accentGradient).frame(height: 1.5).padding(.horizontal, 24).blur(radius: 0.4)
            }
        }
        .contentShape(shape)
        .onHover(perform: hover)
        .onDrop(of: [.fileURL, .plainText, .utf8PlainText], isTargeted: Binding(
            get: { model.dropTargeted },
            set: { targeted in
                model.dropTargeted = targeted
                if targeted && model.presentation == .dormant { model.presentation = .glance }
                if !targeted && model.presentation == .glance { scheduleCollapseFromGlance() }
            }
        )) { providers in model.handleDrop(providers) }
        .onExitCommand { model.escape() }
    }

    @ViewBuilder
    private var content: some View {
        switch layout.presentation {
        case .dormant:
            DormantView(model: model, notchWidth: layout.geometry?.notchRect.width ?? 0, notchMode: notchMode)
        case .glance:
            GlanceView(model: model)
        case .expanded:
            CockpitView(model: model)
        case .intake:
            IntakeView(model: model)
        }
    }

    /// Hover with a ~200 ms dwell opens a glance; click and hotkey act instantly (PRD §7.3).
    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard UserDefaults.standard.object(forKey: "hoverToGlance") as? Bool ?? true else { return }
        if inside, model.presentation == .dormant {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled, model.presentation == .dormant else { return }
                model.presentation = .glance
            }
        } else if !inside, model.presentation == .glance {
            scheduleCollapseFromGlance()
        }
    }

    private func scheduleCollapseFromGlance() {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, model.presentation == .glance, !model.dropTargeted else { return }
            model.presentation = .dormant
        }
    }
}

/// S0: no text; only a tiny peripheral signal when work exists. Click opens.
struct DormantView: View {
    var model: AppModel
    var notchWidth: CGFloat
    var notchMode: Bool

    var body: some View {
        let c = model.glanceCapsule
        HStack(spacing: 0) {
            if let c {
                let style = StatusStyle(c.status)
                Circle().fill(style.color).frame(width: 5, height: 5)
                    .padding(.leading, notchMode ? 4 : 10)
                Spacer(minLength: 0)
                if c.status == .awaitingApproval {
                    Circle().fill(Theme.warning).frame(width: 5, height: 5).padding(.trailing, notchMode ? 4 : 10)
                }
            } else if !notchMode {
                Spacer()
                PatchbeamGlyph(size: 13)
                Spacer()
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleFromHotKey() }
        .accessibilityElement()
        .accessibilityLabel(c.map { "Patchbeam: \($0.repoDisplayName), \($0.status.label)" } ?? "Open Patchbeam")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.toggleFromHotKey() }
    }
}

/// S1: repo · status, thin rail. At most two pieces of information.
struct GlanceView: View {
    var model: AppModel

    var body: some View {
        Group {
            if model.dropTargeted {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Theme.accent)
                    Text("Drop log to inspect").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                }
            } else if let c = model.glanceCapsule {
                let style = StatusStyle(c.status)
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: style.symbol).foregroundStyle(style.color).font(.system(size: 12, weight: .semibold))
                        Text(c.repoDisplayName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(style.label).font(.system(size: 12)).foregroundStyle(style.color).lineLimit(1)
                    }
                    if style.isLive {
                        BeamRail(phase: model.events[c.id]?.last?.phase, live: true, color: style.color)
                    }
                }
                .padding(.horizontal, 14)
            } else {
                HStack(spacing: 8) {
                    PatchbeamGlyph(size: 14)
                    Text("What broke?").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("⌃⌥Space").font(Theme.mono(10.5)).foregroundStyle(Theme.textSubdued)
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.glanceCapsule == nil ? model.beginIntake() : model.open(.expanded) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.glanceCapsule.map { "Running repair for \($0.repoDisplayName): \($0.status.label)" } ?? "Open Patchbeam")
        .accessibilityAddTraits(.isButton)
    }
}

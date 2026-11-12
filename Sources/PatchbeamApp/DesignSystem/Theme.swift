import AppKit
import PatchbeamCore
import SwiftUI

/// Visual tokens from PRD §7.1. Patchbeam's panel is always dark (it sits beside the black
/// camera housing), so these are fixed rather than appearance-dependent.
enum Theme {
    static let background = Color(hex: 0x0D1016)
    static let surface = Color(hex: 0x171C26)
    static let surfaceRaised = Color(hex: 0x1E2430)
    static let separator = Color(hex: 0x303846)
    static let text = Color(hex: 0xF5F7FB)
    static let textSecondary = Color(hex: 0xA8B2C4)
    static let textSubdued = Color(hex: 0x758298)
    static let accent = Color(hex: 0x8C93FF)
    static let accentBlue = Color(hex: 0x5C8DFF)
    static let executing = Color(hex: 0x79B5FF)
    static let ready = Color(hex: 0x59D5A3)
    static let warning = Color(hex: 0xFFC36E)
    static let failed = Color(hex: 0xFF7D83)

    static let accentGradient = LinearGradient(colors: [accent, accentBlue], startPoint: .leading, endPoint: .trailing)

    static let panelRadius: CGFloat = 24
    static let innerRadius: CGFloat = 13

    static func mono(_ size: CGFloat = 11.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Every status has a color **and** an icon **and** a word (never color alone, PRD §22).
struct StatusStyle {
    let color: Color
    let symbol: String
    let label: String
    let isLive: Bool

    init(_ status: CapsuleStatus) {
        label = status.label
        switch status {
        case .preparingWorktree, .queued, .running, .retrying, .reconciling:
            color = Theme.executing; symbol = "bolt.horizontal.circle"; isLive = true
        case .verifying:
            color = Theme.executing; symbol = "checklist"; isLive = true
        case .awaitingApproval:
            color = Theme.warning; symbol = "hand.raised.circle"; isLive = false
        case .reviewReadyVerified:
            color = Theme.ready; symbol = "checkmark.seal"; isLive = false
        case .applied:
            color = Theme.ready; symbol = "arrow.down.doc"; isLive = false
        case .reviewReadyFailed, .failed:
            color = Theme.failed; symbol = "xmark.octagon"; isLive = false
        case .reviewReadyUnverified:
            color = Theme.warning; symbol = "exclamationmark.triangle"; isLive = false
        case .cancelling:
            color = Theme.textSecondary; symbol = "stop.circle"; isLive = true
        case .cancelled, .discarded, .kept:
            color = Theme.textSecondary; symbol = status == .kept ? "tray.full" : "stop.circle"; isLive = false
        case .interrupted, .needsRestart, .resumable:
            color = Theme.warning; symbol = "exclamationmark.arrow.circlepath"; isLive = false
        case .draft, .ready:
            color = Theme.textSecondary; symbol = "circle.dashed"; isLive = false
        }
    }
}

/// Original Patchbeam glyph: two offset rays converging into a diff "+" mark.
struct PatchbeamGlyph: View {
    var size: CGFloat = 16
    var color: Color? = nil

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let stroke = max(1.4, w * 0.11)
            var ray1 = Path()
            ray1.move(to: CGPoint(x: w * 0.06, y: h * 0.30))
            ray1.addLine(to: CGPoint(x: w * 0.52, y: h * 0.50))
            var ray2 = Path()
            ray2.move(to: CGPoint(x: w * 0.06, y: h * 0.74))
            ray2.addLine(to: CGPoint(x: w * 0.52, y: h * 0.50))
            var plus = Path()
            plus.move(to: CGPoint(x: w * 0.62, y: h * 0.50))
            plus.addLine(to: CGPoint(x: w * 0.96, y: h * 0.50))
            plus.move(to: CGPoint(x: w * 0.79, y: h * 0.33))
            plus.addLine(to: CGPoint(x: w * 0.79, y: h * 0.67))
            let style = StrokeStyle(lineWidth: stroke, lineCap: .round)
            if let color {
                for p in [ray1, ray2, plus] { ctx.stroke(p, with: .color(color), style: style) }
            } else {
                let g = GraphicsContext.Shading.linearGradient(Gradient(colors: [Theme.accent, Theme.accentBlue]),
                                                              startPoint: .zero, endPoint: CGPoint(x: w, y: h))
                ctx.stroke(ray1, with: g, style: style)
                ctx.stroke(ray2, with: g, style: style)
                ctx.stroke(plus, with: .color(Theme.ready), style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Template image for the menu bar.
    @MainActor static func menuBarImage() -> NSImage {
        let renderer = ImageRenderer(content: PatchbeamGlyph(size: 18, color: .black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "plus.diamond", accessibilityDescription: "Patchbeam")!
        image.isTemplate = true
        image.accessibilityDescription = "Patchbeam"
        return image
    }
}

/// Thin execution beam. It animates only while work is actually executing; otherwise static.
/// Phase position moves left (diagnosis) → right (proof) per PRD §7.4.
struct BeamRail: View {
    var phase: AgentEvent.Phase?
    var live: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("reduceMotionOverride") private var reduceMotionOverride = false

    private var progress: CGFloat {
        switch phase {
        case .preparing: 0.12
        case .diagnosing: 0.30
        case .editing: 0.55
        case .verifying: 0.80
        case .reviewing, .done: 1.0
        case nil: 0
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                SwiftUI.Capsule().fill(Theme.separator.opacity(0.7))
                SwiftUI.Capsule().fill(color.opacity(0.55)).frame(width: max(4, geo.size.width * progress))
                if live && !(systemReduceMotion || reduceMotionOverride) {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let x = CGFloat((t.truncatingRemainder(dividingBy: 1.6)) / 1.6)
                        SwiftUI.Capsule()
                            .fill(LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 60)
                            .offset(x: -60 + (geo.size.width * progress + 60) * x)
                    }
                    .mask(SwiftUI.Capsule().frame(width: max(4, geo.size.width * progress)).frame(maxWidth: .infinity, alignment: .leading))
                }
            }
        }
        .frame(height: 3)
        .clipShape(SwiftUI.Capsule())
        .accessibilityHidden(true)
    }
}

struct Chip: View {
    var text: String
    var symbol: String? = nil
    var tint: Color = Theme.textSecondary
    var mono = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)) }
            Text(text).font(mono ? Theme.mono(10.5) : .system(size: 10.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(SwiftUI.Capsule().fill(tint.opacity(0.12)))
        .overlay(SwiftUI.Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }
}

/// Unmistakable label for scripted runs (PB-021).
struct DemoBadge: View {
    var body: some View {
        Chip(text: "Demo — no model used", symbol: "theatermasks", tint: Theme.warning)
            .accessibilityLabel("Demo mode. No model used.")
    }
}

struct PanelButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, quiet }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background(configuration.isPressed)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: 0.5))
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: Color(hex: 0x0D1016)
        case .destructive: Theme.failed
        case .secondary: Theme.text
        case .quiet: Theme.textSecondary
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: (pressed ? Theme.accent.opacity(0.8) : Theme.accent)
        case .destructive: Theme.failed.opacity(pressed ? 0.22 : 0.12)
        case .secondary: Theme.surfaceRaised.opacity(pressed ? 0.7 : 1)
        case .quiet: Color.white.opacity(pressed ? 0.08 : 0.0001)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .clear
        case .destructive: Theme.failed.opacity(0.3)
        default: Theme.separator
        }
    }
}

/// Island silhouette: flush with the screen top, small concave "shoulders" where it meets the
/// menu bar (like the hardware housing), rounded bottom corners.
struct IslandShape: Shape {
    var topFlare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFlare, bottomRadius) }
        set { topFlare = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let f = min(topFlare, rect.width / 4)
        let r = min(bottomRadius, rect.height / 2, (rect.width - 2 * f) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.minY + f), control: CGPoint(x: rect.minX + f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + f + r, y: rect.maxY), control: CGPoint(x: rect.minX + f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.maxY - r), control: CGPoint(x: rect.maxX - f, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// The domain capsule wins inside the app; the SwiftUI shape is spelled `SwiftUI.Capsule`.
typealias Capsule = PatchbeamCore.Capsule

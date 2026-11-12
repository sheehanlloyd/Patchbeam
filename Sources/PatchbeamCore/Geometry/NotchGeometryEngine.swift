import CoreGraphics
import Foundation

/// A plain value snapshot of an `NSScreen`, so geometry can be unit tested without AppKit.
/// All rects use AppKit global coordinates (origin bottom-left of the primary display).
public struct ScreenDescriptor: Sendable, Equatable, Codable {
    public var id: String
    public var localizedName: String
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`; non-zero on notched built-in displays.
    public var safeAreaTop: CGFloat
    /// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (menu-bar areas beside the notch).
    public var auxiliaryTopLeft: CGRect?
    public var auxiliaryTopRight: CGRect?
    public var backingScale: CGFloat
    public var isBuiltIn: Bool

    public init(
        id: String,
        localizedName: String,
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?,
        backingScale: CGFloat,
        isBuiltIn: Bool
    ) {
        self.id = id
        self.localizedName = localizedName
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
        self.backingScale = backingScale
        self.isBuiltIn = isBuiltIn
    }

    /// True only when the OS reports a top safe-area inset *and* both auxiliary areas,
    /// i.e. there really is a camera housing between two menu-bar regions.
    public var hasNotch: Bool {
        safeAreaTop > 0 && auxiliaryTopLeft != nil && auxiliaryTopRight != nil
    }
}

public enum LayoutMode: String, Sendable, Codable {
    /// Integrated with a physical camera housing reported by the OS.
    case notch
    /// Non-notched or external display: a floating capsule below the menu bar.
    case floatingCapsule
}

/// The presentation states from PRD §7.2.
public enum PanelPresentation: String, Sendable, Codable, CaseIterable {
    case dormant   // S0
    case glance    // S1
    case expanded  // S2 / S3 (review is an expanded variant)
    case intake    // S4
}

public struct NotchGeometry: Sendable, Equatable {
    public var screenFrame: CGRect
    public var visibleFrame: CGRect
    public var layoutMode: LayoutMode
    /// Approximate camera-housing rect in global coordinates (zero-width in capsule mode).
    public var notchRect: CGRect
    public var menuBarHeight: CGFloat
    public var displayScale: CGFloat

    /// The vertical band at the top of a panel that must stay content-free because the
    /// hardware cutout sits there. Zero in floating-capsule mode.
    public var reservedTopInset: CGFloat {
        layoutMode == .notch ? notchRect.height : 0
    }
}

public struct PanelLayoutMetrics: Sendable, Equatable {
    public var glanceSize = CGSize(width: 340, height: 44)
    public var expandedWidth: CGFloat = 480
    public var intakeWidth: CGFloat = 480
    public var maxContentHeight: CGFloat = 580
    public var maxScreenFraction: CGFloat = 0.70
    /// Dormant island extends this far beyond each side of the notch.
    public var dormantShoulder: CGFloat = 6
    public var floatingDormantSize = CGSize(width: 132, height: 26)
    /// Gap between the menu bar and the floating capsule.
    public var floatingTopGap: CGFloat = 6
    /// Padding around the visible shape reserved for its soft shadow (non-dormant only).
    public var shadowInset: CGFloat = 16
    /// Minimum distance from screen edges.
    public var edgeMargin: CGFloat = 8

    public init() {}
}

/// Pure geometry for the notch panel. Derives layout from reported display metrics,
/// never from hardware model identifiers (PRD §8.2).
public struct NotchGeometryEngine: Sendable {
    public var metrics: PanelLayoutMetrics

    public init(metrics: PanelLayoutMetrics = PanelLayoutMetrics()) {
        self.metrics = metrics
    }

    public func geometry(for screen: ScreenDescriptor) -> NotchGeometry {
        let frame = screen.frame
        let menuBarHeight = max(0, frame.maxY - screen.visibleFrame.maxY)
        if screen.hasNotch, let left = screen.auxiliaryTopLeft, let right = screen.auxiliaryTopRight, right.minX > left.maxX {
            let height = screen.safeAreaTop
            let notch = CGRect(x: left.maxX, y: frame.maxY - height, width: right.minX - left.maxX, height: height)
            return NotchGeometry(
                screenFrame: frame,
                visibleFrame: screen.visibleFrame,
                layoutMode: .notch,
                notchRect: notch,
                menuBarHeight: max(menuBarHeight, height),
                displayScale: screen.backingScale
            )
        }
        return NotchGeometry(
            screenFrame: frame,
            visibleFrame: screen.visibleFrame,
            layoutMode: .floatingCapsule,
            notchRect: CGRect(x: frame.midX, y: frame.maxY - menuBarHeight, width: 0, height: menuBarHeight),
            menuBarHeight: menuBarHeight,
            displayScale: screen.backingScale
        )
    }

    /// The visible shape's size for a presentation, before shadow padding.
    public func shapeSize(for presentation: PanelPresentation, geometry g: NotchGeometry, contentHeight: CGFloat = 0) -> CGSize {
        let maxHeight = maxPanelHeight(g)
        switch (presentation, g.layoutMode) {
        case (.dormant, .notch):
            return CGSize(width: g.notchRect.width + metrics.dormantShoulder * 2, height: g.notchRect.height)
        case (.dormant, .floatingCapsule):
            return metrics.floatingDormantSize
        case (.glance, _):
            let width = max(metrics.glanceSize.width, g.layoutMode == .notch ? g.notchRect.width + 120 : 0)
            return CGSize(width: width, height: min(maxHeight, g.reservedTopInset + metrics.glanceSize.height))
        case (.expanded, _):
            let content = min(max(contentHeight, 160), metrics.maxContentHeight)
            return CGSize(width: max(metrics.expandedWidth, g.notchRect.width + 80), height: min(maxHeight, g.reservedTopInset + content))
        case (.intake, _):
            let content = min(max(contentHeight, 200), metrics.maxContentHeight)
            return CGSize(width: max(metrics.intakeWidth, g.notchRect.width + 80), height: min(maxHeight, g.reservedTopInset + content))
        }
    }

    /// Largest panel height allowed: ≤ min(580 pt + notch, 70% of the usable display).
    public func maxPanelHeight(_ g: NotchGeometry) -> CGFloat {
        let usable = g.layoutMode == .notch ? g.screenFrame.height : g.visibleFrame.height
        return min(g.reservedTopInset + metrics.maxContentHeight, usable * metrics.maxScreenFraction)
    }

    /// Window frame for a presentation: the shape plus shadow padding, centered on the
    /// notch (or display), top-anchored, and clamped on-screen.
    public func panelFrame(for presentation: PanelPresentation, geometry g: NotchGeometry, contentHeight: CGFloat = 0) -> CGRect {
        let shape = shapeSize(for: presentation, geometry: g, contentHeight: contentHeight)
        let pad = presentation == .dormant ? 0 : metrics.shadowInset
        let width = min(shape.width + pad * 2, g.screenFrame.width - metrics.edgeMargin * 2)
        let height = shape.height + pad
        let top: CGFloat
        switch g.layoutMode {
        case .notch:
            top = g.screenFrame.maxY
        case .floatingCapsule:
            top = g.visibleFrame.maxY - metrics.floatingTopGap
        }
        let centerX = g.layoutMode == .notch ? g.notchRect.midX : g.screenFrame.midX
        var frame = CGRect(x: centerX - width / 2, y: top - height, width: width, height: height)
        // Clamp horizontally and vertically to the display.
        let minX = g.screenFrame.minX + metrics.edgeMargin
        let maxX = g.screenFrame.maxX - metrics.edgeMargin
        if frame.minX < minX { frame.origin.x = minX }
        if frame.maxX > maxX { frame.origin.x = maxX - frame.width }
        let floor = g.visibleFrame.minY + metrics.edgeMargin
        if frame.minY < floor {
            frame.size.height = max(0, top - floor)
            frame.origin.y = floor
        }
        return frame.integral
    }

    /// Choose the display: the user's preference if still attached, else the built-in
    /// notched display, else the first screen. Returns nil only with no screens.
    public func selectScreen(_ screens: [ScreenDescriptor], preferredID: String?) -> ScreenDescriptor? {
        if let preferredID, let match = screens.first(where: { $0.id == preferredID }) { return match }
        if let notched = screens.first(where: { $0.hasNotch }) { return notched }
        if let builtIn = screens.first(where: { $0.isBuiltIn }) { return builtIn }
        return screens.first
    }
}

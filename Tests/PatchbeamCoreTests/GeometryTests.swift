import CoreGraphics
import Testing
@testable import PatchbeamCore

/// Real metrics captured from `NSScreen` on the build host (Mac16,8, MacBook Pro 14",
/// default "looks like 1512×982" scaling) on 2026-11-11.
let observedMacBookPro14 = ScreenDescriptor(
    id: "1",
    localizedName: "Built-in Retina Display",
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32,
    auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
    auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32),
    backingScale: 2,
    isBuiltIn: true
)

/// Synthetic external monitor placed to the right of the laptop, no notch.
let externalMonitor = ScreenDescriptor(
    id: "2",
    localizedName: "External",
    frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1512, y: -200, width: 2560, height: 1415),
    safeAreaTop: 0,
    auxiliaryTopLeft: nil,
    auxiliaryTopRight: nil,
    backingScale: 1,
    isBuiltIn: false
)

@Suite("NotchGeometryEngine")
struct GeometryTests {
    let engine = NotchGeometryEngine()

    @Test func detectsPhysicalNotchFromAuxiliaryAreas() {
        let g = engine.geometry(for: observedMacBookPro14)
        #expect(g.layoutMode == .notch)
        #expect(g.notchRect == CGRect(x: 663, y: 950, width: 185, height: 32))
        #expect(g.reservedTopInset == 32)
    }

    @Test func safeAreaWithoutAuxiliaryAreasIsNotANotch() {
        var screen = observedMacBookPro14
        screen.auxiliaryTopRight = nil
        #expect(engine.geometry(for: screen).layoutMode == .floatingCapsule)
    }

    @Test func dormantHugsTheNotch() {
        let g = engine.geometry(for: observedMacBookPro14)
        let frame = engine.panelFrame(for: .dormant, geometry: g)
        #expect(frame.maxY == 982, "top-anchored to the display edge")
        #expect(frame.height == 32)
        #expect(frame.midX == g.notchRect.midX)
        #expect(frame.width == CGFloat(185 + 12), "\(frame.width.description) \(frame)")
    }

    @Test(arguments: PanelPresentation.allCases)
    func everyPresentationStaysOnScreen(_ p: PanelPresentation) {
        for screen in [observedMacBookPro14, externalMonitor] {
            let g = engine.geometry(for: screen)
            for content in [CGFloat(0), 300, 2000] {
                let f = engine.panelFrame(for: p, geometry: g, contentHeight: content)
                #expect(screen.frame.contains(f), "\(p) on \(screen.localizedName) content \(content): \(f)")
                #expect(f.width > 0 && f.height > 0)
            }
        }
    }

    @Test func expandedHeightRespectsCaps() {
        let g = engine.geometry(for: observedMacBookPro14)
        let f = engine.panelFrame(for: .expanded, geometry: g, contentHeight: 5000)
        // 70% of 982 = 687.4 → capped below 580 + 32 = 612 because 612 < 687.
        #expect(f.height <= 612 + engine.metrics.shadowInset)
    }

    @Test func expandedCapsAtSeventyPercentOnShortDisplays() {
        var short = observedMacBookPro14
        short.frame = CGRect(x: 0, y: 0, width: 1280, height: 600)
        short.visibleFrame = CGRect(x: 0, y: 0, width: 1280, height: 568)
        short.auxiliaryTopLeft = CGRect(x: 0, y: 568, width: 547, height: 32)
        short.auxiliaryTopRight = CGRect(x: 733, y: 568, width: 547, height: 32)
        let g = engine.geometry(for: short)
        let shape = engine.shapeSize(for: .expanded, geometry: g, contentHeight: 5000)
        #expect(shape.height <= 600 * 0.70 + 0.001)
    }

    @Test func externalDisplayUsesFloatingCapsuleBelowMenuBar() {
        let g = engine.geometry(for: externalMonitor)
        #expect(g.layoutMode == .floatingCapsule)
        #expect(g.reservedTopInset == 0)
        let f = engine.panelFrame(for: .dormant, geometry: g)
        #expect(f.maxY <= externalMonitor.visibleFrame.maxY, "never covers menu-bar items")
        #expect(abs(f.midX - externalMonitor.frame.midX) <= 1)
    }

    @Test func retinaScaleDoesNotChangePointGeometry() {
        var x1 = observedMacBookPro14
        x1.backingScale = 1
        #expect(engine.panelFrame(for: .glance, geometry: engine.geometry(for: x1))
            == engine.panelFrame(for: .glance, geometry: engine.geometry(for: observedMacBookPro14)))
    }

    @Test func narrowDisplayClampsWidth() {
        let tiny = ScreenDescriptor(
            id: "3", localizedName: "Tiny", frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 276), safeAreaTop: 0,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil, backingScale: 1, isBuiltIn: false)
        let g = engine.geometry(for: tiny)
        let f = engine.panelFrame(for: .expanded, geometry: g, contentHeight: 400)
        #expect(f.minX >= 8 && f.maxX <= 392)
        #expect(f.minY >= 8)
    }

    @Test func screenSelectionFallsBackWhenPreferredDisplayIsGone() {
        #expect(engine.selectScreen([externalMonitor, observedMacBookPro14], preferredID: "2")?.id == "2")
        #expect(engine.selectScreen([externalMonitor, observedMacBookPro14], preferredID: "99")?.id == "1",
                "unplugged preference re-homes to the notched display")
        #expect(engine.selectScreen([externalMonitor], preferredID: "1")?.id == "2")
        #expect(engine.selectScreen([], preferredID: nil) == nil)
    }
}

import AppKit
import PatchbeamCore

/// Opt-in, developer-only evidence capture. When `PATCHBEAM_CAPTURE_DIR` is set, Patchbeam
/// renders **its own panel window** (never the desktop or other apps) to numbered PNG frames.
/// No Screen Recording permission is involved: the app only draws its own view hierarchy.
@MainActor
final class EvidenceRecorder {
    let directory: URL
    private weak var view: NSView?
    private var timer: Timer?
    private var index = 0
    private let fps: Double

    init?(view: NSView, environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let dir = environment["PATCHBEAM_CAPTURE_DIR"], !dir.isEmpty else { return nil }
        directory = URL(fileURLWithPath: dir, isDirectory: true)
        self.view = view
        fps = Double(environment["PATCHBEAM_CAPTURE_FPS"] ?? "") ?? 12
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureFrame() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Render the panel's content view at backing resolution.
    func image() -> NSBitmapImageRep? {
        guard let view, view.bounds.width > 1, view.bounds.height > 1 else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    func captureFrame() {
        guard let rep = image(), let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = directory.appendingPathComponent(String(format: "frame-%05d.png", index))
        index += 1
        try? data.write(to: url)
    }

    func still(_ name: String) {
        guard let rep = image(), let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("still-\(name).png"))
    }
}

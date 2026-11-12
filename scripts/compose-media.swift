// Composes frames rendered by the running Patchbeam app (PATCHBEAM_CAPTURE_DIR) onto a
// 1920×1080 canvas with captions derived from the app state recorded *for that frame*
// (frames.tsv). It adds labels only; it never alters or synthesizes UI.
//
// usage: swift scripts/compose-media.swift <capture-dir> <out-dir> [speed-label]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: compose-media.swift <capture-dir> <out-dir> [speed-label]\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let speedLabel = args.count > 3 ? args[3] : "real time"
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

struct FrameState {
    var index: Int
    var presentation: String
    var status: String
    var label: String
    var lastEvent: String
    var tab: String
    var confirming: Bool
}

let tsv = (try? String(contentsOf: input.appendingPathComponent("frames.tsv"), encoding: .utf8)) ?? ""
let states: [FrameState] = tsv.split(separator: "\n").compactMap { line in
    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 8, let i = Int(f[0]) else { return nil }
    return FrameState(index: i, presentation: f[2], status: f[3], label: f[4], lastEvent: f[5], tab: f[6], confirming: f[7] == "confirm")
}

func caption(_ s: FrameState) -> (String, String) {
    switch s.presentation {
    case "dormant":
        return s.status == "applied" ? ("Back to the notch", "The capsule keeps its proof trail; the island stays quiet.")
            : ("Dormant in the notch", "Patchbeam stays black around the camera housing until you need it.")
    case "glance":
        return s.status.isEmpty ? ("Glance", "Hover the notch (≈200 ms dwell) or press ⌃⌥Space.")
            : ("Glance: \(s.label)", "At most two facts while collapsed.")
    case "intake":
        return ("Intake: what broke?", "A real broken-python fixture repo, its failing traceback, the DemoAgent, and an explicitly approved check.")
    default:
        if s.confirming { return ("Explicit apply", "Working tree only. Patchbeam checks the base commit and dirty files first. Nothing is committed or pushed.") }
        switch s.status {
        case "reviewReadyVerified":
            let what = s.tab == "Changes" ? "Git diff from the base commit" : s.tab == "Proof" ? "Host-run check: before exit 1 → after exit 0" : "Activity log"
            return ("Selected checks passed — \(what)", "Proof comes from the exit code of python3 -m unittest -v, run by Patchbeam in the worktree.")
        case "applied":
            return ("Applied to the working tree", "The source repo now passes; HEAD is unchanged and nothing is staged.")
        case "":
            return ("Cockpit", "")
        default:
            return (s.label, s.lastEvent)
        }
    }
}

let W: CGFloat = 1920, H: CGFloat = 1080
let bg = NSColor(srgbRed: 0x0D / 255, green: 0x10 / 255, blue: 0x16 / 255, alpha: 1)
let secondary = NSColor(srgbRed: 0xA8 / 255, green: 0xB2 / 255, blue: 0xC4 / 255, alpha: 1)
let subdued = NSColor(srgbRed: 0x75 / 255, green: 0x82 / 255, blue: 0x98 / 255, alpha: 1)

func draw(_ text: String, font: NSFont, color: NSColor, in rect: CGRect, align: NSTextAlignment = .center) {
    let p = NSMutableParagraphStyle()
    p.alignment = align
    p.lineBreakMode = .byTruncatingTail
    (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
}

let frameFiles = (try FileManager.default.contentsOfDirectory(atPath: input.path)).filter { $0.hasPrefix("frame-") }.sorted()
var written = 0
for (n, name) in frameFiles.enumerated() {
    guard let image = NSImage(contentsOf: input.appendingPathComponent(name)),
          let rep = image.representations.first else { continue }
    let index = Int(name.dropFirst(6).prefix(5)) ?? n
    let state = states.first { $0.index == index } ?? FrameState(index: index, presentation: "", status: "", label: "", lastEvent: "", tab: "", confirming: false)

    let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
    bg.setFill()
    CGRect(x: 0, y: 0, width: W, height: H).fill()

    // Panel pixels are @2x; draw at 0.8 of pixel size, top-centered like the notch.
    let scale: CGFloat = 0.8
    let pw = CGFloat(rep.pixelsWide) * scale, ph = CGFloat(rep.pixelsHigh) * scale
    let top: CGFloat = H - 40
    image.draw(in: CGRect(x: (W - pw) / 2, y: top - ph, width: pw, height: ph), from: .zero, operation: .sourceOver, fraction: 1)

    let (title, detail) = caption(state)
    draw(title, font: .systemFont(ofSize: 34, weight: .semibold), color: .white, in: CGRect(x: 120, y: 92, width: W - 240, height: 46))
    draw(detail, font: .systemFont(ofSize: 22), color: secondary, in: CGRect(x: 120, y: 58, width: W - 240, height: 30))
    draw("Real Patchbeam app on macOS · scripted DemoAgent (no model) · app's own panel window, no desktop · \(speedLabel)",
         font: .systemFont(ofSize: 17), color: subdued, in: CGRect(x: 60, y: 18, width: W - 120, height: 24))
    NSGraphicsContext.restoreGraphicsState()

    let out = output.appendingPathComponent(String(format: "c-%05d.png", written))
    try canvas.representation(using: .png, properties: [:])!.write(to: out)
    written += 1
}
print("composed \(written) frames → \(output.path)")

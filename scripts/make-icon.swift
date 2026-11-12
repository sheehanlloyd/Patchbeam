// Renders Patchbeam's original glyph (two rays converging into a diff "+") into an .iconset.
// usage: swift scripts/make-icon.swift <out.iconset>
import AppKit
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let tile = NSBezierPath(roundedRect: CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: color(0x1B2130), ending: color(0x0B0E13))!.draw(in: tile, angle: -90)
    color(0x303846).setStroke(); tile.lineWidth = max(1, s * 0.006); tile.stroke()
    let g = CGRect(x: s * 0.24, y: s * 0.24, width: s * 0.52, height: s * 0.52)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: g.minX + g.width * x, y: g.maxY - g.height * y) }
    let w = g.width * 0.11
    let rays = NSBezierPath(); rays.lineWidth = w; rays.lineCapStyle = .round
    rays.move(to: p(0.06, 0.30)); rays.line(to: p(0.52, 0.50)); rays.move(to: p(0.06, 0.74)); rays.line(to: p(0.52, 0.50))
    NSGraphicsContext.current?.saveGraphicsState()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.addPath(rays.cgPath.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)); ctx.clip()
    NSGradient(starting: color(0x8C93FF), ending: color(0x5C8DFF))!.draw(in: g, angle: -30)
    NSGraphicsContext.current?.restoreGraphicsState()
    let plus = NSBezierPath(); plus.lineWidth = w; plus.lineCapStyle = .round
    plus.move(to: p(0.62, 0.50)); plus.line(to: p(0.96, 0.50)); plus.move(to: p(0.79, 0.33)); plus.line(to: p(0.79, 0.67))
    color(0x59D5A3).setStroke(); plus.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}

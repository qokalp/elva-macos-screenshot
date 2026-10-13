// AppIcon.icns üretir: swift Scripts/make_icon.swift <çıktı klasörü>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.62, alpha: 1)])!
        .draw(in: path, angle: -60)

    // Eğik "polaroid" kartlar
    for (angle, alpha) in [(-10.0, 0.55), (8.0, 1.0)] {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: s / 2, yBy: s / 2)
        t.rotate(byDegrees: angle)
        t.concat()
        let w = s * 0.46, h = s * 0.38
        let card = NSRect(x: -w / 2, y: -h / 2, width: w, height: h)
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: card, xRadius: s * 0.02, yRadius: s * 0.02).fill()
        if alpha == 1 {
            let inner = card.insetBy(dx: s * 0.03, dy: s * 0.03).offsetBy(dx: 0, dy: s * 0.015)
            let innerRect = NSRect(x: inner.minX, y: inner.minY + s * 0.02, width: inner.width, height: inner.height - s * 0.02)
            NSGradient(colors: [NSColor(calibratedRed: 0.35, green: 0.75, blue: 1, alpha: 1),
                                NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.95, alpha: 1)])!
                .draw(in: innerRect, angle: -90)
            // dashed selection
            let sel = NSBezierPath(rect: innerRect.insetBy(dx: s * 0.05, dy: s * 0.045))
            sel.lineWidth = max(1, s * 0.012)
            sel.setLineDash([s * 0.03, s * 0.02], count: 2, phase: 0)
            NSColor.white.setStroke()
            sel.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

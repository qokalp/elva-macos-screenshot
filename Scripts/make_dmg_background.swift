// DMG penceresi arka planı: swift Scripts/make_dmg_background.swift <çıktı klasörü>
// 660×400 nokta; background.png (1x) ve background@2x.png üretir.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let size = CGSize(width: 660, height: 400)

func render(scale: CGFloat) -> Data {
    let px = Int(size.width * scale), py = Int(size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(colors: [NSColor(calibratedWhite: 0.985, alpha: 1), NSColor(calibratedWhite: 0.93, alpha: 1)])!
        .draw(in: bounds, angle: -90)

    // Üst başlık
    let title = NSAttributedString(string: "Elva Screenshot Tool for macOS", attributes: [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
    ])
    title.draw(at: NSPoint(x: (size.width - title.size().width) / 2, y: size.height - 62))

    // Ok (uygulama → Applications); ikon merkezleri y = 200 (Finder üstten ölçer)
    let y: CGFloat = size.height - 200
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: y))
    arrow.curve(to: NSPoint(x: 388, y: y), controlPoint1: NSPoint(x: 300, y: y + 26), controlPoint2: NSPoint(x: 350, y: y + 26))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 9], count: 2, phase: 0)
    let accent = NSColor(calibratedRed: 0.55, green: 0.33, blue: 0.95, alpha: 1)
    accent.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 378, y: y + 10))
    head.line(to: NSPoint(x: 392, y: y))
    head.line(to: NSPoint(x: 377, y: y - 6))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Alt açıklama (İngilizce + Türkçe)
    let lines: [(String, CGFloat, NSColor)] = [
        ("Drag the app into the Applications folder to install", 66, NSColor(calibratedWhite: 0.35, alpha: 1)),
        ("Kurmak için uygulamayı Applications klasörüne sürükleyin", 44, NSColor(calibratedWhite: 0.5, alpha: 1)),
    ]
    for (text, y, color) in lines {
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: color,
        ])
        str.draw(at: NSPoint(x: (size.width - str.size().width) / 2, y: y))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: outDir.appendingPathComponent("background.png"))
try render(scale: 2).write(to: outDir.appendingPathComponent("background@2x.png"))

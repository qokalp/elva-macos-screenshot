import AppKit

enum EditorTool: String, CaseIterable, Identifiable {
    case pen, text, highlighter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: L10n.t("Pen", "Kalem")
        case .text: L10n.t("Text", "Yazı")
        case .highlighter: L10n.t("Highlighter", "Vurgulayıcı")
        }
    }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .highlighter: "highlighter"
        }
    }
}

/// Koordinatlar görüntü piksel uzayında (sol-alt orijin).
struct Annotation: Identifiable {
    enum Kind {
        case stroke(points: [CGPoint], width: CGFloat, highlighter: Bool)
        case text(String, origin: CGPoint, fontSize: CGFloat)
    }

    let id = UUID()
    var kind: Kind
    var color: NSColor
}

enum AnnotationRenderer {
    static let highlighterAlpha: CGFloat = 0.45

    static func textAttributes(color: NSColor, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
        ]
    }

    static func draw(_ annotation: Annotation, in ctx: CGContext) {
        switch annotation.kind {
        case let .stroke(points, width, highlighter):
            guard let first = points.first else { return }
            let path = CGMutablePath()
            path.move(to: first)
            if points.count == 1 {
                path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            } else if highlighter && points.count == 2 {
                path.addLine(to: points[1])
            } else {
                // Yumuşak çizgi: ara noktalardan geçen quad eğriler.
                for i in 1..<points.count {
                    let prev = points[i - 1], cur = points[i]
                    let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
                    path.addQuadCurve(to: mid, control: prev)
                }
                path.addLine(to: points[points.count - 1])
            }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.setLineWidth(width)
            ctx.setLineJoin(.round)
            if highlighter {
                ctx.setLineCap(.square)
                ctx.setStrokeColor(annotation.color.withAlphaComponent(highlighterAlpha).cgColor)
            } else {
                ctx.setLineCap(.round)
                ctx.setStrokeColor(annotation.color.cgColor)
            }
            ctx.strokePath()
            ctx.restoreGState()

        case let .text(string, origin, fontSize):
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: string, attributes: textAttributes(color: annotation.color, fontSize: fontSize))
                .draw(at: origin)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Temel görüntü + çizimleri tek bir bitmap'e basar.
    static func render(base: CGImage, annotations: [Annotation], background: NSColor? = nil) -> CGImage {
        let w = base.width, h = base.height
        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let background {
            ctx.setFillColor(background.cgColor)
            ctx.fill(rect)
        }
        ctx.interpolationQuality = .high
        ctx.draw(base, in: rect)
        for a in annotations { draw(a, in: ctx) }
        return ctx.makeImage() ?? base
    }
}

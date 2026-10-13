import AppKit

/// Donmuş ekran görüntüsünü gösterip kare/lasso seçimi alan tam ekran pencere.
final class SelectionWindow: NSWindow {
    init(screen: NSScreen, image: CGImage, mode: CaptureMode, onFinish: @escaping (CGImage?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        setFrame(screen.frame, display: false)
        contentView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                    image: image, mode: mode, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionView: NSView {
    private let image: CGImage
    private let mode: CaptureMode
    private let onFinish: (CGImage?) -> Void

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var lassoPoints: [CGPoint] = []
    private var mouseLocation: CGPoint?

    init(frame: NSRect, image: CGImage, mode: CaptureMode, onFinish: @escaping (CGImage?) -> Void) {
        self.image = image
        self.mode = mode
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } else { super.keyDown(with: event) }
    }

    // MARK: - Mouse

    private func clamped(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let p = clamped(event)
        dragStart = p
        dragCurrent = p
        lassoPoints = [p]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = clamped(event)
        dragCurrent = p
        mouseLocation = p
        if mode == .lasso, let last = lassoPoints.last, hypot(p.x - last.x, p.y - last.y) > 1.5 {
            lassoPoints.append(p)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            lassoPoints = []
            needsDisplay = true
        }
        switch mode {
        case .rectangle:
            guard let r = selectionRect, r.width >= 4, r.height >= 4 else { return }
            onFinish(cropRect(r))
        case .lasso:
            guard lassoPoints.count > 4, let path = lassoPath(closed: true),
                  path.boundingBox.width >= 4, path.boundingBox.height >= 4 else { return }
            onFinish(cropPath(path))
        case .fullScreen:
            onFinish(image)
        }
    }

    // MARK: - Geometry

    private var pixelScale: CGFloat { CGFloat(image.width) / bounds.width }

    private var selectionRect: CGRect? {
        guard let a = dragStart, let b = dragCurrent else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).integral
    }

    private func lassoPath(closed: Bool) -> CGPath? {
        guard let first = lassoPoints.first, lassoPoints.count > 1 else { return nil }
        let path = CGMutablePath()
        path.move(to: first)
        for p in lassoPoints.dropFirst() { path.addLine(to: p) }
        if closed { path.closeSubpath() }
        return path
    }

    private var selectionPath: CGPath? {
        switch mode {
        case .rectangle: return selectionRect.map { CGPath(rect: $0, transform: nil) }
        case .lasso: return lassoPath(closed: true)
        case .fullScreen: return nil
        }
    }

    private func cropRect(_ r: CGRect) -> CGImage? {
        let s = pixelScale
        let pixelRect = CGRect(x: r.minX * s, y: (bounds.height - r.maxY) * s, width: r.width * s, height: r.height * s).integral
        return image.cropping(to: pixelRect)
    }

    private func cropPath(_ path: CGPath) -> CGImage? {
        let box = path.boundingBox.integral
        let s = pixelScale
        let w = Int(box.width * s), h = Int(box.height * s)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(image, in: bounds)
        return ctx.makeImage()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: bounds)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        ctx.fill(bounds)

        if let path = selectionPath {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.draw(image, in: bounds)
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            if mode == .lasso { ctx.setLineDash(phase: 0, lengths: [6, 4]) }
            ctx.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.6).cgColor)
            ctx.strokePath()
            ctx.restoreGState()

            if mode == .rectangle, let r = selectionRect {
                let s = pixelScale
                drawLabel("\(Int(r.width * s)) × \(Int(r.height * s))",
                          at: CGPoint(x: r.minX, y: r.minY - 26 < 4 ? r.maxY + 6 : r.minY - 26))
            }
        } else {
            if mode == .rectangle, let m = mouseLocation {
                ctx.saveGState()
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
                ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: [4, 4])
                ctx.move(to: CGPoint(x: m.x, y: 0)); ctx.addLine(to: CGPoint(x: m.x, y: bounds.height))
                ctx.move(to: CGPoint(x: 0, y: m.y)); ctx.addLine(to: CGPoint(x: bounds.width, y: m.y))
                ctx.strokePath()
                ctx.restoreGState()
            }
            let hint = mode == .lasso
                ? "Lasso: serbest çizerek alan seçin  ·  Esc ile iptal"
                : "Kare seçim: sürükleyerek alan seçin  ·  Esc ile iptal"
            drawHint(hint)
        }
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let rect = CGRect(x: point.x, y: point.y, width: size.width + 14, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        str.draw(at: CGPoint(x: rect.minX + 7, y: rect.minY + 4))
    }

    private func drawHint(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let rect = CGRect(x: (bounds.width - size.width) / 2 - 18, y: bounds.height - 120,
                          width: size.width + 36, height: size.height + 18)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        str.draw(at: CGPoint(x: rect.minX + 18, y: rect.minY + 9))
    }
}

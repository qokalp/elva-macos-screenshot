import AppKit
import SwiftUI

/// Görüntüyü sığdırarak gösterir; kalem, vurgulayıcı ve yazı girişini işler.
final class CanvasView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    var document: EditorDocument? {
        didSet { if oldValue !== document { needsDisplay = true } }
    }
    var settings: EditorSettings = .shared

    private var currentPoints: [CGPoint] = []
    private var textField: NSTextField?
    private var textDocument: EditorDocument?
    private var textColor: NSColor = .red
    private var textScale: CGFloat = 1
    private var textCancelled = false

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Geometry

    private var imageSize: CGSize {
        guard let img = document?.image else { return .zero }
        return CGSize(width: img.width, height: img.height)
    }

    /// Görüntünün view içindeki (aspect-fit) dikdörtgeni.
    private var imageRect: CGRect {
        let size = imageSize
        guard size.width > 0, size.height > 0 else { return .zero }
        let area = bounds
        let s = min(area.width / size.width, area.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    private var scale: CGFloat {
        let size = imageSize
        return size.width > 0 ? imageRect.width / size.width : 1
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let r = imageRect, s = scale
        return CGPoint(x: (p.x - r.minX) / s, y: (p.y - r.minY) / s)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let doc = document else { return }
        let r = imageRect

        // Saydam alanlar (lasso) için dama deseni.
        NSColor.white.setFill()
        r.fill()
        drawCheckerboard(in: r, ctx: ctx)

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high
        ctx.draw(doc.image, in: CGRect(origin: .zero, size: imageSize))
        for a in doc.annotations { AnnotationRenderer.draw(a, in: ctx) }
        if let live = liveStroke { AnnotationRenderer.draw(live, in: ctx) }
        ctx.restoreGState()
    }

    private func drawCheckerboard(in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: rect)
        NSColor(white: 0.88, alpha: 1).setFill()
        let tile: CGFloat = 8
        var y = rect.minY, row = 0
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : tile)
            while x < rect.maxX {
                CGRect(x: x, y: y, width: tile, height: tile).fill()
                x += tile * 2
            }
            y += tile
            row += 1
        }
        ctx.restoreGState()
    }

    private var liveStroke: Annotation? {
        guard !currentPoints.isEmpty else { return nil }
        let hl = settings.tool == .highlighter
        return Annotation(kind: .stroke(points: currentPoints, width: CGFloat(settings.size) / scale, highlighter: hl),
                          color: settings.nsColor)
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor = settings.tool == .text ? .iBeam : .crosshair
        addCursorRect(imageRect, cursor: cursor)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let hadText = textField != nil
        window?.makeFirstResponder(self) // aktif yazıyı tamamlar
        if hadText { commitText() }

        let p = convert(event.locationInWindow, from: nil)
        guard document != nil, imageRect.contains(p) else { return }

        switch settings.tool {
        case .pen, .highlighter:
            currentPoints = [toImage(p)]
            needsDisplay = true
        case .text:
            if !hadText { beginText(at: p) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !currentPoints.isEmpty else { return }
        let p = toImage(convert(event.locationInWindow, from: nil))
        if settings.tool == .highlighter && event.modifierFlags.contains(.shift) {
            // Shift: düz çizgi
            currentPoints = [currentPoints[0], p]
        } else {
            currentPoints.append(p)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let stroke = liveStroke else { return }
        currentPoints = []
        document?.add(stroke)
        needsDisplay = true
    }

    // MARK: - Text

    private func beginText(at p: CGPoint) {
        let field = NSTextField(string: "")
        field.font = .systemFont(ofSize: CGFloat(settings.size), weight: .semibold)
        field.textColor = settings.nsColor
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.placeholderString = L10n.t("Text…", "Yazı…")
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.sizeToFit()
        field.frame = CGRect(x: p.x - 2, y: p.y - field.frame.height / 2,
                             width: max(160, field.frame.width), height: field.frame.height)
        addSubview(field)
        window?.makeFirstResponder(field)

        textField = field
        textDocument = document
        textColor = settings.nsColor
        textScale = scale
        textCancelled = false
    }

    func commitText() {
        guard let field = textField else { return }
        textField = nil
        defer {
            field.removeFromSuperview()
            textDocument = nil
        }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textCancelled, !text.isEmpty, let doc = textDocument, let font = field.font else { return }

        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let viewOrigin = CGPoint(x: field.frame.minX + 2, y: field.frame.minY + (field.frame.height - lineHeight) / 2)
        let r = imageRect
        let origin = CGPoint(x: (viewOrigin.x - r.minX) / textScale, y: (viewOrigin.y - r.minY) / textScale)
        doc.add(Annotation(kind: .text(text, origin: origin, fontSize: font.pointSize / textScale), color: textColor))
        needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = textField else { return }
        let width = (field.attributedStringValue.size().width) + 24
        field.frame.size.width = max(160, width)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            textCancelled = true
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    // MARK: - Menu actions (⌘Z, ⇧⌘Z, ⌘C)

    @objc private func commitPendingTextNotification(_ note: Notification) {
        guard textField != nil else { return }
        window?.makeFirstResponder(self)
        commitText()
    }

    @objc func undo(_ sender: Any?) {
        document?.undo()
        needsDisplay = true
    }

    @objc func redo(_ sender: Any?) {
        document?.redo()
        needsDisplay = true
    }

    @objc func copy(_ sender: Any?) {
        guard let doc = document else { return }
        ImageIOHelper.copyToPasteboard(doc.rendered())
        onCopy?()
    }

    var onCopy: (() -> Void)?

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): document?.canUndo ?? false
        case #selector(redo(_:)): document?.canRedo ?? false
        case #selector(copy(_:)): document != nil
        default: true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // delete: son çizimi geri al
            undo(nil)
        default:
            super.keyDown(with: event)
        }
    }

    /// Araç çubuğundaki bir eylemden önce, yazılmakta olan metni görüntüye işler.
    static let commitPendingText = Notification.Name("ElvaCommitPendingText")

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: Self.commitPendingText, object: nil)
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(commitPendingTextNotification),
                                                   name: Self.commitPendingText, object: nil)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    @ObservedObject var settings: EditorSettings
    var onCopy: () -> Void

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.settings = settings
        view.document = document
        view.onCopy = onCopy
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        if view.document !== document {
            view.commitText()
            view.document = document
        }
        view.settings = settings
        if settings.tool != .text { view.commitText() }
        view.onCopy = onCopy
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}


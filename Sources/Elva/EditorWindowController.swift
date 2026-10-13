import AppKit
import SwiftUI

/// Çerçevesiz, saydam editör penceresi.
final class EditorWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape {
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performClose(_ sender: Any?) {
        // Çerçevesiz pencerede kapat düğmesi yok; ⌘W için kendimiz kapatıyoruz.
        if delegate?.windowShouldClose?(self) ?? true { close() }
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openControllers: Set<EditorWindowController> = []

    static let margin: CGFloat = 18      // gölge için kenar boşluğu
    static let toolbarHeight: CGFloat = 44
    static let gap: CGFloat = 10
    static let minWidth: CGFloat = 560   // araç çubuğu sığsın

    let model: EditorModel

    static func show(documents: [EditorDocument]) {
        let controller = EditorWindowController(documents: documents)
        openControllers.insert(controller)
        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(documents: [EditorDocument]) {
        model = EditorModel(documents: documents)

        let screen = NSScreen.underMouse ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let backing = screen?.backingScaleFactor ?? 2
        let chromeH = Self.margin * 2 + Self.gap + Self.toolbarHeight
        let maxBox = CGSize(width: visible.width * 0.85 - Self.margin * 2, height: visible.height * 0.88 - chromeH)

        // Tüm belgeleri kapsayan kutu
        model.backingScale = backing
        model.canvasBox = maxBox
        var box = CGSize(width: 1, height: 1)
        for doc in documents {
            let s = model.displaySize(for: doc)
            box.width = max(box.width, s.width)
            box.height = max(box.height, s.height)
        }
        model.canvasBox = box

        let width = max(box.width, Self.minWidth) + Self.margin * 2
        let height = box.height + chromeH

        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                  styleMask: [.borderless, .miniaturizable],
                                  backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed

        let hosting = NSHostingView(rootView: EditorView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting

        super.init(window: window)
        window.delegate = self
        model.window = window
        model.updateTitle()
        model.requestClose = { [weak window] in window?.performClose(nil) }
        window.onEscape = { [weak window] in window?.performClose(nil) }

        window.setFrameOrigin(NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2))
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: CanvasView.commitPendingText, object: nil)
        let modified = model.documents.filter(\.isModified).count
        guard modified > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = "Kaydedilmemiş çizimler var"
        alert.informativeText = modified == 1
            ? "Pencereyi kapatırsanız çizimler kaybolacak."
            : "\(modified) görüntüdeki çizimler kaybolacak."
        alert.addButton(withTitle: "Arşivle ve Kapat")
        alert.addButton(withTitle: "Vazgeç")
        alert.addButton(withTitle: "Kaydetmeden Kapat").hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.archiveAll()
            return true
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.remove(self)
    }
}

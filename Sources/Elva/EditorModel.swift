import AppKit
import SwiftUI

final class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()
    let createdAt: Date
    var archiveID: UUID?

    @Published private(set) var image: CGImage
    @Published private(set) var annotations: [Annotation] = []
    @Published private var redoStack: [Annotation] = []

    init(image: CGImage, archiveID: UUID? = nil, createdAt: Date = Date()) {
        self.image = image
        self.archiveID = archiveID
        self.createdAt = createdAt
    }

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isModified: Bool { !annotations.isEmpty }

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
        redoStack.removeAll()
    }

    func undo() {
        guard let last = annotations.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        annotations.append(next)
    }

    func clear() {
        redoStack.append(contentsOf: annotations.reversed())
        annotations.removeAll()
    }

    func rendered() -> CGImage {
        annotations.isEmpty ? image : AnnotationRenderer.render(base: image, annotations: annotations)
    }

    /// Çizimleri görüntüye kalıcı olarak işler (arşivleme sonrası).
    func bake(_ rendered: CGImage) {
        image = rendered
        annotations.removeAll()
        redoStack.removeAll()
    }
}

final class EditorSettings: ObservableObject {
    static let shared = EditorSettings()

    @Published var tool: EditorTool = .pen
    @Published private var colors: [EditorTool: Color] = [.pen: .red, .text: .red, .highlighter: .yellow]
    @Published private var sizes: [EditorTool: Double] = [.pen: 4, .text: 22, .highlighter: 18]

    var color: Color {
        get { colors[tool] ?? .red }
        set { colors[tool] = newValue }
    }

    var nsColor: NSColor { NSColor(color).usingColorSpace(.sRGB) ?? .red }

    /// Ekran noktası cinsinden kalınlık / yazı boyutu.
    var size: Double {
        get { sizes[tool] ?? 4 }
        set { sizes[tool] = newValue }
    }

    var sizeRange: ClosedRange<Double> {
        switch tool {
        case .pen: 1...24
        case .highlighter: 6...60
        case .text: 10...96
        }
    }

    var sizeLabel: String { tool == .text ? "Boyut" : "Kalınlık" }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var documents: [EditorDocument]
    @Published var index = 0 {
        didSet { updateTitle() }
    }
    @Published var toast: String?

    let settings = EditorSettings.shared
    weak var window: NSWindow?
    private var toastWork: DispatchWorkItem?

    init(documents: [EditorDocument]) {
        self.documents = documents
    }

    var current: EditorDocument { documents[index] }

    /// Yazı aracıyla girilmekte olan metni eylemden önce görüntüye işler.
    private func commitPendingText() {
        NotificationCenter.default.post(name: CanvasView.commitPendingText, object: nil)
    }
    var isBatch: Bool { documents.count > 1 }

    /// Görüntülerin sığması gereken kutu (nokta); pencere bu kutuya göre boyutlanır.
    var canvasBox: CGSize = CGSize(width: 600, height: 400)
    var backingScale: CGFloat = 2
    var requestClose: () -> Void = {}

    func updateTitle() {
        window?.title = AppInfo.name
    }

    /// Belgenin kutu içinde, 1:1 nokta boyutunu aşmadan gösterileceği boyut.
    func displaySize(for doc: EditorDocument) -> CGSize {
        let w = CGFloat(doc.image.width) / backingScale
        let h = CGFloat(doc.image.height) / backingScale
        let s = min(1, canvasBox.width / max(w, 1), canvasBox.height / max(h, 1))
        return CGSize(width: max(1, (w * s).rounded()), height: max(1, (h * s).rounded()))
    }

    func go(_ delta: Int) {
        commitPendingText()
        let next = index + delta
        guard documents.indices.contains(next) else { return }
        index = next
    }

    // MARK: - Actions

    func copyCurrent() {
        commitPendingText()
        ImageIOHelper.copyToPasteboard(current.rendered())
        showToast("Panoya kopyalandı")
    }

    func saveCurrent(as format: ImageFormat) {
        commitPendingText()
        let doc = current
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ImageIOHelper.fileBaseName(for: doc.createdAt) + "." + format.fileExtension
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ImageIOHelper.write(doc.rendered(), to: url, format: format)
                self?.showToast("\(format.title) olarak kaydedildi")
            } catch {
                self?.presentError(error)
            }
        }
    }

    func archiveCurrent() {
        commitPendingText()
        archive(current)
        showToast("Arşivlendi")
    }

    func archiveAll() {
        commitPendingText()
        documents.forEach(archive)
        showToast("\(documents.count) görüntü arşivlendi")
    }

    func saveAll(as format: ImageFormat) {
        commitPendingText()
        let docs = documents
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Buraya Kaydet"
        panel.message = "\(docs.count) görüntü \(format.title) olarak kaydedilecek"
        panel.begin { [weak self] response in
            guard response == .OK, let dir = panel.url else { return }
            do {
                let count = try BatchExporter.export(docs.map { ($0.createdAt, $0.rendered()) }, to: dir, format: format)
                self?.showToast("\(count) görüntü kaydedildi")
            } catch {
                self?.presentError(error)
            }
        }
    }

    private func archive(_ doc: EditorDocument) {
        let store = ArchiveStore.shared
        let image = doc.rendered()
        if let id = doc.archiveID, store.contains(id) {
            if doc.isModified { store.update(id, image: image) }
        } else {
            doc.archiveID = store.add(image)?.id
        }
        doc.bake(image)
    }

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.3)) { toast = text }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }
}

enum BatchExporter {
    /// Görüntüleri klasöre yazar, aynı isim varsa numara ekler. Yazılan dosya sayısını döner.
    static func export(_ images: [(Date, CGImage)], to directory: URL, format: ImageFormat) throws -> Int {
        let fm = FileManager.default
        var count = 0
        for (date, image) in images {
            let base = ImageIOHelper.fileBaseName(for: date)
            var url = directory.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
            var n = 2
            while fm.fileExists(atPath: url.path) {
                url = directory.appendingPathComponent("\(base) (\(n))").appendingPathExtension(format.fileExtension)
                n += 1
            }
            try ImageIOHelper.write(image, to: url, format: format)
            count += 1
        }
        return count
    }
}

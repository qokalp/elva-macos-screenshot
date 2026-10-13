import AppKit
import Foundation

struct ArchiveItem: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var modifiedAt: Date
    /// Grid'de şık görünüm için -10…+10 derece arası sabit eğim.
    let rotation: Double
}

@MainActor
final class ArchiveStore: ObservableObject {
    static let shared = ArchiveStore()

    @Published private(set) var items: [ArchiveItem] = []

    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private let thumbnailCache = NSCache<NSString, NSImage>()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Elva Screenshot/Archive", isDirectory: true)
        let fm = FileManager.default
        // Eski sürümün (GkScreenShot) arşivini taşı.
        let legacy = support.appendingPathComponent("GkScreenShot/Archive", isDirectory: true)
        if !fm.fileExists(atPath: directory.path), fm.fileExists(atPath: legacy.path) {
            try? fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: legacy, to: directory)
            try? fm.removeItem(at: legacy.deletingLastPathComponent())
        }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func fileURL(for item: ArchiveItem) -> URL { fileURL(for: item.id) }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    func contains(_ id: UUID) -> Bool { items.contains { $0.id == id } }

    @discardableResult
    func add(_ image: CGImage) -> ArchiveItem? {
        let now = Date()
        let item = ArchiveItem(id: UUID(), createdAt: now, modifiedAt: now, rotation: Double.random(in: -10...10))
        do {
            try ImageIOHelper.write(image, to: fileURL(for: item), format: .png)
        } catch {
            NSLog("Elva: arşive yazılamadı: \(error)")
            return nil
        }
        items.insert(item, at: 0)
        save()
        return item
    }

    func update(_ id: UUID, image: CGImage) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        do {
            try ImageIOHelper.write(image, to: fileURL(for: id), format: .png)
        } catch {
            NSLog("Elva: arşiv güncellenemedi: \(error)")
            return
        }
        items[idx].modifiedAt = Date()
        save()
    }

    func delete(_ ids: Set<UUID>) {
        for id in ids {
            try? FileManager.default.removeItem(at: fileURL(for: id))
        }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func cgImage(for item: ArchiveItem) -> CGImage? {
        ImageIOHelper.load(fileURL(for: item))
    }

    func thumbnail(for item: ArchiveItem) async -> NSImage? {
        let key = "\(item.id.uuidString)-\(item.modifiedAt.timeIntervalSince1970)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = fileURL(for: item)
        let cg = await Task.detached(priority: .userInitiated) {
            ImageIOHelper.thumbnail(url, maxPixelSize: 420)
        }.value
        guard let cg else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ArchiveItem].self, from: data) {
            items = decoded.filter { FileManager.default.fileExists(atPath: fileURL(for: $0.id).path) }
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Elva: arşiv dizini kaydedilemedi: \(error)")
        }
    }
}

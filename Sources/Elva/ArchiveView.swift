import AppKit
import ServiceManagement
import SwiftUI

struct ArchiveView: View {
    static let size = CGSize(width: 340, height: 440)

    @ObservedObject var store: ArchiveStore
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @AppStorage(CaptureDelay.key) private var delay = 0

    private let columns = Array(repeating: GridItem(.fixed(92), spacing: 14), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            captureBar
            Divider()
            archiveBar
            if store.items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onChange(of: store.items) { _, items in
            selection.formIntersection(items.map(\.id))
        }
    }

    // MARK: - Üst: yakalama butonları + gecikme

    private var captureBar: some View {
        HStack(spacing: 4) {
            CaptureButton(title: "Tam Ekran", symbol: "display") {
                AppCoordinator.shared.capture(.fullScreen)
            }
            CaptureButton(title: "Kare", symbol: "rectangle.dashed") {
                AppCoordinator.shared.capture(.rectangle)
            }
            CaptureButton(title: "Lasso", symbol: "lasso") {
                AppCoordinator.shared.capture(.lasso)
            }

            Divider().frame(height: 34).padding(.horizontal, 2)

            CaptureButton(title: delay == 0 ? "Gecikme" : "\(delay) sn", symbol: "timer",
                          tint: delay == 0 ? nil : .accentColor) {
                PopupMenu.show(CaptureDelay.options.map { sec in
                    let title = sec == 0 ? "Gecikme yok" : "\(sec) saniye"
                    return PopupMenu.Item((sec == delay ? "✓  " : "     ") + title) { delay = sec }
                })
            }
            .frame(width: 64)
            .help("Gecikmeli çekim")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Arşiv başlığı / seçim

    private var archiveBar: some View {
        HStack(spacing: 8) {
            if selecting {
                Text("\(selection.count) seçili")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Button(selection.count == store.items.count ? "Hiçbiri" : "Tümü") {
                    selection = selection.count == store.items.count ? [] : Set(store.items.map(\.id))
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                Spacer()
                Group {
                    BarIcon(symbol: "pencil.tip", help: "Düzenle") {
                        AppCoordinator.shared.openEditor(for: selectedItems)
                    }
                    Menu {
                        Button("PNG olarak kaydet…") { export(selectedItems, as: .png) }
                        Button("JPG olarak kaydet…") { export(selectedItems, as: .jpg) }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Kaydet")
                    BarIcon(symbol: "trash", help: "Sil") { delete(selection) }
                }
                .disabled(selection.isEmpty)
                Button("Bitti") {
                    selecting = false
                    selection = []
                }
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
                .keyboardShortcut(.cancelAction)
            } else {
                Text("Arşiv")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                BarIcon(symbol: "checkmark.circle", help: "Seç") { selecting = true }
                    .disabled(store.items.isEmpty)
                SettingsMenu(store: store)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(store.items) { item in
                    ThumbnailCell(
                        item: item,
                        store: store,
                        selecting: selecting,
                        isSelected: selection.contains(item.id)
                    ) {
                        if selecting {
                            toggle(item.id)
                        } else {
                            AppCoordinator.shared.openEditor(for: [item])
                        }
                    }
                    .contextMenu { contextMenu(for: item) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ArchiveItem) -> some View {
        Button("Düzenle") { AppCoordinator.shared.openEditor(for: [item]) }
        Button("Kopyala") {
            if let img = store.cgImage(for: item) { ImageIOHelper.copyToPasteboard(img) }
        }
        Button("PNG olarak kaydet…") { export([item], as: .png) }
        Button("JPG olarak kaydet…") { export([item], as: .jpg) }
        Button("Finder'da göster") {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: item)])
        }
        Divider()
        Button("Sil", role: .destructive) { delete([item.id]) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.stack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Arşiv boş")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private var selectedItems: [ArchiveItem] {
        store.items.filter { selection.contains($0.id) }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func export(_ items: [ArchiveItem], as format: ImageFormat) {
        guard !items.isEmpty else { return }
        AppCoordinator.shared.closePopover()
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Buraya Kaydet"
        panel.message = "\(items.count) görüntü \(format.title) olarak kaydedilecek"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let images = items.compactMap { item in store.cgImage(for: item).map { (item.createdAt, $0) } }
        do {
            _ = try BatchExporter.export(images, to: dir, format: format)
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = ids.count == 1 ? "Ekran görüntüsü silinsin mi?" : "\(ids.count) ekran görüntüsü silinsin mi?"
        alert.informativeText = "Bu işlem geri alınamaz."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sil").hasDestructiveAction = true
        alert.addButton(withTitle: "Vazgeç")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.delete(ids)
        selection.subtract(ids)
        if store.items.isEmpty { selecting = false }
    }
}

// MARK: - Components

private struct CaptureButton: View {
    let title: String
    let symbol: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(tint ?? .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.primary.opacity(hover ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct BarIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

private struct ThumbnailCell: View {
    let item: ArchiveItem
    let store: ArchiveStore
    let selecting: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hover = false
    @State private var image: NSImage?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 82, height: 56)
            .clipped()

            Text(Self.dateFormatter.string(from: item.createdAt))
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.4))
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 3)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 3))
        .overlay(alignment: .topTrailing) {
            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.9), isSelected ? Color.accentColor : Color.black.opacity(0.35))
                    .background(Circle().fill(isSelected ? Color.accentColor : Color.black.opacity(0.25)).padding(2))
                    .offset(x: 5, y: -5)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(selecting && isSelected ? 1 : 0)
        )
        .shadow(color: .black.opacity(hover ? 0.3 : 0.15), radius: hover ? 10 : 3, x: 0, y: hover ? 6 : 1)
        .rotationEffect(.degrees(hover ? 0 : item.rotation))
        .scaleEffect(hover ? 1.4 : (selecting && isSelected ? 0.94 : 1))
        .zIndex(hover ? 10 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.62), value: hover)
        .animation(.spring(response: 0.25), value: isSelected)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .onDrag {
            NSItemProvider(contentsOf: store.fileURL(for: item)) ?? NSItemProvider()
        }
        .help("Düzenlemek için tıklayın · Masaüstüne sürükleyebilirsiniz")
        .task(id: item.modifiedAt) {
            image = await store.thumbnail(for: item)
        }
    }
}

private struct SettingsMenu: View {
    let store: ArchiveStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Button("Arşiv klasörünü aç") {
                NSWorkspace.shared.open(store.directory)
            }
            Toggle("Oturum açılışında başlat", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSLog("Elva: giriş öğesi ayarlanamadı: \(error)")
                    }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
            Divider()
            Button("Elva'dan Çık") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

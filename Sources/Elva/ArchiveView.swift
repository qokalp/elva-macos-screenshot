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
            CaptureButton(title: L10n.t("Full Screen", "Tam Ekran"), symbol: "display") {
                AppCoordinator.shared.capture(.fullScreen)
            }
            CaptureButton(title: L10n.t("Rectangle", "Kare"), symbol: "rectangle.dashed") {
                AppCoordinator.shared.capture(.rectangle)
            }
            CaptureButton(title: "Lasso", symbol: "lasso") {
                AppCoordinator.shared.capture(.lasso)
            }

            Divider().frame(height: 34).padding(.horizontal, 2)

            CaptureButton(title: delay == 0 ? L10n.t("Timer", "Gecikme") : L10n.t("\(delay) s", "\(delay) sn"), symbol: "timer",
                          tint: delay == 0 ? nil : .accentColor) {
                PopupMenu.show(CaptureDelay.options.map { sec in
                    let title = sec == 0 ? L10n.t("No delay", "Gecikme yok") : L10n.t("\(sec) seconds", "\(sec) saniye")
                    return PopupMenu.Item((sec == delay ? "✓  " : "     ") + title) { delay = sec }
                })
            }
            .frame(width: 64)
            .help(L10n.t("Delayed capture", "Gecikmeli çekim"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Arşiv başlığı / seçim

    private var archiveBar: some View {
        HStack(spacing: 8) {
            if selecting {
                Text(L10n.t("\(selection.count) selected", "\(selection.count) seçili"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Button(selection.count == store.items.count ? L10n.t("None", "Hiçbiri") : L10n.t("All", "Tümü")) {
                    selection = selection.count == store.items.count ? [] : Set(store.items.map(\.id))
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                Spacer()
                Group {
                    BarIcon(symbol: "pencil.tip", help: L10n.t("Edit", "Düzenle")) {
                        AppCoordinator.shared.openEditor(for: selectedItems)
                    }
                    Menu {
                        Button(L10n.t("Save as PNG…", "PNG olarak kaydet…")) { export(selectedItems, as: .png) }
                        Button(L10n.t("Save as JPG…", "JPG olarak kaydet…")) { export(selectedItems, as: .jpg) }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L10n.t("Save", "Kaydet"))
                    BarIcon(symbol: "trash", help: L10n.t("Delete", "Sil")) { delete(selection) }
                }
                .disabled(selection.isEmpty)
                Button(L10n.t("Done", "Bitti")) {
                    selecting = false
                    selection = []
                }
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
                .keyboardShortcut(.cancelAction)
            } else {
                Text(L10n.t("Archive", "Arşiv"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                BarIcon(symbol: "checkmark.circle", help: L10n.t("Select", "Seç")) { selecting = true }
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
        Button(L10n.t("Edit", "Düzenle")) { AppCoordinator.shared.openEditor(for: [item]) }
        Button(L10n.t("Copy", "Kopyala")) {
            if let img = store.cgImage(for: item) { ImageIOHelper.copyToPasteboard(img) }
        }
        Button(L10n.t("Save as PNG…", "PNG olarak kaydet…")) { export([item], as: .png) }
        Button(L10n.t("Save as JPG…", "JPG olarak kaydet…")) { export([item], as: .jpg) }
        Button(L10n.t("Show in Finder", "Finder'da göster")) {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: item)])
        }
        Divider()
        Button(L10n.t("Delete", "Sil"), role: .destructive) { delete([item.id]) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.stack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.t("Archive is empty", "Arşiv boş"))
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
        panel.prompt = L10n.t("Save Here", "Buraya Kaydet")
        panel.message = L10n.t("\(items.count) images will be saved as \(format.title)", "\(items.count) görüntü \(format.title) olarak kaydedilecek")
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
        alert.messageText = ids.count == 1
            ? L10n.t("Delete this screenshot?", "Ekran görüntüsü silinsin mi?")
            : L10n.t("Delete \(ids.count) screenshots?", "\(ids.count) ekran görüntüsü silinsin mi?")
        alert.informativeText = L10n.t("This can't be undone.", "Bu işlem geri alınamaz.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("Delete", "Sil")).hasDestructiveAction = true
        alert.addButton(withTitle: L10n.t("Cancel", "Vazgeç"))
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
        f.locale = L10n.locale
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
        .help(L10n.t("Click to edit · Drag to your desktop", "Düzenlemek için tıklayın · Masaüstüne sürükleyebilirsiniz"))
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
            Button(L10n.t("Open Archive Folder", "Arşiv klasörünü aç")) {
                NSWorkspace.shared.open(store.directory)
            }
            Toggle(L10n.t("Open at Login", "Oturum açılışında başlat"), isOn: Binding(
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
            Button(L10n.t("Quit Elva", "Elva'dan Çık")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

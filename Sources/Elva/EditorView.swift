import AppKit
import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        EditorContent(model: model, settings: model.settings, doc: model.current)
    }
}

private struct EditorContent: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var settings: EditorSettings
    @ObservedObject var doc: EditorDocument

    var body: some View {
        let size = model.displaySize(for: doc)
        VStack(spacing: EditorWindowController.gap) {
            ZStack {
                CanvasRepresentable(document: doc, settings: settings) { model.showToast("Panoya kopyalandı") }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            }
            .frame(width: model.canvasBox.width, height: model.canvasBox.height)
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }

            EditorToolbar(model: model, settings: settings, doc: doc)
                .frame(height: EditorWindowController.toolbarHeight)
        }
        .padding(EditorWindowController.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - macOS ekran görüntüsü araç çubuğu tarzı alt bar

private struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var settings: EditorSettings
    @ObservedObject var doc: EditorDocument
    @State private var showStyle = false

    var body: some View {
        HStack(spacing: 2) {
            ToolbarIcon(symbol: "xmark", help: "Kapat (Esc)") { model.requestClose() }

            separator

            ForEach(EditorTool.allCases) { tool in
                ToolbarIcon(symbol: tool.symbol, help: tool.title, isActive: settings.tool == tool) {
                    settings.tool = tool
                }
            }

            Button { showStyle.toggle() } label: {
                Circle()
                    .fill(settings.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Renk ve \(settings.sizeLabel.lowercased())")
            .popover(isPresented: $showStyle, arrowEdge: .bottom) {
                StylePopover(settings: settings)
            }

            separator

            ToolbarIcon(symbol: "arrow.uturn.backward", help: "Geri al (⌘Z)") { doc.undo() }
                .disabled(!doc.canUndo)
            ToolbarIcon(symbol: "arrow.uturn.forward", help: "Yinele (⇧⌘Z)") { doc.redo() }
                .disabled(!doc.canRedo)

            if model.isBatch {
                separator
                ToolbarIcon(symbol: "chevron.left", help: "Önceki (⌘←)") { model.go(-1) }
                    .disabled(model.index == 0)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Text("\(model.index + 1)/\(model.documents.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minWidth: 30)
                ToolbarIcon(symbol: "chevron.right", help: "Sonraki (⌘→)") { model.go(1) }
                    .disabled(model.index == model.documents.count - 1)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }

            separator

            ToolbarIcon(symbol: "doc.on.doc", help: "Kopyala (⇧⌘C)") { model.copyCurrent() }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            ToolbarIcon(symbol: "square.and.arrow.down", help: "Kaydet (⌘S PNG · ⇧⌘S JPG)") {
                var items: [PopupMenu.Item] = [
                    .init("PNG olarak kaydet…") { model.saveCurrent(as: .png) },
                    .init("JPG olarak kaydet…") { model.saveCurrent(as: .jpg) },
                ]
                if model.isBatch {
                    items.append(.separator)
                    items.append(.init("Tümünü PNG olarak kaydet…") { model.saveAll(as: .png) })
                    items.append(.init("Tümünü JPG olarak kaydet…") { model.saveAll(as: .jpg) })
                }
                PopupMenu.show(items)
            }
            // Görünmez kısayol düğmeleri
            Group {
                Button("") { model.saveCurrent(as: .png) }.keyboardShortcut("s", modifiers: .command)
                Button("") { model.saveCurrent(as: .jpg) }.keyboardShortcut("s", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .opacity(0)

            ToolbarIcon(symbol: "archivebox", help: "Arşivle (⌘E)") { model.archiveCurrent() }
                .keyboardShortcut("e", modifiers: .command)
            if model.isBatch {
                ToolbarIcon(symbol: "archivebox.fill", help: "Tümünü arşivle") { model.archiveAll() }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: EditorWindowController.toolbarHeight)
        .background(
            ZStack {
                WindowDragArea()
                VisualEffectBlur()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
        .environment(\.colorScheme, .dark)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 5)
    }
}

private struct ToolbarIcon: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void

    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(isEnabled ? 0.85 : 0.3))
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Color.accentColor : Color.white.opacity(hover && isEnabled ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Fare konumunda yerel bir menü açar.
@MainActor
enum PopupMenu {
    struct Item {
        let title: String
        let action: (() -> Void)?

        init(_ title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }

        private init() {
            title = ""
            action = nil
        }

        static let separator = Item()
    }

    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func run() { action() }
    }

    static func show(_ items: [Item]) {
        let menu = NSMenu()
        var targets: [Target] = []
        for item in items {
            guard let action = item.action else {
                menu.addItem(.separator())
                continue
            }
            let target = Target(action)
            targets.append(target)
            let menuItem = NSMenuItem(title: item.title, action: #selector(Target.run), keyEquivalent: "")
            menuItem.target = target
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        withExtendedLifetime(targets) {}
    }
}

private struct StylePopover: View {
    @ObservedObject var settings: EditorSettings

    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { color in
                    Button { settings.color = color } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .padding(-3)
                                    .opacity(NSColor(settings.color).isClose(to: NSColor(color)) ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: $settings.color, supportsOpacity: false)
                    .labelsHidden()
            }
            HStack(spacing: 8) {
                Text(settings.sizeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: $settings.size, in: settings.sizeRange)
                    .controlSize(.small)
                Text("\(Int(settings.size))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: 270)
    }
}

/// Araç çubuğunun boş alanından pencereyi sürüklemeyi sağlar.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private extension NSColor {
    func isClose(to other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}

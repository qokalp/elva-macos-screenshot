import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: AppInfo.name)?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: ArchiveView.size.width, height: ArchiveView.size.height)
        popover.contentViewController = NSHostingController(rootView: ArchiveView(store: .shared))

        AppCoordinator.shared.closePopover = { [weak self] in
            self?.popover.performClose(nil)
        }

        registerHotKeys()
    }

    /// Finder'dan "Birlikte Aç" ya da Dock ikonuna sürüklenen görselleri editörde açar.
    func application(_ application: NSApplication, open urls: [URL]) {
        let docs = urls.compactMap { url in
            ImageIOHelper.load(url).map { EditorDocument(image: $0) }
        }
        guard !docs.isEmpty else { return }
        EditorWindowController.show(documents: docs)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func registerHotKeys() {
        let mods = controlKey | shiftKey
        HotKeyManager.shared.register(keyCode: kVK_ANSI_1, modifiers: mods) {
            AppCoordinator.shared.capture(.fullScreen)
        }
        HotKeyManager.shared.register(keyCode: kVK_ANSI_2, modifiers: mods) {
            AppCoordinator.shared.capture(.rectangle)
        }
        HotKeyManager.shared.register(keyCode: kVK_ANSI_3, modifiers: mods) {
            AppCoordinator.shared.capture(.lasso)
        }
    }
}

@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    var closePopover: () -> Void = {}

    func capture(_ mode: CaptureMode) {
        closePopover()
        CaptureManager.shared.start(mode)
    }

    func openEditor(with image: CGImage) {
        EditorWindowController.show(documents: [EditorDocument(image: image)])
    }

    func openEditor(for items: [ArchiveItem]) {
        let store = ArchiveStore.shared
        let docs = items.compactMap { item -> EditorDocument? in
            guard let image = store.cgImage(for: item) else { return nil }
            return EditorDocument(image: image, archiveID: item.id, createdAt: item.createdAt)
        }
        guard !docs.isEmpty else { return }
        closePopover()
        EditorWindowController.show(documents: docs)
    }
}

enum MainMenu {
    @MainActor
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Elva'dan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Pencere")
        windowMenu.addItem(withTitle: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Küçült", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

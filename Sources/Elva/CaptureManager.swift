import AppKit

enum CaptureMode {
    case fullScreen, rectangle, lasso
}

enum CaptureDelay {
    static let key = "captureDelay"
    static let options = [0, 3, 5, 10]
    static var current: Int { UserDefaults.standard.integer(forKey: key) }
}

@MainActor
final class CaptureManager {
    static let shared = CaptureManager()

    private var overlays: [SelectionWindow] = []
    private var keyMonitor: Any?
    private var isBusy = false

    func start(_ mode: CaptureMode) {
        guard !isBusy else { return }
        isBusy = true

        Task { @MainActor in
            // Popover kapanırken görüntüye girmesin.
            try? await Task.sleep(for: .milliseconds(150))
            let delay = CaptureDelay.current
            if delay > 0 {
                await CountdownHUD.run(seconds: delay)
            }
            do {
                let shots = try await ScreenCapturer.captureAllScreens()
                guard !shots.isEmpty else { throw CocoaError(.featureUnsupported) }
                switch mode {
                case .fullScreen:
                    let target = NSScreen.underMouse
                    let shot = shots.first { $0.screen == target } ?? shots[0]
                    finish(with: shot.image)
                case .rectangle, .lasso:
                    showOverlays(for: shots, mode: mode)
                }
            } catch {
                isBusy = false
                if CGPreflightScreenCaptureAccess() {
                    showError(error)
                } else {
                    showPermissionAlert()
                }
            }
        }
    }

    private func showOverlays(for shots: [ScreenShot], mode: CaptureMode) {
        NSApp.activate()
        overlays = shots.map { shot in
            SelectionWindow(screen: shot.screen, image: shot.image, mode: mode) { [weak self] image in
                self?.finish(with: image)
            }
        }
        let mouseScreen = NSScreen.underMouse
        for window in overlays {
            window.orderFrontRegardless()
        }
        (overlays.first { $0.screen == mouseScreen } ?? overlays.first)?.makeKey()
        NSCursor.crosshair.push()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.finish(with: nil)
                return nil
            }
            return event
        }
    }

    private func finish(with image: CGImage?) {
        if !overlays.isEmpty {
            NSCursor.pop()
        }
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isBusy = false

        guard let image else { return }
        playShutterSound()
        AppCoordinator.shared.openEditor(with: image)
    }

    private func showPermissionAlert() {
        // İlk seferde sistem izin penceresini tetikler.
        CGRequestScreenCaptureAccess()

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Ekran kaydı izni gerekli"
        alert.informativeText = "Sistem Ayarları › Gizlilik ve Güvenlik › Ekran ve Sistem Sesi Kaydı bölümünden \(AppInfo.name) uygulamasına izin verin. Listede zaten varsa kaldırıp yeniden ekleyin, ardından uygulamayı yeniden başlatın."
        alert.addButton(withTitle: "Sistem Ayarlarını Aç")
        alert.addButton(withTitle: "Vazgeç")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showError(_ error: Error) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Ekran görüntüsü alınamadı"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func playShutterSound() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: path) {
            NSSound(contentsOfFile: path, byReference: true)?.play()
        }
    }
}

/// Gecikmeli çekimde ekran ortasında küçük geri sayım göstergesi.
/// Uygulamanın kendi pencereleri çekimden hariç tutulduğu için görüntüye girmez.
@MainActor
enum CountdownHUD {
    static func run(seconds: Int) async {
        let size: CGFloat = 96
        let screen = NSScreen.underMouse ?? NSScreen.main
        let frame = screen?.frame ?? .zero
        let panel = NSPanel(contentRect: NSRect(x: frame.midX - size / 2, y: frame.midY - size / 2, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        label.textColor = .white
        label.alignment = .center

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        background.material = .hudWindow
        background.appearance = NSAppearance(named: .darkAqua)
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 22
        background.layer?.masksToBounds = true
        label.frame = NSRect(x: 0, y: (size - 54) / 2, width: size, height: 54)
        background.addSubview(label)
        panel.contentView = background
        panel.orderFrontRegardless()

        for remaining in stride(from: seconds, to: 0, by: -1) {
            label.stringValue = "\(remaining)"
            try? await Task.sleep(for: .seconds(1))
        }
        panel.orderOut(nil)
    }
}

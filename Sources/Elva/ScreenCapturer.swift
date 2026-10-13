import AppKit
import ScreenCaptureKit

struct ScreenShot {
    let screen: NSScreen
    let image: CGImage
}

enum ScreenCapturer {
    /// Bağlı tüm ekranların görüntüsünü alır (uygulamanın kendi pencereleri hariç).
    @MainActor
    static func captureAllScreens() async throws -> [ScreenShot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }

        var result: [ScreenShot] = []
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(ScreenShot(screen: screen, image: image))
        }
        return result
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static var underMouse: NSScreen? {
        let loc = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(loc, $0.frame, false) } ?? main
    }
}

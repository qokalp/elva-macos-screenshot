<p align="right"><b>English</b> · <a href="TECHNICAL.tr.md">Türkçe</a></p>

# Elva Screenshot Tool for macOS — Technical Documentation

This document is for anyone who wants to build the project from source, understand how it's put together, or work on it.

## Requirements

| | |
|---|---|
| macOS | 14 Sonoma or later |
| Xcode | 15 or later (for the Swift 5.10+ compiler; the command line tools are enough) |
| Dependencies | None — Apple frameworks only |

Frameworks used: **SwiftUI**, **AppKit**, **ScreenCaptureKit**, **ImageIO**, **Carbon (HIToolbox)**, **ServiceManagement**.

## Quick start

```bash
git clone https://github.com/qokalp/Elva-Screenshot.git
cd Elva-Screenshot

./build.sh            # build/Elva Screenshot Tool for macOS.app
./build.sh install    # copies it to /Applications and launches it
./build.sh dmg        # dist/Elva-Screenshot.dmg (disk image with drag-and-drop install)
```

To just compile during development:

```bash
swift build           # debug
swift build -c release
```

> The app is designed to run from inside an `.app` bundle (menu bar item, Info.plist, permissions). Use `./build.sh install` rather than running it directly with `swift run`.

To open the project in Xcode, just open `Package.swift`.

## Project structure

```
.
├── Package.swift                 Swift Package definition (single executable target: Elva)
├── build.sh                      .app bundle, install and DMG creation
├── Resources/
│   └── Info.plist                Bundle info (LSUIElement, permission description, document types)
├── Scripts/
│   ├── make_icon.swift           Draws the app icon (AppIcon.icns) in code
│   └── make_dmg_background.swift Draws the background image of the DMG window
├── Sources/Elva/
│   ├── main.swift                App entry point (accessory / menu bar mode)
│   ├── AppInfo.swift             App name constants
│   ├── AppDelegate.swift         Menu bar item, popover, global shortcuts, AppCoordinator, main menu
│   ├── HotKeyManager.swift       Global shortcuts via Carbon RegisterEventHotKey
│   ├── CaptureManager.swift      Capture flow, timer and countdown HUD, permission alert
│   ├── ScreenCapturer.swift      Captures all displays with ScreenCaptureKit
│   ├── SelectionOverlay.swift    Rectangle / lasso selection overlay and cropping
│   ├── ArchiveStore.swift        Archive: file system + index.json, thumbnail cache
│   ├── ArchiveView.swift         Menu bar popover UI (buttons, grid, batch actions)
│   ├── EditorWindowController.swift  Borderless editor window and sizing
│   ├── EditorView.swift          Editor UI and bottom toolbar
│   ├── EditorModel.swift         Document, settings and editor actions (copy, save, archive)
│   ├── CanvasView.swift          Drawing surface (AppKit NSView): pen, highlighter, text
│   ├── Annotation.swift          Annotation model and Core Graphics rendering
│   └── ImageIOHelper.swift       PNG/JPG encoding, loading, thumbnails, pasteboard
└── docs/
    ├── TECHNICAL.md              This document (English)
    ├── TECHNICAL.tr.md           Technical documentation (Turkish)
    └── images/                   README images
```

## Architecture

```
 Menu bar icon ──────► NSPopover (ArchiveView)
        │                     │  buttons / archive clicks
 Global shortcut ─────────────┤
 (HotKeyManager)              ▼
                        AppCoordinator ──► CaptureManager ──► ScreenCapturer (ScreenCaptureKit)
                              │                 │
                              │                 ├─ Full screen: image goes straight through
                              │                 └─ Rectangle / Lasso: SelectionWindow (frozen screen) → crop
                              ▼
                   EditorWindowController ──► EditorView + CanvasView
                              │
                              └─► ArchiveStore / NSSavePanel / NSPasteboard
```

### App lifecycle
- `LSUIElement = true` and `setActivationPolicy(.accessory)`: no Dock icon, only a menu bar item.
- An invisible main menu (`MainMenu.install`) is installed so that keyboard shortcuts (⌘Z, ⌘C, ⌘V…) work in text fields.
- Images opened from Finder via "Open With" arrive through `application(_:open:)` and open in the editor.

### Capturing
- `ScreenCapturer.captureAllScreens()` finds the matching `SCDisplay` for each `NSScreen` and captures it at full pixel resolution with `SCScreenshotManager.captureImage`. The app's own windows are excluded by the content filter, so the countdown HUD and the editor never show up in captures.
- **Full screen:** the image of the screen under the mouse goes straight to the editor.
- **Rectangle / Lasso:** a `SelectionWindow` opens on every screen, showing the frozen image dimmed, with the selected area lit up. Rectangles are cut out with `CGImage.cropping(to:)`; a lasso is drawn into a bitmap the size of the path's bounding box, masked by the path (the outside stays transparent).
- **Timer:** reads `captureDelay` (0/3/5/10) from `UserDefaults`; `CountdownHUD` shows a countdown in the middle of the screen.
- If a capture fails and `CGPreflightScreenCaptureAccess()` returns false, the permission alert is shown.

### Editor
- The window is borderless and transparent (`EditorWindow`); its content is the image with a thin border plus a HUD-style toolbar underneath.
- Window size is computed from a "canvas box" that fits every open image (`EditorModel.canvasBox`). Images are scaled to never exceed their 1:1 point size and to fit within ~85% of the screen.
- **Coordinates:** all annotations are stored in the image's **pixel space** (bottom-left origin). That way the exported image matches what's on screen, whatever the display scale. Stroke width and text size are converted to pixels by dividing by the scale at the moment of drawing.
- `AnnotationRenderer` uses the same code for drawing on screen and for exporting (`render(base:annotations:)`).
- The text tool places a temporary `NSTextField` at the clicked point; on Enter or loss of focus it's saved as an `Annotation.text`, and Esc cancels. Before any toolbar action (copy, save, archive, switching image or closing), text still being typed is committed via the `CanvasView.commitPendingText` notification.
- Undo / redo is kept as a stack per document (`EditorDocument`).
- **Archive:** annotations are flattened into the image (`bake`); if the image was opened from the archive, the same entry is updated, otherwise a new entry is added.

### Archive
- Location: `~/Library/Application Support/Elva Screenshot/Archive/`
- Each image is stored as `<UUID>.png`; metadata (created/modified time, tilt angle in the grid) lives in `index.json`.
- The tilt angle (-10°…+10°) is picked at random once, when the entry is created, so the grid looks the same every time it opens.
- Thumbnails are generated in the background with `CGImageSourceCreateThumbnailAtIndex` and kept in an `NSCache`.
- The archive from the old version (`GkScreenShot`) is moved to the new location automatically on first launch.

### Global shortcuts
Uses `RegisterEventHotKey`, which doesn't need Accessibility permission. The defaults are in `AppDelegate.registerHotKeys()`:

| Shortcut | Action |
|---|---|
| ⌃⇧1 | Full screen |
| ⌃⇧2 | Rectangle selection |
| ⌃⇧3 | Lasso |

Control+Shift was chosen to avoid clashing with macOS's own ⌘⇧3 / ⌘⇧4 shortcuts.

## Permissions

| Permission | Why | When it's requested |
|---|---|---|
| Screen & System Audio Recording | Taking screenshots with ScreenCaptureKit | By the system, on the first capture |

To reset the permission state (for testing):

```bash
tccutil reset ScreenCapture com.gkoseoglu.ElvaScreenshot
```

## Common changes

- **Changing shortcuts:** the `kVK_*` key codes and the `controlKey | shiftKey` modifiers in `AppDelegate.registerHotKeys()`. The app doesn't display the shortcuts anywhere; remember to update both README files (README.md, README.tr.md).
- **Timer options:** `CaptureDelay.options` (`CaptureManager.swift`).
- **Preset colors / thickness ranges:** `StylePopover.colors` (`EditorView.swift`) and `EditorSettings.sizeRange` (`EditorModel.swift`).
- **Grid appearance:** `ThumbnailCell` (`ArchiveView.swift`) — tilt, hover enlargement (`scaleEffect`), card sizes.
- **App icon:** `Scripts/make_icon.swift`, then `rm build/AppIcon.icns && ./build.sh`.
- **UI text:** the interface strings are currently hard-coded in Turkish in the SwiftUI/AppKit views.

## Publishing a release (GitHub)

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Build `dist/Elva-Screenshot.dmg` with `./build.sh dmg`.
3. Create a new **Release** on GitHub and attach `Elva-Screenshot.dmg`. As long as the file name stays the same, the
   `releases/latest/download/Elva-Screenshot.dmg` download link in the README always points to the latest version.

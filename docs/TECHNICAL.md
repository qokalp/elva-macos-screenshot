# Elva Screenshot Tool for macOS — Technical Documentation / Teknik Doküman

<p align="center">
  <a href="#english"><b>English</b></a> &nbsp;|&nbsp; <a href="#turkce"><b>Türkçe</b></a>
</p>

---

<a id="english"></a>

# English

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
git clone https://github.com/qokalp/elva-macos-screenshot.git
cd elva-macos-screenshot

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
│   ├── Info.plist                Bundle info (LSUIElement, permission description, document types, localizations)
│   ├── en.lproj/InfoPlist.strings  English permission text shown by macOS
│   └── tr.lproj/InfoPlist.strings  Turkish permission text shown by macOS
├── Scripts/
│   ├── make_icon.swift           Draws the app icon (AppIcon.icns) in code
│   └── make_dmg_background.swift Draws the background image of the DMG window
├── Sources/Elva/
│   ├── main.swift                App entry point (accessory / menu bar mode)
│   ├── AppInfo.swift             App name constants
│   ├── Localization.swift        English / Turkish UI text (L10n)
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
    ├── TECHNICAL.md              This document (English + Turkish)
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

### Localization
- The app is in **English and Turkish**. `L10n.isTurkish` checks the first preferred language of the system: if it starts with `tr` the UI is Turkish, otherwise English.
- Every user-facing string is written as `L10n.t("English", "Türkçe")` right where it's used, so both languages are always side by side in the code.
- Dates in the archive and default file names use `L10n.locale`.
- The permission text that macOS shows comes from `Resources/<lang>.lproj/InfoPlist.strings`; `build.sh` copies these into the bundle. `CFBundleLocalizations` in Info.plist lists `en` and `tr`, so system panels (save dialogs etc.) also follow the language.
- To try the other language without changing your Mac's language:

  ```bash
  open "/Applications/Elva Screenshot Tool for macOS.app" --args -AppleLanguages '(en)'   # or '(tr)'
  ```

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

- **Changing shortcuts:** the `kVK_*` key codes and the `controlKey | shiftKey` modifiers in `AppDelegate.registerHotKeys()`. The app doesn't display the shortcuts anywhere; remember to update both language sections of README.md.
- **Timer options:** `CaptureDelay.options` (`CaptureManager.swift`).
- **Preset colors / thickness ranges:** `StylePopover.colors` (`EditorView.swift`) and `EditorSettings.sizeRange` (`EditorModel.swift`).
- **Grid appearance:** `ThumbnailCell` (`ArchiveView.swift`) — tilt, hover enlargement (`scaleEffect`), card sizes.
- **App icon:** `Scripts/make_icon.swift`, then `rm build/AppIcon.icns && ./build.sh`.
- **UI text:** find the string and edit both sides of its `L10n.t("English", "Türkçe")` call. New strings should be written the same way.

## Publishing a release (GitHub)

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Build `dist/Elva-Screenshot.dmg` with `./build.sh dmg`.
3. Create a new **Release** on GitHub and attach `Elva-Screenshot.dmg`. As long as the file name stays the same, the
   `releases/latest/download/Elva-Screenshot.dmg` download link in the README always points to the latest version.

<p align="right"><a href="#turkce">Türkçe ↓</a></p>

---

<a id="turkce"></a>

# Türkçe

Bu doküman projeyi kaynak koddan derlemek, yapısını anlamak ve geliştirmek isteyenler içindir.

## Gereksinimler

| | |
|---|---|
| macOS | 14 Sonoma veya üstü |
| Xcode | 15 veya üstü (Swift 5.10+ derleyicisi için; komut satırı araçları yeterli) |
| Bağımlılıklar | Yok — yalnızca Apple framework'leri |

Kullanılan framework'ler: **SwiftUI**, **AppKit**, **ScreenCaptureKit**, **ImageIO**, **Carbon (HIToolbox)**, **ServiceManagement**.

## Hızlı başlangıç

```bash
git clone https://github.com/qokalp/elva-macos-screenshot.git
cd elva-macos-screenshot

./build.sh            # build/Elva Screenshot Tool for macOS.app
./build.sh install    # /Applications'a kopyalar ve başlatır
./build.sh dmg        # dist/Elva-Screenshot.dmg (sürükle-bırak kurulumlu disk görüntüsü)
```

Geliştirme sırasında yalnızca derlemek için:

```bash
swift build           # debug
swift build -c release
```

> Uygulama `.app` paketi içinde çalışmak üzere tasarlandı (menü çubuğu öğesi, Info.plist, izinler). `swift run` ile doğrudan çalıştırmak yerine `./build.sh install` kullanın.

Projeyi Xcode'da açmak için `Package.swift` dosyasını açmanız yeterli.

## Proje yapısı

```
.
├── Package.swift                 Swift Package tanımı (tek executable hedef: Elva)
├── build.sh                      .app paketi, kurulum ve DMG üretimi
├── Resources/
│   ├── Info.plist                Bundle bilgileri (LSUIElement, izin açıklaması, belge türleri, diller)
│   ├── en.lproj/InfoPlist.strings  macOS'un gösterdiği İngilizce izin metni
│   └── tr.lproj/InfoPlist.strings  macOS'un gösterdiği Türkçe izin metni
├── Scripts/
│   ├── make_icon.swift           Uygulama ikonunu (AppIcon.icns) kodla çizer
│   └── make_dmg_background.swift DMG penceresinin arka plan görselini çizer
├── Sources/Elva/
│   ├── main.swift                Uygulama girişi (accessory / menü çubuğu modu)
│   ├── AppInfo.swift             Uygulama adı sabitleri
│   ├── Localization.swift        İngilizce / Türkçe arayüz metinleri (L10n)
│   ├── AppDelegate.swift         Menü çubuğu öğesi, popover, global kısayollar, AppCoordinator, ana menü
│   ├── HotKeyManager.swift       Carbon RegisterEventHotKey ile global kısayollar
│   ├── CaptureManager.swift      Çekim akışı, gecikme ve geri sayım göstergesi, izin uyarısı
│   ├── ScreenCapturer.swift      ScreenCaptureKit ile tüm ekranları yakalama
│   ├── SelectionOverlay.swift    Kare / lasso seçim katmanı ve kırpma
│   ├── ArchiveStore.swift        Arşiv: dosya sistemi + index.json, küçük resim önbelleği
│   ├── ArchiveView.swift         Menü çubuğu popover arayüzü (butonlar, grid, toplu işlemler)
│   ├── EditorWindowController.swift  Çerçevesiz editör penceresi ve boyutlandırma
│   ├── EditorView.swift          Editör arayüzü ve alt araç çubuğu
│   ├── EditorModel.swift         Belge, ayarlar ve editör eylemleri (kopyala, kaydet, arşivle)
│   ├── CanvasView.swift          Çizim yüzeyi (AppKit NSView): kalem, vurgulayıcı, yazı
│   ├── Annotation.swift          Çizim modeli ve Core Graphics ile render
│   └── ImageIOHelper.swift       PNG/JPG kodlama, yükleme, küçük resim, pano
└── docs/
    ├── TECHNICAL.md              Bu doküman (İngilizce + Türkçe)
    └── images/                   README görselleri
```

## Mimari

```
 Menü çubuğu ikonu ──► NSPopover (ArchiveView)
        │                     │  butonlar / arşiv tıklaması
 Global kısayol ──────────────┤
 (HotKeyManager)              ▼
                        AppCoordinator ──► CaptureManager ──► ScreenCapturer (ScreenCaptureKit)
                              │                 │
                              │                 ├─ Tam ekran: doğrudan görüntü
                              │                 └─ Kare / Lasso: SelectionWindow (donmuş ekran) → kırpma
                              ▼
                   EditorWindowController ──► EditorView + CanvasView
                              │
                              └─► ArchiveStore / NSSavePanel / NSPasteboard
```

### Uygulama yaşam döngüsü
- `LSUIElement = true` ve `setActivationPolicy(.accessory)`: Dock ikonu yok, yalnızca menü çubuğu öğesi.
- Klavye kısayollarının (⌘Z, ⌘C, ⌘V…) metin alanlarında çalışması için görünmeyen bir ana menü (`MainMenu.install`) kurulur.
- Finder'dan "Birlikte Aç" ile gelen görseller `application(_:open:)` üzerinden editörde açılır.

### Dil desteği
- Uygulama **İngilizce ve Türkçe**dir. `L10n.isTurkish` sistemin ilk tercih edilen diline bakar: `tr` ile başlıyorsa arayüz Türkçe, değilse İngilizce olur.
- Kullanıcının gördüğü her metin, kullanıldığı yerde `L10n.t("English", "Türkçe")` şeklinde yazılıdır; böylece iki dil kodda hep yan yana durur.
- Arşivdeki tarihler ve varsayılan dosya adları `L10n.locale` kullanır.
- macOS'un gösterdiği izin metni `Resources/<dil>.lproj/InfoPlist.strings` dosyalarından gelir; `build.sh` bunları pakete kopyalar. Info.plist'teki `CFBundleLocalizations` `en` ve `tr` içerdiği için sistem pencereleri (kaydetme penceresi vb.) de dile uyar.
- Mac'inizin dilini değiştirmeden diğer dili denemek için:

  ```bash
  open "/Applications/Elva Screenshot Tool for macOS.app" --args -AppleLanguages '(en)'   # ya da '(tr)'
  ```

### Çekim
- `ScreenCapturer.captureAllScreens()` her `NSScreen` için eşleşen `SCDisplay`'i bulur ve `SCScreenshotManager.captureImage` ile ekranın tam piksel çözünürlüğünde görüntü alır. Uygulamanın kendi pencereleri filtreyle hariç tutulur (geri sayım göstergesi ve editör görüntüye girmez).
- **Tam ekran:** farenin bulunduğu ekranın görüntüsü doğrudan editöre gider.
- **Kare / Lasso:** her ekran için bir `SelectionWindow` açılır; donmuş görüntü karartılarak gösterilir, seçili alan aydınlatılır. Kare seçim `CGImage.cropping(to:)` ile kesilir; lasso, yolun sınır kutusu boyutunda bir bitmap'e yola göre maskelenerek çizilir (dışı saydam kalır).
- **Gecikme:** `UserDefaults` içindeki `captureDelay` (0/3/5/10) okunur, `CountdownHUD` ekran ortasında geri sayım gösterir.
- Çekim hata verirse ve `CGPreflightScreenCaptureAccess()` false dönerse izin uyarısı gösterilir.

### Editör
- Pencere çerçevesiz ve saydamdır (`EditorWindow`); içerik: ince kenarlı görüntü + altta HUD tarzı araç çubuğu.
- Pencere boyutu, açılan tüm görüntüleri kapsayan bir "tuval kutusu"na göre hesaplanır (`EditorModel.canvasBox`). Görüntüler 1:1 nokta boyutunu aşmayacak, ekranın ~%85'ine sığacak şekilde ölçeklenir.
- **Koordinatlar:** tüm çizimler görüntünün **piksel uzayında** (sol-alt orijin) saklanır. Böylece ekran ölçeği ne olursa olsun dışa aktarılan görüntü ekrandakiyle aynıdır. Kalınlık ve yazı boyutu, çizim anındaki ölçeğe bölünerek piksel cinsine çevrilir.
- `AnnotationRenderer` hem ekrana çizimde hem de dışa aktarmada aynı kodu kullanır (`render(base:annotations:)`).
- Yazı aracı, tıklanan noktaya geçici bir `NSTextField` yerleştirir; Enter / odak kaybında `Annotation.text` olarak kaydedilir, Esc iptal eder. Araç çubuğundaki herhangi bir eylemden (kopyala, kaydet, arşivle, görsel değiştirme, kapatma) önce yazılmakta olan metin `CanvasView.commitPendingText` bildirimiyle görüntüye işlenir.
- Geri al / yinele belge başına bir yığınla tutulur (`EditorDocument`).
- **Arşivle:** çizimler görüntüye işlenir (`bake`), arşivden açılmış bir görüntüyse aynı kayıt güncellenir, değilse yeni kayıt eklenir.

### Arşiv
- Konum: `~/Library/Application Support/Elva Screenshot/Archive/`
- Her görüntü `<UUID>.png` olarak saklanır; meta veriler (oluşturma/değişiklik zamanı, grid'deki eğim açısı) `index.json` içindedir.
- Eğim açısı (-10°…+10°) kayıt oluşturulurken bir kez rastgele seçilir, böylece grid her açılışta aynı görünür.
- Küçük resimler `CGImageSourceCreateThumbnailAtIndex` ile arka planda üretilir ve `NSCache`'te tutulur.
- Eski sürümün (`GkScreenShot`) arşivi ilk açılışta otomatik olarak yeni konuma taşınır.

### Global kısayollar
`RegisterEventHotKey` kullanılır; Erişilebilirlik izni gerektirmez. Varsayılanlar `AppDelegate.registerHotKeys()` içindedir:

| Kısayol | İşlem |
|---|---|
| ⌃⇧1 | Tam ekran |
| ⌃⇧2 | Kare seçim |
| ⌃⇧3 | Lasso |

macOS'un kendi ⌘⇧3 / ⌘⇧4 kısayollarıyla çakışmamak için Control+Shift tercih edildi.

## İzinler

| İzin | Neden | Nerede istenir |
|---|---|---|
| Ekran ve Sistem Sesi Kaydı | ScreenCaptureKit ile ekran görüntüsü almak | İlk çekimde sistem tarafından |

İzin durumunu sıfırlamak için (test amaçlı):

```bash
tccutil reset ScreenCapture com.gkoseoglu.ElvaScreenshot
```

## Sık yapılan değişiklikler

- **Kısayolları değiştirmek:** `AppDelegate.registerHotKeys()` içindeki `kVK_*` tuş kodları ve `controlKey | shiftKey` değiştiricileri. Uygulama kısayolları hiçbir yerde göstermez; README.md'nin iki dil bölümünü de güncellemeyi unutmayın.
- **Gecikme seçenekleri:** `CaptureDelay.options` (`CaptureManager.swift`).
- **Hazır renkler / kalınlık aralıkları:** `StylePopover.colors` (`EditorView.swift`) ve `EditorSettings.sizeRange` (`EditorModel.swift`).
- **Grid görünümü:** `ThumbnailCell` (`ArchiveView.swift`) — eğim, hover büyütmesi (`scaleEffect`), kart boyutları.
- **Uygulama ikonu:** `Scripts/make_icon.swift`, ardından `rm build/AppIcon.icns && ./build.sh`.
- **Arayüz metinleri:** metni bulup `L10n.t("English", "Türkçe")` çağrısının iki tarafını da düzenleyin. Yeni metinler de aynı şekilde yazılmalı.

## Sürüm yayınlama (GitHub)

1. `Resources/Info.plist` içinde `CFBundleShortVersionString` ve `CFBundleVersion` değerlerini artırın.
2. `./build.sh dmg` ile `dist/Elva-Screenshot.dmg` üretin.
3. GitHub'da yeni bir **Release** oluşturup `Elva-Screenshot.dmg` dosyasını ekleyin. Dosya adı aynı kaldıkça README'deki
   `releases/latest/download/Elva-Screenshot.dmg` indirme bağlantısı her zaman son sürümü gösterir.

<p align="right"><a href="#english">English ↑</a></p>

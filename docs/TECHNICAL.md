# Elva Screenshot Tool for MacOS — Teknik Doküman

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
git clone https://github.com/qokalp/Elva-Screenshot.git
cd Elva-Screenshot

./build.sh            # build/Elva Screenshot Tool for MacOS.app
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
│   └── Info.plist                Bundle bilgileri (LSUIElement, izin açıklaması, belge türleri)
├── Scripts/
│   ├── make_icon.swift           Uygulama ikonunu (AppIcon.icns) kodla çizer
│   └── make_dmg_background.swift DMG penceresinin arka plan görselini çizer
├── Sources/Elva/
│   ├── main.swift                Uygulama girişi (accessory / menü çubuğu modu)
│   ├── AppInfo.swift             Uygulama adı sabitleri
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
    ├── TECHNICAL.md              Bu doküman
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
- Yazı aracı, tıklanan noktaya geçici bir `NSTextField` yerleştirir; Enter / odak kaybında `Annotation.text` olarak kaydedilir, Esc iptal eder.
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

- **Kısayolları değiştirmek:** `AppDelegate.registerHotKeys()` içindeki `kVK_*` tuş kodları ve `controlKey | shiftKey` değiştiricileri. Popover alt bilgisindeki metinler yoktur; README'yi güncellemeyi unutmayın.
- **Gecikme seçenekleri:** `CaptureDelay.options` (`CaptureManager.swift`).
- **Hazır renkler / kalınlık aralıkları:** `StylePopover.colors` (`EditorView.swift`) ve `EditorSettings.sizeRange` (`EditorModel.swift`).
- **Grid görünümü:** `ThumbnailCell` (`ArchiveView.swift`) — eğim, hover büyütmesi (`scaleEffect`), kart boyutları.
- **Uygulama ikonu:** `Scripts/make_icon.swift`, ardından `rm build/AppIcon.icns && ./build.sh`.

## Sürüm yayınlama (GitHub)

1. `Resources/Info.plist` içinde `CFBundleShortVersionString` ve `CFBundleVersion` değerlerini artırın.
2. `./build.sh dmg` ile `dist/Elva-Screenshot.dmg` üretin.
3. GitHub'da yeni bir **Release** oluşturup `Elva-Screenshot.dmg` dosyasını ekleyin. Dosya adı aynı kaldıkça README'deki
   `releases/latest/download/Elva-Screenshot.dmg` indirme bağlantısı her zaman son sürümü gösterir.

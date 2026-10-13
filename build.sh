#!/bin/bash
# Elva Screenshot Tool for macOS — derleme ve paketleme
#
#   ./build.sh            → build/Elva Screenshot Tool for macOS.app
#   ./build.sh install    → ayrıca /Applications'a kurar ve başlatır
#   ./build.sh dmg        → ayrıca dist/Elva-Screenshot.dmg (sürükle-bırak kurulum) üretir
#   ./build.sh release    → dmg + Apple noter onayı (notarization) ve stapling
#                           NOTARY_PROFILE (varsayılan: elva-notary) adlı notarytool profili gerekir
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Elva Screenshot Tool for macOS"
EXECUTABLE="Elva"
BUNDLE_ID="com.gkoseoglu.ElvaScreenshot"
VOLUME_NAME="Elva Screenshot"
DMG_NAME="Elva-Screenshot.dmg"
APP="build/$APP_NAME.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-elva-notary}"
MODE="${1:-}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "▸ Derleniyor (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▸ Uygulama paketi hazırlanıyor…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

if [ ! -f build/AppIcon.icns ]; then
    echo "▸ İkon üretiliyor…"
    swift Scripts/make_icon.swift build >/dev/null
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
    rm -rf build/AppIcon.iconset
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 '"Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)}"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 '"Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)}"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "▸ İmzalanıyor: $SIGN_IDENTITY"
    # Noter onayı güvenli zaman damgası ister; günlük derlemelerde ağ gerektirmesin diye yalnızca release'te.
    TIMESTAMP_FLAG="--timestamp=none"
    [ "$MODE" = "release" ] && TIMESTAMP_FLAG="--timestamp"
    codesign --force --options runtime $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    echo "▸ İmzalanıyor (ad-hoc)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

# build/ kopyası Launchpad/Spotlight'ta ikinci bir uygulama gibi görünmesin.
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true

echo "✓ Hazır: $APP"

notarize() {
    # $1: gönderilecek dosya (.zip ya da .dmg)
    echo "▸ Noter onayına gönderiliyor: $(basename "$1") (birkaç dakika sürebilir)…"
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [ "$MODE" = "release" ]; then
    case "$SIGN_IDENTITY" in
        "Developer ID Application"*) ;;
        *) echo "✗ Noter onayı için Developer ID Application sertifikası gerekli"; exit 1 ;;
    esac
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
        echo "✗ '$NOTARY_PROFILE' notarytool profili bulunamadı."
        echo "  Oluşturmak için: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id <team-id>"
        exit 1
    }
    ZIP="build/$EXECUTABLE-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    rm -f "$ZIP"
    xcrun stapler staple "$APP"
fi

case "$MODE" in
install)
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "✓ /Applications/$APP_NAME.app kuruldu ve başlatıldı"
    ;;
dmg|release)
    echo "▸ DMG hazırlanıyor…"
    STAGE="build/dmg-stage"
    RW="build/dmg-rw.dmg"
    rm -rf "$STAGE" "$RW"
    mkdir -p "$STAGE/.background" dist
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    swift Scripts/make_dmg_background.swift "$STAGE/.background"
    tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
        -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
    rm "$STAGE/.background/"*.png

    # Aynı isimde bağlı bir disk varsa ayır.
    [ -d "/Volumes/$VOLUME_NAME" ] && hdiutil detach "/Volumes/$VOLUME_NAME" -force >/dev/null || true

    # Spotlight vb. klasörü o an tutuyorsa "kaynak meşgul" hatası verebilir; birkaç kez dene.
    for attempt in 1 2 3 4 5; do
        hdiutil create -srcfolder "$STAGE" -volname "$VOLUME_NAME" -fs HFS+ -format UDRW -ov "$RW" >/dev/null && break
        [ "$attempt" = 5 ] && { echo "✗ DMG oluşturulamadı"; exit 1; }
        sleep 3
    done
    MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -o '/Volumes/.*$')"

    # Finder penceresi düzeni: arka plan, ikon boyutu, konumlar.
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {200, 120, 860, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {165, 200}
        set position of item "Applications" of container window to {495, 200}
        update without registering applications
        delay 2
        close
        -- Ayarların .DS_Store'a yazılması için bir kez daha aç/kapat
        open
        set the bounds of container window to {200, 120, 860, 548}
        delay 2
        close
    end tell
end tell
APPLESCRIPT

    # .DS_Store yazılana kadar bekle
    for _ in $(seq 1 20); do [ -f "$MOUNT_DIR/.DS_Store" ] && break; sleep 0.5; done
    sleep 1
    cp build/AppIcon.icns "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
    chmod -Rf go-w "$MOUNT_DIR" || true
    sync
    hdiutil detach "$MOUNT_DIR" >/dev/null
    rm -f "dist/$DMG_NAME"
    hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "dist/$DMG_NAME" >/dev/null
    rm -rf "$RW" "$STAGE"
    if [ -n "$SIGN_IDENTITY" ]; then
        codesign --force $TIMESTAMP_FLAG --sign "$SIGN_IDENTITY" "dist/$DMG_NAME"
    fi
    if [ "$MODE" = "release" ]; then
        notarize "dist/$DMG_NAME"
        xcrun stapler staple "dist/$DMG_NAME"
        spctl -a -t open --context context:primary-signature -v "dist/$DMG_NAME"
    fi
    echo "✓ DMG: dist/$DMG_NAME"
    ;;
esac

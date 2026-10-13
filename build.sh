#!/bin/bash
# Elva Screenshot Tool for macOS — derleme ve paketleme
#
#   ./build.sh            → build/Elva Screenshot Tool for macOS.app
#   ./build.sh install    → ayrıca /Applications'a kurar ve başlatır
#   ./build.sh dmg        → ayrıca dist/Elva-Screenshot.dmg (sürükle-bırak kurulum) üretir
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Elva Screenshot Tool for macOS"
EXECUTABLE="Elva"
BUNDLE_ID="com.gkoseoglu.ElvaScreenshot"
VOLUME_NAME="Elva Screenshot"
DMG_NAME="Elva-Screenshot.dmg"
APP="build/$APP_NAME.app"
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
    codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    echo "▸ İmzalanıyor (ad-hoc)"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

# build/ kopyası Launchpad/Spotlight'ta ikinci bir uygulama gibi görünmesin.
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true

echo "✓ Hazır: $APP"

case "${1:-}" in
install)
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "✓ /Applications/$APP_NAME.app kuruldu ve başlatıldı"
    ;;
dmg)
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

    hdiutil create -srcfolder "$STAGE" -volname "$VOLUME_NAME" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
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
        codesign --force --sign "$SIGN_IDENTITY" "dist/$DMG_NAME"
    fi
    echo "✓ DMG: dist/$DMG_NAME"
    ;;
esac

#!/bin/bash
#
# GMS Commander — Komut satırından çalıştırılabilir .app paketi üretir.
#
# Xcode kurulu olmayan makinelerde (yalnızca Command Line Tools) uygulamayı
# derlemek ve paketlemek için kullanılır. Xcode kurulu bir makinede
# `xcodebuild -project GMS_Commander.xcodeproj -scheme GMS_Commander` tercih edilir.
#
# Kullanım:
#   ./Scripts/build.sh            # Derle ve build/GMS Commander.app üret
#   ./Scripts/build.sh --clean    # Önce temizle, sonra derle
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="GMS Commander"
BUNDLE_ID="com.gms.commander"
VERSION="1.0.0"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SOURCE_DIR="$ROOT_DIR/GMS_Commander"
ASSETS_DIR="$SOURCE_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
DEPLOYMENT_TARGET="14.0"

if [[ "${1:-}" == "--clean" ]]; then
    rm -rf "$BUILD_DIR"
fi

echo "==> GMS Commander $VERSION derleniyor"

SDK_PATH="$(xcrun --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"

if [[ ! -d "$SDK_PATH" ]]; then
    echo "Hata: macOS SDK bulunamadı. Xcode veya Command Line Tools kurulu olmalı." >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# --- 1. Swift kaynaklarını derle -------------------------------------------------

SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$SOURCE_DIR" -name '*.swift' -not -path '*/.build/*' | sort)

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "Hata: Derlenecek Swift dosyası bulunamadı." >&2
    exit 1
fi

echo "    ${#SOURCES[@]} Swift dosyası derleniyor ($(sw_vers -productVersion) SDK: $(basename "$SDK_PATH"))"

"$SWIFTC" \
    -target "arm64-apple-macos$DEPLOYMENT_TARGET" \
    -sdk "$SDK_PATH" \
    -swift-version 5 \
    -O \
    -whole-module-optimization \
    -o "$MACOS_DIR/$APP_NAME" \
    "${SOURCES[@]}"

# --- 2. Bilgi listesi ve paket dosyaları ----------------------------------------

PLIST="$CONTENTS_DIR/Info.plist"
cp "$SOURCE_DIR/Resources/Info.plist" "$PLIST"

# Info.plist içindeki $(...) değişkenlerini gerçek değerlerle doldur.
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon.icns" "$PLIST"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# --- 3. Yerelleştirme -----------------------------------------------------------

cp -R "$SOURCE_DIR/Resources/tr.lproj" "$RESOURCES_DIR/"

# --- 4. Simge (.icns) ------------------------------------------------------------

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

copy_icon() { # <kaynak dosya> <hedef ad>
    cp "$ASSETS_DIR/$1" "$ICONSET/$2"
}

copy_icon "icon_16x16.png" "icon_16x16.png"
copy_icon "icon_32x32.png" "icon_16x16@2x.png"
copy_icon "icon_32x32.png" "icon_32x32.png"
copy_icon "icon_128x128.png" "icon_128x128.png"
copy_icon "icon_256x256.png" "icon_128x128@2x.png"
copy_icon "icon_256x256.png" "icon_256x256.png"
copy_icon "icon_512x512.png" "icon_256x256@2x.png"
copy_icon "icon_512x512.png" "icon_512x512.png"
copy_icon "icon_512x512@2x.png" "icon_512x512@2x.png"

# 32x32@2x (64 px) doğrudan üretilmediği için 128 px dosyadan ölçeklenir.
sips -z 64 64 "$ASSETS_DIR/icon_128x128.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET"

# --- 5. İmzalama (ad-hoc) -------------------------------------------------------

codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null 2>&1 || {
    echo "Uyarı: Ad-hoc imzalama başarısız oldu; uygulama yine de çalışabilir." >&2
}

echo "==> Paket hazır: $APP_BUNDLE"
codesign -dv "$APP_BUNDLE" 2>&1 | sed -n '1,3p' || true
echo "    Boyut: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo
echo "Çalıştırmak için:  open \"$APP_BUNDLE\""

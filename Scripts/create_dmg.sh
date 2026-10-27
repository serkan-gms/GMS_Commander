#!/bin/bash
#
# GMS Commander — Kurulabilir DMG disk imajı üretir.
#
# Önce ./Scripts/build.sh ile uygulama paketini üretir, ardından
# /Applications kısayolu içeren sürüklenebilir bir DMG oluşturur.
#
# Kullanım:
#   ./Scripts/create_dmg.sh
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="GMS Commander"
VERSION="1.0.0"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
STAGING_DIR="$BUILD_DIR/dmg-staging"
VOLUME_NAME="$APP_NAME"
DMG_NAME="GMS_Commander_v${VERSION}_mac_arm64.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "==> Uygulama paketi bulunamadı, önce derleniyor"
    "$ROOT_DIR/Scripts/build.sh"
fi

echo "==> DMG hazırlanıyor: $DMG_NAME"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Disk imajındaki dosyaların imzası korunmalı; kopyalama sırasında
# genişletilmiş öznitelikler korunur (cp -R -p yerine ditto kullanılır).
rm -rf "$STAGING_DIR/$APP_NAME.app"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> Doğrulama"
hdiutil verify "$DMG_PATH" | tail -2

echo
echo "==> DMG hazır: $DMG_PATH"
echo "    Boyut: $(du -sh "$DMG_PATH" | cut -f1)"
echo
echo "Kurmak için DMG'yi açıp \"$APP_NAME\" uygulamasını Applications klasörüne sürükleyin."

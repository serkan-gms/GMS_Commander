#!/bin/bash
#
# GMS Commander — Derleme çıktılarını ve geçici dosyaları temizler.
#
# Kullanım:
#   ./Scripts/clean.sh
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Temizlik başlıyor"

rm -rf "$ROOT_DIR/build"
rm -rf "$ROOT_DIR/DerivedData"
rm -rf "$ROOT_DIR/.build"

# Xcode'un proje bazlı geçici dosyaları
find "$ROOT_DIR" -name '.DS_Store' -delete 2>/dev/null || true
find "$ROOT_DIR" -name '*.xcuserdatad' -type d -prune -exec rm -rf {} + 2>/dev/null || true
rm -rf "$ROOT_DIR/GMS_Commander.xcodeproj/project.xcworkspace/xcuserdata" 2>/dev/null || true

echo "==> Temizlik tamamlandı"

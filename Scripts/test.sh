#!/bin/bash
#
# GMS Commander — Bağımsız test koşucusunu derler ve çalıştırır.
#
# XCTest yalnızca Xcode ile birlikte geldiği için, yalnızca Command Line Tools
# kurulu makinelerde testler bu koşucu ile çalıştırılır. Aynı senaryolar
# Tests/GMSCommanderTests altında XCTest olarak da bulunur.
#
# Kullanım:
#   ./Scripts/test.sh
#   ./Scripts/test.sh --xcode     # Xcode kuruluysa gerçek XCTest çalıştırır
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="$ROOT_DIR/build"
BINARY="$BUILD_DIR/standalone-tests"
SDK_PATH="$(xcrun --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"

if [[ "${1:-}" == "--xcode" ]]; then
    if ! xcodebuild -version >/dev/null 2>&1; then
        echo "Hata: xcodebuild bulunamadı. Bu makinede XCTest çalıştırılamaz." >&2
        echo "Xcode kurduktan sonra tekrar deneyin veya ./Scripts/test.sh kullanın." >&2
        exit 1
    fi
    xcodebuild test \
        -project GMS_Commander.xcodeproj \
        -scheme GMS_Commander \
        -destination 'platform=macOS,arch=arm64' \
        CODE_SIGNING_ALLOWED=NO
    exit $?
fi

mkdir -p "$BUILD_DIR"

echo "==> Bağımsız testler derleniyor"
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find GMS_Commander -name '*.swift' \
    -not -name 'GMS_CommanderApp.swift' \
    -not -path '*/.build/*' | sort)

"$SWIFTC" \
    -target arm64-apple-macos14.0 \
    -sdk "$SDK_PATH" \
    -swift-version 5 \
    -o "$BINARY" \
    "${SOURCES[@]}" \
    Tests/StandaloneTests/main.swift

echo "==> Testler çalıştırılıyor"
echo
"$BINARY"

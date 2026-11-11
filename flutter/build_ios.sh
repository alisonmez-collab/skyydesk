#!/usr/bin/env bash
# https://docs.flutter.dev/deployment/ios
# no obfuscate, because errors are not easy to read afterwards
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

if ! command -v flutter >/dev/null 2>&1; then
    echo "HATA: flutter PATH'te bulunamadi." >&2
    exit 1
fi

# Apple Team ID depoda tutulmuyor. Signing.xcconfig'ten okunur; CI icin ortam
# degiskeni olarak da verilebilir.
SIGNING_XCCONFIG="$REPO_ROOT/flutter/ios/Flutter/Signing.xcconfig"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
if [ -z "$DEVELOPMENT_TEAM" ] && [ -f "$SIGNING_XCCONFIG" ]; then
    # "|| true": eslesme yoksa bos donsun, set -e scripti burada kesmesin —
    # eksik Team ID'yi asagidaki kontrol anlamli bir mesajla bildiriyor.
    DEVELOPMENT_TEAM=$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p' \
        "$SIGNING_XCCONFIG" | head -1 || true)
fi
if [ -z "$DEVELOPMENT_TEAM" ] || [ "$DEVELOPMENT_TEAM" = "XXXXXXXXXX" ]; then
    echo "HATA: Apple Team ID bulunamadi." >&2
    echo "  cp flutter/ios/Flutter/Signing.xcconfig.example flutter/ios/Flutter/Signing.xcconfig" >&2
    echo "  ve DEVELOPMENT_TEAM satirina kendi Team ID'nizi yazin." >&2
    echo "  (Ya da: DEVELOPMENT_TEAM=ABCDE12345 ./build_ios.sh)" >&2
    exit 1
fi

# Flutter 3.24.5 icin gereken SDK yamasi. Zaten uygulanmissa git apply --check
# basarisiz olur ve adim atlanir.
FLUTTER_SDK=$(dirname "$(dirname "$(command -v flutter)")")
PATCH="$REPO_ROOT/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff"
if [ -f "$PATCH" ]; then
    if git -C "$FLUTTER_SDK" apply --check "$PATCH" 2>/dev/null; then
        git -C "$FLUTTER_SDK" apply "$PATCH"
    fi
fi

# Ekip kimligini icerdigi icin uretilen dosya; depoda sablonu duruyor.
EXPORT_OPTIONS="$REPO_ROOT/flutter/ios/build-exportOptions.plist"
sed "s/__DEVELOPMENT_TEAM__/$DEVELOPMENT_TEAM/" \
    "$REPO_ROOT/flutter/ios/exportOptions.plist.template" > "$EXPORT_OPTIONS"

cd "$REPO_ROOT/flutter"
flutter build ipa --release --export-options-plist="$EXPORT_OPTIONS"

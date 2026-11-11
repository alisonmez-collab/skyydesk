#!/usr/bin/env bash
# Yerel Android paketleme. Kontrol listesi: docs/ANDROID_YAYIN.md
# (CI kendi adimlariyla derliyor, bu betigi kullanmiyor.)
set -euo pipefail

MODE=${MODE:=release}

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
    echo "HATA: ANDROID_NDK_HOME tanimli degil." >&2
    echo "  app/build.gradle r28c (28.2.13676358) pinliyor; ayni NDK'yi gosterin." >&2
    exit 1
fi

# GCC tabanli "toolchains/aarch64-linux-android-4.9/..." yolu NDK r18'de kaldirildi;
# r28'de strip araci llvm-strip ve tek bir llvm dizininde, tum mimariler icin ortak.
# Onceki hali o eski yolu cagiriyordu ve r28 ile ilk satirda "No such file or
# directory" veriyordu.
HOST_TAG=linux-x86_64
case "$(uname -s)" in
    Darwin) HOST_TAG=darwin-x86_64 ;;
    MINGW*|MSYS*|CYGWIN*) HOST_TAG=windows-x86_64 ;;
esac
STRIP="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin/llvm-strip"

if [ ! -x "$STRIP" ]; then
    echo "HATA: llvm-strip bulunamadi: $STRIP" >&2
    exit 1
fi

for abi in arm64-v8a armeabi-v7a; do
    dir="android/app/src/main/jniLibs/$abi"
    if [ -d "$dir" ]; then
        # Bos dizinde glob'un kendisi arguman olarak gecmesin diye -maxdepth ile.
        find "$dir" -maxdepth 1 -name '*.so' -exec "$STRIP" {} +
    fi
done

flutter build apk --target-platform android-arm64,android-arm --${MODE} --obfuscate --split-debug-info ./split-debug-info
flutter build apk --split-per-abi --target-platform android-arm64,android-arm --${MODE} --obfuscate --split-debug-info ./split-debug-info
# Play'e giden budur; APK kabul edilmiyor.
flutter build appbundle --target-platform android-arm64,android-arm --${MODE} --obfuscate --split-debug-info ./split-debug-info

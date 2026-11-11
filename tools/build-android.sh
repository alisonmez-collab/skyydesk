#!/bin/bash
# SkyyDesk — Android (.apk) derlemesi.
#
# Linux/Windows karsiliklari tools/build-linux.sh ve tools/build-windows.bat.
# Ucu de ayni kaynak agacindan, ayni sirayla calisir: once bagimliliklar,
# sonra Rust kutuphanesi, sonra platformun paketi.
#
#   ./tools/build-android.sh              arm64-v8a (varsayilan)
#   ./tools/build-android.sh armeabi-v7a  32 bit ARM
#   ./tools/build-android.sh --check      sadece on kosullari dogrula
#
# NEDEN LINUX: Android'i Windows kutusundan capraz derlemek denendi ve zincir
# her adimda kirildi — cargo-ndk'nin Windows sarmalayicisi API seviyesini
# dusuruyor, OpenSSL'in Configure'u Unix yollu bir perl istiyor, ffmpeg msys
# kabugu ariyor. Upstream de Android'i Ubuntu'da derliyor; desteklenen host bu.
# Kaynak tek; derleyen makinenin hangisi oldugu ayri bir sey.

# Derleme ortami, yayin oncesi test listesi ve ekran goruntusu recetesi:
#   SkyyDesk deposu -> docs/ANDROID_YAYIN.md

set -uo pipefail

export PATH="$HOME/.cargo/bin:$HOME/flutter/bin:$PATH"
# SDK notr bir yoldan cagriliyor: OpenSSL derleyicinin TAM YOLUNU
# kutuphaneye dizgi olarak gomuyor ve $HOME altindaki yol derleme
# makinesini anlatiyordu (28.09.2026). /opt/android-sdk ayni dizine
# bakan bir bag; gomulen dizgi artik notr.
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"

# Cargo deposu ve derleme ciktisi ev dizininin DISINDA: gomulen dizgiler
# (openssl-sys'in ENGINESDIR oneki, kcp-sys'in C dosyasindaki __FILE__)
# hedef ve depo dizininden geliyor ve yol haritasi bayraklari onlara islemiyor
# -- cunku dosya yolu kaydi degil, derleme tanimi. Linux derlemesi ayni
# dizinleri kullaniyor; ikisi ayni depoyu paylassin diye adlari da ayni.
export CARGO_HOME="${CARGO_HOME:-/var/tmp/skyydesk-cargo}"
export PATH="$PATH:$CARGO_HOME/bin"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/var/tmp/skyydesk-android}"

# Derleme makinesinin yollari pakete GOMULUYOR. Android tarafinda bu ayar hic
# yoktu: 28.09.2026'da olculdu, libskyydesk.so icinde kendi kaynak agacimizdan
# 604 yol duruyordu. Bayraklar Linux derlemesiyle ayni dosyadan okunuyor.
. "$(dirname "$0")/yol-anonim.sh"

# Varsayilani kapali yetkiler iki dilde yazili; ayrisirlarsa ayar kutusu "acik"
# gorunurken izin kapali kalir. Linux derlemesinde de ayni denetim var.
python3 "$(dirname "$0")/varsayilan-deneme.py" || die "yetki varsayilanlari iki tarafta ayrismis"

export RUSTFLAGS="${RUSTFLAGS:-} $(yol_anonim_bayraklari "$(pwd)")"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

say() { printf '\n=== %s — %s\n' "$1" "$(date '+%H:%M:%S')"; }
die() { printf 'HATA: %s\n' "$1" >&2; exit 1; }

ABI="${1:-arm64-v8a}"
[ "$ABI" = "--check" ] && { ABI=arm64-v8a; CHECKONLY=1; }
case "$ABI" in
  arm64-v8a)   TRIPLET=arm64-android;    RUSTTARGET=aarch64-linux-android;  PLATFORM=android-arm64; NDKABI=aarch64-linux-android ;;
  armeabi-v7a) TRIPLET=arm-neon-android; RUSTTARGET=armv7-linux-androideabi; PLATFORM=android-arm; NDKABI=arm-linux-androideabi ;;
  *) die "desteklenmeyen ABI: $ABI  (arm64-v8a | armeabi-v7a)" ;;
esac

say "on kosullar   ABI=$ABI  triplet=$TRIPLET"
for c in cargo cargo-ndk flutter javac; do
  command -v "$c" >/dev/null 2>&1 || die "$c bulunamadi"
  printf '  %-10s %s\n' "$c" "$(command -v $c)"
done
[ -x "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ] \
  || die "NDK eksik ya da yok: $ANDROID_NDK_HOME"
printf '  %-10s %s\n' ndk "$ANDROID_NDK_HOME"
[ -x "$VCPKG_ROOT/vcpkg" ] || die "vcpkg yok: $VCPKG_ROOT"
printf '  %-10s %s\n' vcpkg "$VCPKG_ROOT"

# Imzalama: anahtar depoda DURMAZ (bkz. flutter/android/.gitignore).
[ -f flutter/android/key.properties ] \
  || die "flutter/android/key.properties yok. Ornek: flutter/android/key.properties.example"
printf '  %-10s %s\n' imza "key.properties bulundu"

[ -n "${CHECKONLY:-}" ] && { echo "on kosullar tamam"; exit 0; }

say "markalama denetimi"
BRAND=$(sh tools/brand-check.sh)
echo "$BRAND" | sed 's/^/  /'
gate() { echo "$BRAND" | grep -q "$1" || die "denetim: $2"; }
gate '^FOREIGN_ENDPOINTS=yok$'  "urun bize ait olmayan bir adrese cikiyor -> $(echo "$BRAND" | grep FOREIGN)"
gate 'APP_NAME_RAW.*SkyyDesk'    "APP_NAME SkyyDesk degil"
gate 'ANDROID_LABEL.*SkyyDesk'   "uygulama adi SkyyDesk degil"
gate 'ANDROID_APPID.*com\.elpo\.skyydesk' "applicationId beklenen deger degil"
gate 'ANDROID_SCHEME.*skyydesk'  "url semasi skyydesk degil"
gate '^STALE_BRAND=yok$'        "arayuzde eski marka kalintisi"

say "yetim dosya denetimi"
orphan=$(git status --porcelain --ignored flutter/assets res 2>/dev/null | grep '^!!' | sed 's/^!! //' | tr '\n' ' ')
[ -n "$orphan" ] && die "paketlenen dizinde git'in gormedigi dosya var: $orphan"
echo "  -> yetim dosya yok"

say "1/3 bagimliliklar (vcpkg, $TRIPLET)"
./flutter/build_android_deps.sh "$ABI" || die "vcpkg bagimliliklari"

say "2/3 rust kutuphanesi ($RUSTTARGET)"
# hwcodec'in build.rs'i bindgen calistiriyor ve bindgen sysroot verilmezse HOST
# basliklarini okuyor: /usr/include/stdint.h'yi acip, hedef aarch64 oldugu icin
# bits/ dizinini aarch64 multiarch'inda ariyor ve bulamiyor. Hata
# "bits/libc-header-start.h file not found" diyor — kulaga eksik paket gibi
# geliyor, oysa dosya makinede duruyor, sadece yanlis yerde araniyor.
NDK_SYSROOT="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
export "BINDGEN_EXTRA_CLANG_ARGS_$(echo "$RUSTTARGET" | tr - _)=--target=${RUSTTARGET}21 --sysroot=$NDK_SYSROOT"
cargo ndk --platform 21 --target "$RUSTTARGET" build --locked --release --features flutter,hwcodec \
  || die "cargo ndk build"

# Baglayicinin yazdigi arama yolu derleme makinesinin rustup dizinini
# gosteriyor. Paket kutuphaneleri yan yana tasidigi icin dogru deger
# "$ORIGIN"; patchelf varsa duzeltiliyor.
# Kutuphanenin yeri TEK yerde: hedef dizin ev dizininin disinda ve asagidaki
# kopyalama da ayni degiskeni okumali (28.09.2026).
SO="$CARGO_TARGET_DIR/$RUSTTARGET/release/liblibskyydesk.so"
if command -v patchelf >/dev/null 2>&1 && [ -f "$SO" ]; then
  patchelf --set-rpath '$ORIGIN' "$SO" 2>/dev/null \
    && echo "  -> arama yolu (RPATH) sadelestirildi"
fi
[ -f "$SO" ] || die "beklenen kutuphane yok: $SO"
mkdir -p "flutter/android/app/src/main/jniLibs/$ABI"
rm -f "flutter/android/app/src/main/jniLibs/$ABI/librustdesk.so"  # eski ad artifacti kalmasin
cp "$SO" "flutter/android/app/src/main/jniLibs/$ABI/libskyydesk.so"
"$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" \
  "flutter/android/app/src/main/jniLibs/$ABI/libskyydesk.so"
# libskyydesk.so, NDK'nin libc++_shared.so'suna baglanir; onu da pakete koymazsak
# uygulama ACILISTA "dlopen failed: libc++_shared.so not found" ile CRASH eder.
cp "$NDK_SYSROOT/usr/lib/$NDKABI/libc++_shared.so" \
  "flutter/android/app/src/main/jniLibs/$ABI/libc++_shared.so"
printf '  libskyydesk.so %s bayt\n' "$(stat -c%s "flutter/android/app/src/main/jniLibs/$ABI/libskyydesk.so")"

say "3/3 apk"
# Kaynaklar (ikonlar, strings) degistiginde Gradle'in eski ara ciktilari
# uyusmuyor ve derleme "Unable to locate resourceFile ... in source-sets" diyerek
# duduyor — hata degisen dosyayi degil, ara dizindeki bir kalintiyi gosteriyor.
# Yalniz Android modulunun ciktisini at; flutter clean tum build/ dizinini
# silecegi icin Linux .deb derlemesini de bosuna sifirlardi.
if [ -d flutter/build/app ] && [ -n "$(find flutter/android/app/src/main/res -newer flutter/build/app -print -quit 2>/dev/null)" ]; then
  echo "  kaynaklar degismis — flutter/build/app temizleniyor"
  rm -rf flutter/build/app
fi
( cd flutter && flutter build apk --target-platform "$PLATFORM" --release ) || die "flutter build apk"

# Paketin ICINDEKI kutuphaneler olculuyor: bayrak dusesse derleme "basarili"
# biter ve musteriye derleme makinesinin dizin agacini anlatan bir paket gider.
APK_OLC=$(mktemp -d /tmp/apk-yol-XXXXXX)
unzip -q -o "flutter/build/app/outputs/flutter-apk/app-release.apk" "lib/*" -d "$APK_OLC" \
  || die "apk acilamadi (yol denetimi)"
APK_HATA=0
for _so in $(find "$APK_OLC" -name '*.so'); do
  case "$(basename "$_so")" in
    libflutter.so|libc++_shared.so) continue ;;   # hazir gelen ikililer
  esac
  yol_denetimi "$_so" || APK_HATA=1
done
rm -rf "$APK_OLC"
[ "$APK_HATA" -eq 0 ] || die "derleme makinesinin yolu pakete sizmis (yukariya bak)."

APK=flutter/build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || die "apk olusmadi: $APK"

# Play Store'a APK YUKLENMIYOR — yeni uygulamalarda yalnizca App Bundle kabul
# ediliyor. APK sahada elden kurulum ve test icin lazim, AAB magaza icin; ikisi
# de uretiliyor. Ayri komut olarak birakilsa derlemeyi yapan kisi AAB uretmeyi
# unutur ve magazaya yuklenecek dosya olmaz.
( cd flutter && flutter build appbundle --target-platform "$PLATFORM" --release ) || die "flutter build appbundle"
AAB=flutter/build/app/outputs/bundle/release/app-release.aab
[ -f "$AAB" ] || die "aab olusmadi: $AAB"

say "sonuc"
OUT="SkyyDesk-Android-$ABI.apk"
mv -f "$APK" "$OUT"
printf '  paket : %s (%s bayt)\n' "$OUT" "$(stat -c%s "$OUT")"
OUT_AAB="SkyyDesk-Android.aab"
mv -f "$AAB" "$OUT_AAB"
printf '  magaza: %s (%s bayt) - Play icin yuklenecek dosya BUDUR\n' "$OUT_AAB" "$(stat -c%s "$OUT_AAB")"
"$ANDROID_HOME"/build-tools/*/aapt2 dump badging "$OUT" 2>/dev/null \
  | grep -E "^package|application-label:|sdkVersion|native-code" | sed 's/^/  /'

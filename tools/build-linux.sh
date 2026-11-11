#!/bin/bash
# SkyyDesk — Linux (.deb) derlemesi.
#
# Windows karsiligi tools/build-windows.bat. Ikisi de ayni kaynak agacindan,
# ayni sirayla calisir: once Rust kutuphanesi, sonra Flutter kabugu, sonra
# platformun paketi. Bir platformda yapilan markalama degisikligi digerinde
# de ayni dosyadan okunur; ayrisma ancak biri calistirilmazsa olur.
#
#   ./tools/build-linux.sh          derle ve paketle
#   ./tools/build-linux.sh --check  sadece on kosullari dogrula
#
# Docker kullanilmaz — kurulum dogrudan makinede.

set -uo pipefail

export PATH="$HOME/.cargo/bin:$HOME/flutter/bin:$PATH"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

say() { printf '\n=== %s — %s\n' "$1" "$(date '+%H:%M:%S')"; }
die() { printf 'HATA: %s\n' "$1" >&2; exit 1; }

say "on kosullar"
for c in cargo flutter python3 dpkg-deb; do
  command -v "$c" >/dev/null 2>&1 || die "$c bulunamadi"
  printf '  %-10s %s\n' "$c" "$(command -v $c)"
done
for p in libyuv opus vpx; do
  printf '  %-10s %s\n' "$p" "$(pkg-config --modversion $p 2>/dev/null || echo 'YOK')"
done
[ "${1:-}" = "--check" ] && { echo "on kosullar tamam"; exit 0; }

say "markalama denetimi"
BRAND=$(sh tools/brand-check.sh)
echo "$BRAND" | sed 's/^/  /'

# Upstream birlesmelerinden sonra bu degerler sessizce geri gelebiliyor;
# hatirlamaya birakmiyoruz, derlemeyi dusuruyoruz.
gate() {
  echo "$BRAND" | grep -q "$1" || die "denetim: $2"
}
gate '^FOREIGN_ENDPOINTS=yok$'        "urun bize ait olmayan bir adrese cikiyor -> $(echo "$BRAND" | grep FOREIGN)"
gate 'RENDEZVOUS.*rs\.skyydesk\.com' "rendezvous sunucusu bizim degil -> $(echo "$BRAND" | grep RENDEZVOUS)"
gate 'APP_NAME_RAW.*SkyyDesk'          "APP_NAME SkyyDesk degil -> $(echo "$BRAND" | grep APP_NAME)"
gate 'HOMEPAGE.*skyydesk\.com'        "Homepage bizim alan adimiz degil"
# Ad tutarliligi: kodun hesapladigi ad ile paketin yazdigi ad ayrildiginda
# hicbir sey hata vermez, sadece calismaz. Gozetimsiz oturum icin xorg.conf
# ve startwm.sh bulunamaz, PAM sessizce gdm yiginina duser.
gate '^ETC_PATH_MISMATCH=yok$'       "paket /etc altina yanlis adla kuruyor -> $(echo "$BRAND" | grep ETC_PATH)"
gate '^PAM_NAME_MISMATCH=yok$'       "PAM dosyasi yanlis adla kuruluyor -> $(echo "$BRAND" | grep PAM_NAME)"
gate '^MACOS_ORG_MISMATCH=yok$'      "macOS scriptleri baska org oneki tasiyor -> $(echo "$BRAND" | grep MACOS_ORG)"
gate 'ANDROID_LABEL.*SkyyDesk'        "Android uygulama adi SkyyDesk degil"
gate 'ANDROID_SCHEME.*skyydesk'       "Android derin baglanti semasi skyydesk degil"
# Arayuzde eski marka: yan menudeki yazi iki parca halinde kuruldugu icin
# (Elpo + Desk) hicbir dizge aramasi gormuyordu, ekranda ise yaziyordu.
gate '^STALE_BRAND=yok$'             "arayuzde eski marka kalintisi -> $(echo "$BRAND" | grep STALE_BRAND)"
# Masaustu girisi/servis birimi ikilinin adiyla eslesmezse paket sessizce
# yanlis dosyayi kurar ya da hic kurmaz; ikisi de calisma aninda anlasilir.
gate '^DESKTOP_FILE=[^E]'            "masaustu girisi ikilinin adiyla eslesmiyor"
gate '^SERVICE_FILE=[^E]'            "servis birimi ikilinin adiyla eslesmiyor"
echo "  -> denetim gecti"

say "yetim dosya denetimi"
# Paketlenen dizinlerde git'in yok saydigi dosya varsa iki makine farkli
# icerik dagitir: dosya depoda olmadigi icin digerine hic gitmez, ama
# paketleyici (pubspec assets/, build.py res/) onu yine de alir.
orphan=$(git status --porcelain --ignored flutter/assets res 2>/dev/null | grep '^!!' | sed 's/^!! //' | tr '\n' ' ')
if [ -n "$orphan" ]; then
  die "paketlenen dizinde git'in gormedigi dosya var: $orphan"
fi
echo "  -> yetim dosya yok"

say "bridge damgasi"
# Uretilmis bridge dosyalari depoda tutuluyor (ureten arac dis bir indirme).
# Kaynak degistiginde eskirler; ortaya cikan hata derlemenin cok ilerisinde,
# anlasilmasi zor bir tip uyusmazligi olarak gorunur. Damga onu burada yakalar.
if [ -f tools/bridge.stamp ]; then
  want=$(grep -v '^#' tools/bridge.stamp | tr -d '[:space:]')
  # Satir sonu CEVIRISINDEN bagimsiz ozet: Windows klonunda dosya CRLF ile
  # duruyor, Linux'ta LF. Ham sha256 iki makinede farkli cikiyor ve damga
  # hicbir zaman ikisine birden uymuyordu (26.09.2026).
  have=$(tr -d '' < src/flutter_ffi.rs | sha256sum | cut -d' ' -f1)
  if [ "$want" != "$have" ]; then
    die "src/flutter_ffi.rs degismis ama bridge yenilenmemis.
  Once:  flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart
  Sonra: sha256sum src/flutter_ffi.rs degerini tools/bridge.stamp icine yaz."
  fi
  echo "  -> bridge guncel"
fi

say "1/3 rust kutuphanesi"
# hwcodec: H264/H265 donanim kodlama/cozme (VAAPI/QSV). GPU'lu musteri
# Linux'unda karsi tarafa yazilim AV1/VP9 yerine donanim H264 sunulur —
# telefon/istemci de H264'u donanimla cozer, oturum belirgin hizlanir.
# ffmpeg vcpkg'den STATIK gelir (x64-linux triplet), .deb'e yeni .so girmez.
# GPU'suz makinede zarar yok: aygit yoksa kendiliginden yazilima duser.
export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/vcpkg}"
[ -d "$VCPKG_ROOT/installed/x64-linux/lib" ] \
  || die "vcpkg x64-linux kurulu degil (hwcodec ffmpeg ister): ~/vcpkg/vcpkg install --triplet x64-linux --x-install-root=\$HOME/vcpkg/installed"
# ffmpeg VAAPI OLMADAN derlenir (vcpkg: ffmpeg[avcodec,avformat,avfilter,
# swscale,swresample,nvcodec]:x64-linux).
#
# NEDEN: vcpkg'nin guncel ffmpeg'i libva 2.20+ simgeleri kullaniyor
# (vaMapBuffer2); Debian 12 / Ubuntu 22.04 kusagi libva 2.17 tasiyor. VAAPI
# acik derlenince kutuphane musterinin makinesinde HIC yuklenmiyor
# ("undefined symbol: vaSyncSurface", sonra "vaMapBuffer2" — 26.09.2026).
# Paketin calismasi, olmayan bir GPU hizlandirmasindan onemli. NVENC/NVDEC
# duruyor; VAAPI gerekirse ffmpeg'in libva 2.20+ ile derlendigi ayri bir
# paket kusagi gerekir.

# hwcodec'in C++ tarafi ffmpeg BASLIKLARINA gore derleniyor ve cargo bunu
# yalniz kendi kaynagi degisince yeniliyor. ffmpeg vcpkg'de degistiginde eski
# nesne dosyalari kaliyor ve artik var olmayan simgelere (ornegin VAAPI'nin
# va* cagrilari) bagli bir kutuphane cikiyor. ffmpeg daha yeniyse hwcodec
# bilerek temizleniyor (26.09.2026'da tam bu yasandi).
FFMPEG_LIB="$VCPKG_ROOT/installed/x64-linux/lib/libavcodec.a"
# ffmpeg HIC kurulu degilse hwcodec eski nesnelerine yaslanip sessizce
# cozumsuz simgeli bir kutuphane uretiyor (26.09.2026: vcpkg'nin installed
# agacinda libav* yoktu, derleme "basarili" bitti, kutuphane yuklenmedi).
[ -f "$FFMPEG_LIB" ] || die "ffmpeg kurulu degil: $FFMPEG_LIB
  ~/vcpkg/vcpkg install \"ffmpeg[avcodec,avformat,avfilter,swscale,swresample,nvcodec]:x64-linux\""
HWCODEC_CIKTI=$(ls -d "$HEDEF"/release/build/hwcodec-*/output 2>/dev/null | head -1)
if [ -f "$FFMPEG_LIB" ] && [ -n "$HWCODEC_CIKTI" ] && [ "$FFMPEG_LIB" -nt "$HWCODEC_CIKTI" ]; then
  echo "  ffmpeg yenilenmis -> hwcodec temizleniyor"
  cargo clean -p hwcodec 2>/dev/null || true
fi

# hwcodec'in build betigi yalniz avcodec/avutil/avformat bildiriyor; ffmpeg'in
# geri kalani (swresample, swscale) bildirilmiyor ve statik baglantida
# "undefined symbol: swr_close" ile cikiyor. Eksik olanlar burada ekleniyor.
# libvpx / aom / libyuv: BASLIK ile KUTUPHANE ayni yerden gelmek ZORUNDA.
#
# linux-pkg-config ozelligi basliklari SISTEMDEN aliyor (libvpx-dev 1.12,
# libaom-dev 3.6, libyuv0 2023); asagidaki -L ise baglayiciya once vcpkg
# dizinini gosteriyor ve orada yalnizca .a var — yani gercekte baglanan
# kutuphane vcpkg'nin STATIK surumu (libvpx 1.15.2, aom 3.12.1, libyuv 1857).
#
# 28.09.2026'da olculdu: uretilmis bagintilar VPX_ENCODER_ABI_VERSION=25
# (1.12'nin degeri) diyordu, baglanan 1.15.2 ise 37 bekliyor. Sonuc:
# vpx_codec_enc_init_ver VPX_CODEC_ABI_MISMATCH dondu, kodlayici hic
# kurulamadi ve Linux istemcisi TEK KARE bile uretmedi. Ses ve pano ayri
# servis oldugu icin oturum disaridan saglikli gorunuyor, hata da karsi
# makinenin ekran yakalamasinda araniyordu.
#
# build.rs'in kendi kacis kapisi: NO_PKG_CONFIG_<paket>=1 -> o paket icin
# hem baslik hem kutuphane vcpkg'den gelir.
export NO_PKG_CONFIG_libvpx=1
export NO_PKG_CONFIG_aom=1
export NO_PKG_CONFIG_libyuv=1

# Derleme ciktisi kullanici dizininin DISINDA tutuluyor. Sebebi: openssl-sys,
# OpenSSL'i kendi derleyip kurulum onekini (ENGINESDIR/MODULESDIR) kutuphaneye
# dizgi olarak gomuyor ve o onek OUT_DIR'den, yani hedef dizinden geliyor.
# Yol haritasi bayraklari bu dizgiye islemiyor -- cunku dosya yolu kaydi degil,
# derleme tanimi. Hedef dizin notr olunca gomulen dizgi de notr oluyor.
# Cargo deposu da ev dizininin disinda. Sebebi: OpenSSL derleyici komut
# satirini kutuphaneye gomuyor ve orada gorunen -ffile-prefix-map esleme
# KAYNAGI ($HOME/.cargo) derleme makinesini anlatiyordu. Depo notr olunca
# eslemeye gerek kalmiyor, dolayisiyla gomulecek bir yol da kalmiyor.
export CARGO_HOME="${CARGO_HOME:-/var/tmp/skyydesk-cargo}"
export PATH="$PATH:$CARGO_HOME/bin"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/var/tmp/skyydesk-derleme}"
HEDEF="$CARGO_TARGET_DIR"
mkdir -p "$HEDEF"
# Paketleyici (upstream build.py) target/ altina bakiyor. Baglanti
# kuruyoruz: cargo gercek dosyalari HEDEF altina yaziyor -- yani gomulen
# yollar notr kaliyor -- ama eski gondermeler de calismaya devam ediyor.
[ -L target ] || [ -e target ] && rm -rf target 2>/dev/null || true
ln -sfn "$HEDEF" target

# Derleme makinesinin yollari ikiliye GOMULUYOR. Rust, panik mesajlarina ve
# hata ayiklama bilgisine kaynak dosyanin tam yolunu yaziyor; olculdu
# (28.09.2026): kurulu kutuphanede derleme kullanicisinin ev dizini 1091 kez, cargo deposu
# yolu 977 kez geciyor. Musteriye giden bir dosyada bizim kullanici adimiz ve
# dizin duzenimiz duruyor -- sizma testi raporlarinin "bilgi ifsasi" basligi
# tam olarak budur.
#
# Bayraklar ve denetim ortak dosyada: ayni is Android derlemesinde de
# gerekiyor ve orada hic yoktu (28.09.2026, 604 yol sizmisti).
. "$(dirname "$0")/yol-anonim.sh"

# Varsayilani kapali yetkiler iki dilde yazili (Rust izni uygular, Dart kutuyu
# cizer). Ayrisirlarsa kutu "acik" gorunurken izin kapali kalir; derlemeden
# once bakiliyor.
python3 "$(dirname "$0")/varsayilan-deneme.py" || die "yetki varsayilanlari iki tarafta ayrismis"

YOL_ANONIM=$(yol_anonim_bayraklari "$(pwd)")

# C tarafina yol haritasi bayragi VERILMIYOR. Sebebi olculdu (28.09.2026):
# openssl-sys, OpenSSL'i kendi derlerken derleyicinin TAM KOMUT SATIRINI
# kutuphaneye dizgi olarak gomuyor. Bayragin esleme kaynagi kendi kaynak
# agacimiz oldugu icin (-ffile-prefix-map=<agac>=/skyydesk) bayragin
# KENDISI derleme makinesini anlatiyordu; bekcinin yakaladigi tek sizinti
# buydu. Bayragi kaynak yolunu icinde gecirmeden yazmanin yolu yok.
#
# Rust tarafi --remap-path-prefix ile kapali ve Rust komut satirini hicbir
# yere gomuyor. Geriye kendi C dosyalarimiz kaliyor; yol sizdirip
# sizdirmadiklari asagidaki bekci ile OLCULUYOR. Sizdiriyorlarsa derleme
# durur ve cozum bayrak degil, kaynak agacini notr bir dizine tasimaktir.

export RUSTFLAGS="${RUSTFLAGS:-} $YOL_ANONIM -L $VCPKG_ROOT/installed/x64-linux/lib -C link-arg=-lswresample -C link-arg=-lswscale"

cargo build --locked --features "flutter,linux-pkg-config,hwcodec" --lib --release \
  || die "cargo build basarisiz"
ls -la "$HEDEF/release/liblibskyydesk.so" 2>/dev/null | sed 's/^/  /'

# Yol sizintisi denetimi. Bayrak bir gun kaldirilirsa ya da yeni bir yol
# sizarsa, bunu musteri yerine derleme soylesin.
# Baglayicinin yazdigi arama yolu (RPATH) derleme makinesinin rustup
# dizinini gosteriyor. Paket butun kutuphaneleri yan yana tasidigi icin
# dogru deger "$ORIGIN"; patchelf varsa duzeltiliyor.
if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-rpath '$ORIGIN' "$HEDEF/release/liblibskyydesk.so" 2>/dev/null \
    && echo "  -> arama yolu (RPATH) sadelestirildi"
fi

TUM=$(strings -a "$HEDEF/release/liblibskyydesk.so" 2>/dev/null | grep "$HOME" || true)
BIZIM=$(printf '%s\n' "$TUM" | grep -v "vcpkg/buildtrees" | grep -c "$HOME" || true)
ONCEDEN=$(printf '%s\n' "$TUM" | grep -c "vcpkg/buildtrees" || true)
if [ "${BIZIM:-0}" -gt 0 ]; then
  printf '%s\n' "$TUM" | grep -v "vcpkg/buildtrees" | head -3 | sed 's/^/    /'
  die "derleme makinesinin yolu ikiliye sizmis ($BIZIM kez).
  Yol haritasi bayraklari (YOL_ANONIM / CFLAGS) ya da CARGO_TARGET_DIR
  ayari kaldirilmis olabilir."
fi
echo "  -> kendi kodumuzda yol sizintisi yok"
if [ "${ONCEDEN:-0}" -gt 0 ]; then
  echo "  -> onceden derlenmis vcpkg kutuphanelerinde $ONCEDEN yol kaldi"
  echo "     (o yollar paketler derlenirken gomuldu; temizlenmesi vcpkg"
  echo "      portlarinin -ffile-prefix-map ile yeniden derlenmesini ister)"
fi

# Bagintilar ile baglanan kutuphane ayni ABI'de mi? Yukaridaki ayar bozulursa
# derleme "basarili" biter ve hicbir kare uretmeyen bir paket cikar. Sayiyi
# burada karsilastirmak, bunu musterinin yerine derlemenin yakalamasi icin.
ABI_DIZIN=$(mktemp -d /tmp/vpx-abi-XXXXXX)
cat > "$ABI_DIZIN/abi.c" <<'ABIC'
#include <stdio.h>
#include <vpx/vpx_encoder.h>
int main(void) { printf("%d\n", VPX_ENCODER_ABI_VERSION); return 0; }
ABIC
gcc -I"$VCPKG_ROOT/installed/x64-linux/include" "$ABI_DIZIN/abi.c" -o "$ABI_DIZIN/abi" \
  || die "VPX ABI denetimi derlenemedi (vcpkg basliklari eksik?)"
ABI_KUTUPHANE=$("$ABI_DIZIN/abi")
BAGINTI_DOSYA=$(ls -t "$HEDEF"/release/build/scrap-*/out/vpx_ffi.rs | head -1)
ABI_BAGINTI=$(sed -n 's/^pub const VPX_ENCODER_ABI_VERSION[^=]*= *\([0-9]*\);.*/\1/p' "$BAGINTI_DOSYA")
rm -rf "$ABI_DIZIN"
[ -n "$ABI_BAGINTI" ] || die "uretilmis vpx bagintilari okunamadi: $BAGINTI_DOSYA"
[ "$ABI_KUTUPHANE" = "$ABI_BAGINTI" ] || die "VPX ABI uyusmuyor: kutuphane $ABI_KUTUPHANE bekliyor, bagintilar $ABI_BAGINTI diyor.
  Kodlayici hic kurulamaz, paket TEK KARE uretmez. Cozum: cargo clean -p scrap"
echo "  -> VPX ABI $ABI_BAGINTI (kutuphane $ABI_KUTUPHANE bekliyor)"

# Yuklenebilirlik denetimi: cozumsuz sembol kaldiysa pakete GIRMESIN.
python3 - "$HEDEF/release/liblibskyydesk.so" <<'PY' || die "kutuphane yuklenemiyor (cozumsuz sembol)"
import ctypes, sys
try:
    ctypes.CDLL(sys.argv[1])
except OSError as e:
    print("  YUKLENEMEDI:", e)
    sys.exit(1)
print("  -> kutuphane yuklenebiliyor")
PY

say "2/3 flutter kabugu"
( cd flutter && flutter build linux --release ) || die "flutter build basarisiz"
BUNDLE="flutter/build/linux/x64/release/bundle"
[ -x "$BUNDLE/skyydesk" ] || die "beklenen ikili yok: $BUNDLE/skyydesk"
printf '  ikili: %s\n' "$(ls -la $BUNDLE/skyydesk | awk '{print $5" bayt"}')"

say "3/3 debian paketi"
# --skip-cargo sart: build.py kendi cargo cagrisinda linux-pkg-config'i
# bilmiyor, opus'u kaynaktan derlemeye kalkip magnum-opus'ta patliyor.
# Kutuphaneyi zaten 1. adimda dogru bayraklarla derledik.
python3 build.py --flutter --skip-cargo || die "build.py basarisiz"
DEB=$(ls -t *.deb 2>/dev/null | head -1)
[ -n "$DEB" ] || die "deb uretilmedi"

say "sonuc"
printf '  paket : %s (%s bayt)\n' "$DEB" "$(stat -c%s "$DEB")"
dpkg-deb -f "$DEB" Package Version Maintainer Homepage 2>/dev/null | sed 's/^/  /'
echo
echo "paketteki ikili ve masaustu girisi:"
dpkg-deb -c "$DEB" | grep -E 'usr/bin/|\.desktop|\.service' | awk '{print "  "$6}' | head

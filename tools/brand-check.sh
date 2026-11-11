#!/bin/sh
# Bir SkyyDesk kaynak agacinin icinde calisir ve markalamayla ilgili her
# degeri tek bir yerden okur. Cikti KEY=DEGER satirlaridir; iki makinede
# calistirilip birebir karsilastirilmak icin tasarlandi.
#
#   ./brand-check.sh          degerleri yaz
#   ./brand-check.sh --leaks  ustteki degerlere ek olarak sizan upstream
#                             markalamasini dosya dosya listele
#
# Neden boyle: ayni bilgi build.py, CMakeLists, Runner.rc ve config.rs
# icinde ayri ayri duruyor. Hangisinin dogru oldugunu tartismak yerine
# hepsini yan yana yazdirip birbirini tutuyor mu diye bakiyoruz.

set -eu
# Turkce yerel ayarda [A-Za-z] araligi beklendigi gibi eslesmiyor ve degerler
# yarim okunuyor. Karsilastirma araci makineye gore farkli sonuc veremez.
LC_ALL=C
export LC_ALL
cd "$(dirname "$0")/.." 2>/dev/null || true
[ -f Cargo.toml ] || { echo "SkyyDesk kaynak agacinda degiliz" >&2; exit 2; }

# tek satirlik degeri cek; bulunamazsa bos birak (sessizce gecme, "-" yaz)
val() {
  v=$(grep -m1 -oE "$2" "$1" 2>/dev/null | head -1 || true)
  printf '%s=%s\n' "$3" "${v:--}"
}

printf 'COMMIT=%s\n'  "$(git rev-parse --short HEAD 2>/dev/null || echo -)"
printf 'DIRTY=%s\n'   "$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

val Cargo.toml                        '^version = "[^"]+"'            VERSION
val libs/hbb_common/src/config.rs     'APP_NAME[^=]*= *RwLock::new\("[^"]+"' APP_NAME_RAW
val flutter/linux/CMakeLists.txt      'BINARY_NAME "[^"]+"'           BIN_LINUX
val flutter/windows/CMakeLists.txt    'BINARY_NAME "[^"]+"'           BIN_WINDOWS
val build.py                          'Package: [A-Za-z0-9._-]+'      DEB_PACKAGE
val libs/portable/Cargo.toml          'ProductName = "[^"]+"'         WINRES_PRODUCT
val libs/portable/Cargo.toml          'OriginalFilename = "[^"]+"'    WINRES_ORIGFILE
val flutter/windows/runner/Runner.rc  '"InternalName", "[^"]+"'       RC_INTERNAL
val flutter/windows/runner/Runner.rc  '"OriginalFilename", "[^"]+"'   RC_ORIGFILE
val flutter/windows/runner/Runner.rc  '"ProductName", "[^"]+"'        RC_PRODUCT

# Masaustu girisi ve servis birimi: dosya adi da markanin parcasi. Paketin
# gercekten kopyaladigi ad araniyor — Linux ikilisinin adi ne ise o.
#
# Onceden burada "res/ icindeki ilk .desktop" yaziyordu. Upstream'in
# rustdesk.desktop dosyalari da o dizinde durdugu icin deger alfabetik siraya
# bagliydi: marka fixdesk iken f<r oldugundan dogru dosyayi gosteriyor, skydesk
# olunca r<s oldugundan rustdesk'inkini gostermeye basliyordu. Yani kontrol
# dogruyu tesadufen soyluyordu.
lbin=$(grep -m1 -oE 'BINARY_NAME "[^"]+"' flutter/linux/CMakeLists.txt 2>/dev/null | cut -d'"' -f2)
for kind in desktop service; do
  key=$(printf '%s_FILE' "$kind" | tr 'a-z' 'A-Z')
  if [ -n "$lbin" ] && [ -f "res/$lbin.$kind" ]; then
    printf '%s=%s\n' "$key" "$lbin.$kind"
  else
    printf '%s=EKSIK\n' "$key"
  fi
done

# Urun icine gomulu alan adlari. Bunlar bize ait olmali; aksi halde istemci
# baglanamaz ve baglanti denemeleri baskasina gider.
val libs/hbb_common/src/config.rs 'RENDEZVOUS_SERVERS[^=]*= *&\[[^]]*\]' RENDEZVOUS
val build.py                      'Homepage: [^ ]+'                       HOMEPAGE

# --- Android ---
# Hicbiri once kontrol edilmiyordu; Android bastan sona upstream markasiyla
# duruyordu ve kimse fark etmemisti cunku o platforma hic derleme yapilmamisti.
val flutter/android/app/src/main/res/values/strings.xml \
    '<string name="app_name">[^<]*'                       ANDROID_LABEL
val flutter/android/app/build.gradle \
    'applicationId "[^"]+"'                               ANDROID_APPID
val flutter/android/app/src/main/AndroidManifest.xml \
    'android:scheme="[^"]+"'                              ANDROID_SCHEME

# --- Ad tutarliligi: kodun hesapladigi ile paketin yazdigi ayni mi ---
# Kod /etc/{app_name}/ ve /etc/pam.d/{app_name} ariyor (linux_desktop_manager.rs).
# build.py bunlari baska bir adla kurarsa gozetimsiz oturum sessizce calismaz:
# xorg.conf ve startwm.sh bulunamaz, PAM gdm yiginina duser.
app_lower=$(grep -oE 'APP_NAME: RwLock<String> = RwLock::new\("[^"]+' \
              libs/hbb_common/src/config.rs 2>/dev/null | sed 's/.*"//' | tr 'A-Z' 'a-z')
org=$(grep -oE 'ORG: RwLock<String> = RwLock::new\("[^"]+' \
        libs/hbb_common/src/config.rs 2>/dev/null | sed 's/.*"//')

etc_bad=$(grep -oE "tmpdeb/etc/[a-z.]+/" build.py 2>/dev/null \
          | sed 's|tmpdeb/etc/||;s|/$||' | sort -u \
          | grep -vx "$app_lower" | grep -vx 'pam.d' | tr '\n' ' ')
pam_bad=$(grep -oE "tmpdeb/etc/pam\.d/[a-z]+" build.py 2>/dev/null \
          | sed 's|.*/||' | sort -u | grep -vx "$app_lower" | tr '\n' ' ')
printf 'ETC_PATH_MISMATCH=%s\n' "${etc_bad:-yok}"
printf 'PAM_NAME_MISMATCH=%s\n' "${pam_bad:-yok}"

# macOS: kurulum scriptleri kodun hesapladigi org onekini tasiyor mu.
# ORG com.carriez'den com.elpo'ya cevrilmisti ama scriptler guncellenmemisti;
# correct_app_name() yalniz uygulama adini ikame ediyor, org onekini degil.
# com.apple.* isletim sisteminin kendi anahtarlaridir, haric tutulur.
mac_bad=$(grep -ohE 'com\.[a-z]+\.' src/platform/privileges_scripts/* 2>/dev/null \
          | sort -u | grep -vx "$org." | grep -vx 'com.apple.' | tr '\n' ' ')
printf 'MACOS_ORG_MISMATCH=%s\n' "${mac_bad:-yok}"

# Arayuzde eski marka kalintisi.
# Yan menudeki yazi iki TextSpan olarak kuruluyordu ('Elpo' + 'Desk'), yani
# kaynakta "ElpoDesk" diye bir dizge yoktu ve hicbir marka taramasi goremedi.
# Ekranda ise acikca yaziyordu. Bu yuzden parca parca aranıyor.
# RustDesk haric tutuluyor: kaynakta gecen yerler ya calisma zamaninda
# correct_app_name() ile ikame ediliyor (macOS scriptleri) ya da
# is_custom_client() ile kapali (yardim karti). Aranan sey ESKI BIZIM
# markalarimiz — bunlarin kalmasi rename'in yarim kaldigini gosterir.
stale=$(git grep -hoE "'(Elpo|ElpoDesk|Fix|FixDesk|FixRemote|Tuwa)'" -- flutter/lib src 2>/dev/null | sort -u | tr '
' ' ')
printf 'STALE_BRAND=%s
' "${stale:-yok}"

# Urunun gercekten BAGLANDIGI adresler. Sadece calisma zamaninda cagrilan
# uc noktalari tasiyan dosyalar taranir ve her dosyanin test modulu disarida
# birakilir: Rust'ta test modulu dosyanin sonunda #[cfg(test)] ile basladigi
# icin tarama o isarete kadar surer. Testlerdeki ornek adresler urunun nereye
# baglandigini soylemez, sadece sinyali bogar.
#
# Bu liste bos degilse urun bize ait olmayan bir adrese cikiyor demektir.
SCAN='libs/hbb_common/src/config.rs libs/hbb_common/src/lib.rs src/common.rs src/client.rs src/auth_2fa.rs'
# Eski marka listeden CIKTI. Bir donem "sahadaki istemciler oraya baglaniyor"
# diye izinliydi; alan adi 07.08.2026'da emekliye ayrildi ve yenilenmeyecek.
# Izinli birakmak, yarin duseceginin bilindigi bir adrese cikmayi sessizce
# kabul etmek olurdu.
OURS='skyydesk\.com|localhost|127\.0\.0\.1'
foreign=$(for f in $SCAN; do
            [ -f "$f" ] && awk '/#\[cfg\(test\)\]/{exit} {print}' "$f"
          done \
          | grep -oE '"https?://[A-Za-z0-9.-]+' \
          | sed 's|"https\?://||' \
          | sort -u \
          | grep -vE "^($OURS)$" \
          | tr '\n' ' ')
printf 'FOREIGN_ENDPOINTS=%s\n' "${foreign:-yok}"

# Upstream markalamasi musteriye gorunebilecek yerlerde kalmis mi.
# Disarida biraktiklarimiz: upstream'in kendi dokumanlari, CI tanimlari,
# magaza metinleri ve AGPL geregi duran lisans/atif dosyalari.
leaks() {
  git ls-files 2>/dev/null | grep -vE '^(\.github/|docs/|fastlane/|examples/|appimage/|flatpak/|libs/clipboard/docs/)' \
    | grep -vE '(^|/)(LICENCE|LICENSE|README\.md|Cargo\.lock|pubspec\.lock)$' \
    | grep -vE '\.(png|ico|gif|jpg|jpeg|ttf|otf|svg|woff2?)$'
}

count=0
list=""
for f in $(leaks); do
  [ -f "$f" ] || continue
  n=$(grep -ci 'rustdesk' "$f" 2>/dev/null || true)
  n=${n:-0}
  if [ "$n" -gt 0 ] 2>/dev/null; then
    count=$((count + n))
    list="$list$n\t$f\n"
  fi
done
printf 'UPSTREAM_LEAK_HITS=%s\n' "$count"

if [ "${1:-}" = "--leaks" ]; then
  echo "--- upstream markalamasi gecen dosyalar ---"
  printf "$list" | sort -rn | head -40
fi

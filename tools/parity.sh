#!/bin/sh
# Windows ve Linux build agaclari ayni seyi mi uretiyor?
#
# "Windows'ta calisti, Linux'ta calismadi" bir kere yasandi: is iki ayri
# kopyada yurutuluyordu ve her kopyada markalamanin yarisi vardi. Bu script
# ayni durumu bir daha sessizce olusamaz hale getirmek icin var.
#
#   ./tools/parity.sh          hepsini kontrol et
#   ./tools/parity.sh src      sadece kaynak agaclari
#   ./tools/parity.sh brand    sadece markalama degerleri
#   ./tools/parity.sh dist     sadece uretilmis paketler
#
# Windows tarafindan (git-bash) calistirilir; Linux tarafina ssh ile bakar.

set -u
LC_ALL=C; export LC_ALL

WIN_SRC="${SKYDESK_WIN_SRC:-/c/ElpoDeskBuild/src}"
LIN_HOST="${SKYDESK_HOST:?set SKYDESK_HOST to the Linux build host, user@host}"
LIN_SRC="${SKYDESK_LIN_SRC:?set SKYDESK_LIN_SRC to the source tree on that host}"

T="${TMPDIR:-/tmp}/skyydesk-parity.$$"
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT

FAIL=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  HATA  %s\n' "$1"; FAIL=1; }
head_() { printf '\n== %s ==\n' "$1"; }

check_src() {
  head_ "kaynak agaclari"

  wc=$(cd "$WIN_SRC" && git rev-parse --short HEAD 2>/dev/null)
  lc=$(ssh "$LIN_HOST" "cd '$LIN_SRC' && git rev-parse --short HEAD" 2>/dev/null)
  [ -n "$wc" ] && [ "$wc" = "$lc" ] && ok "ayni commit ($wc)" || bad "commit ayri: windows=$wc linux=$lc"

  wd=$(cd "$WIN_SRC" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ld=$(ssh "$LIN_HOST" "cd '$LIN_SRC' && git status --porcelain | wc -l" 2>/dev/null | tr -d ' ')
  [ "$wd" = "0" ] && ok "windows agaci temiz" || bad "windows agacinda $wd commitlenmemis degisiklik"
  [ "$ld" = "0" ] && ok "linux agaci temiz"   || bad "linux agacinda $ld commitlenmemis degisiklik"

  # Satir sonu farki kasitli (Windows CRLF, Linux LF); icerik ayni olmali.
  ( cd "$WIN_SRC" && git ls-files | sort | while read -r f; do
      [ -f "$f" ] && printf '%s  %s\n' "$(tr -d '\r' < "$f" | md5sum | cut -d' ' -f1)" "$f" \
                  || printf 'YOK  %s\n' "$f"
    done ) > "$T/w"
  ssh "$LIN_HOST" "cd '$LIN_SRC' && git ls-files | LC_ALL=C sort | while read f; do
      [ -f \"\$f\" ] && printf '%s  %s\n' \"\$(tr -d '\r' < \"\$f\" | md5sum | cut -d' ' -f1)\" \"\$f\" \
                    || printf 'YOK  %s\n' \"\$f\"
    done" > "$T/l" 2>/dev/null

  n=$(awk 'NR==FNR{a[$2]=$1;next}{b[$2]=$1} END{n=0
        for(p in a) if(!(p in b) || a[p]!=b[p]) n++
        for(p in b) if(!(p in a)) n++
        print n}' "$T/w" "$T/l")
  t=$(wc -l < "$T/w" | tr -d ' ')
  if [ "$n" = "0" ]; then
    ok "$t dosyanin tamami birebir ayni"
  else
    bad "$n dosya ayrismis (toplam $t)"
    awk 'NR==FNR{a[$2]=$1;next}{b[$2]=$1} END{
        for(p in a) if(!(p in b)) print "        linuxta yok: "p
        else if(a[p]!=b[p])       print "        farkli     : "p
        for(p in b) if(!(p in a)) print "        windowsta yok: "p}' "$T/w" "$T/l" | sort | head -20
  fi
}

check_brand() {
  head_ "markalama degerleri"
  ( cd "$WIN_SRC" && sh tools/brand-check.sh ) > "$T/bw" 2>&1
  ssh "$LIN_HOST" "cd '$LIN_SRC' && sh tools/brand-check.sh" > "$T/bl" 2>&1

  # COMMIT/DIRTY zaten ayri kontrol ediliyor; burada marka degerlerine bakiyoruz
  grep -vE '^(COMMIT|DIRTY)=' "$T/bw" > "$T/bw2"; grep -vE '^(COMMIT|DIRTY)=' "$T/bl" > "$T/bl2"
  if diff -q "$T/bw2" "$T/bl2" >/dev/null 2>&1; then
    ok "iki taraf ayni degerleri bildiriyor"
    sed 's/^/        /' "$T/bw2"
  else
    bad "markalama degerleri ayrisiyor"
    diff "$T/bw2" "$T/bl2" | sed 's/^/        /'
  fi
}

check_dist() {
  head_ "uretilmis paketler"

  deb=$(ssh "$LIN_HOST" "ls -t '$LIN_SRC'/*.deb 2>/dev/null | head -1" 2>/dev/null)
  if [ -n "$deb" ]; then
    ssh "$LIN_HOST" "dpkg-deb -f '$deb' Package Version" > "$T/deb" 2>/dev/null
    dp=$(awk -F': *' '/^Package/{print $2}' "$T/deb")
    dv=$(awk -F': *' '/^Version/{print $2}' "$T/deb")
    ok "deb: $dp $dv"
  else
    bad "deb bulunamadi — once tools/build-linux.sh"
    dp=""; dv=""
  fi

  exe="$WIN_SRC/SkyyDesk-Windows.exe"
  [ -f "$exe" ] || exe="/c/ElpoDeskBuild/SkyyDesk-Windows.exe"
  if [ -f "$exe" ]; then
    ep=$(powershell -NoProfile -Command "(Get-Item '$(cygpath -w "$exe" 2>/dev/null || echo "$exe")').VersionInfo.ProductName" 2>/dev/null | tr -d '\r')
    ev=$(powershell -NoProfile -Command "(Get-Item '$(cygpath -w "$exe" 2>/dev/null || echo "$exe")').VersionInfo.FileVersion" 2>/dev/null | tr -d '\r')
    ok "exe: $ep $ev"
  else
    bad "exe bulunamadi — once tools\\build-windows.bat"
    ep=""; ev=""
  fi

  # --- GOMULU ICERIK ---
  # Paket adi ve surum ayni olabilir ama icerikleri ayrisabilir. Asagidakiler
  # dagitilan dosyanin kendisine bakiyor.

  if [ -n "$deb" ]; then
    # Linux: kodun aradigi yollara mi kuruyor (linux_desktop_manager.rs
    # /etc/{app}/ ve /etc/pam.d/{app} ariyor; baska adla kurulursa gozetimsiz
    # oturum sessizce calismaz, PAM gdm yiginina duser).
    # LC_ALL=C uzak tarafta da sart: parity.sh basindaki ayar yalniz
    # yerel kabugu baglar, ssh ile gonderilen komut uzak makinenin
    # yerel ayariyla calisir ve [a-z] araligi Turkce'de yollari yarim okur.
    etc=$(ssh "$LIN_HOST" "LC_ALL=C dpkg-deb -c '$deb' | LC_ALL=C grep -oE './etc/[a-zA-Z0-9._/-]+' | sort -u | tr '\n' ' '" 2>/dev/null)
    # Kod bu iki yeri birbirinden bagimsiz ariyor; ikisi de dogrulanir.
    case "$etc" in
      *"/etc/skyydesk"*) ok "deb: /etc/skyydesk/ dogru" ;;
      *) bad "deb: /etc/skyydesk/ yok -> $etc" ;;
    esac
    case "$etc" in
      *"/etc/pam.d/skyydesk"*) ok "deb: PAM dosyasi dogru adda" ;;
      *) bad "deb: /etc/pam.d/skyydesk yok (PAM gdm'e duser) -> $etc" ;;
    esac

    # Gomulu rendezvous sunucusu ve dis uc nokta
    lin_scan=$(ssh "$LIN_HOST" "rm -rf /tmp/pkchk && mkdir -p /tmp/pkchk && dpkg-deb -x '$deb' /tmp/pkchk 2>/dev/null && \
      grep -rhaoE 'rs\.[a-z]+\.com|api\.rustdesk\.com|api\.telegram\.org|stun\.[a-z]+\.com' /tmp/pkchk 2>/dev/null | sort -u | tr '\n' ' '; rm -rf /tmp/pkchk" 2>/dev/null)
    echo "        deb icerik: ${lin_scan:-bos}"
    case "$lin_scan" in
      *rs.skyydesk.com*) ok "deb: rendezvous bizim" ;;
      *) bad "deb: rs.skyydesk.com gomulu degil" ;;
    esac
    case "$lin_scan" in
      *rustdesk.com*|*telegram*|*stun.*) bad "deb: dis uc nokta gomulu" ;;
      *) ok "deb: dis uc nokta yok" ;;
    esac
  fi

  # Windows: tasinabilir exe sikistirilmis, ham tarama sonuc vermez —
  # sikistirilmamis kutuphane taranir.
  # Kutuphanenin adi marka gecisinde degisti (librustdesk.dll ->
  # libskyydesk.dll) ama bu denetim eski adi aramaya devam etti: yani
  # Windows tarafinin ic taramasi aylardir HIC kosmadi, her seferinde
  # "kutuphane bulunamadi" deyip pariteyi bozuk gosterdi (28.09.2026).
  rel="$WIN_SRC/flutter/build/windows/x64/runner/Release"
  dll="$rel/libskyydesk.dll"
  if [ -f "$rel/librustdesk.dll" ]; then
    bad "exe: eski adli kutuphane cikti klasorunde duruyor (librustdesk.dll)"
  fi
  if [ -f "$dll" ]; then
    win_scan=$(grep -haoE 'rs\.[a-z]+\.com|api\.rustdesk\.com|api\.telegram\.org|stun\.[a-z]+\.com' "$dll" 2>/dev/null | sort -u | tr '\n' ' ')
    echo "        dll icerik: ${win_scan:-bos}"
    case "$win_scan" in
      *rs.skyydesk.com*) ok "exe: rendezvous bizim" ;;
      *) bad "exe: rs.skyydesk.com gomulu degil" ;;
    esac
    case "$win_scan" in
      *rustdesk.com*|*telegram*|*stun.*) bad "exe: dis uc nokta gomulu" ;;
      *) ok "exe: dis uc nokta yok" ;;
    esac
  else
    bad "windows kutuphanesi bulunamadi (once derle): $dll"
  fi

  # Surumler ayni mi (deb 1.4.9 / exe 1.4.9.0 gibi son sifir farki tolere edilir)
  if [ -n "$dv" ] && [ -n "$ev" ]; then
    case "$ev" in
      "$dv"|"$dv".0) ok "surumler uyusuyor ($dv)" ;;
      *) bad "surum ayrisiyor: deb=$dv exe=$ev" ;;
    esac
  fi
}

case "${1:-all}" in
  src)   check_src ;;
  brand) check_brand ;;
  dist)  check_dist ;;
  all)   check_src; check_brand; check_dist ;;
  *) echo "kullanim: $0 {all|src|brand|dist}" >&2; exit 2 ;;
esac

echo
[ "$FAIL" -eq 0 ] && echo "PARITE TAMAM" || { echo "PARITE BOZUK"; exit 1; }

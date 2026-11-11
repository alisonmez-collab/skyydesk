#!/bin/bash
# SkyyDesk masaustu arayuzunu kullanici gibi surer ve her ekrani kaydeder.
#
# NEDEN VAR: surec ve protokol seviyesindeki dogrulamalar ("acildi",
# "baglandi", "ID uretti") ekranda ne yazdigini soylemez. Bu script yazilinca
# alti gercek hata cikti, hicbiri metin taramasiyla bulunamazdi — en cetini,
# yan menudeki markanin 'Elpo' + 'Desk' diye iki parca halinde kurulmasiydi:
# kaynakta "ElpoDesk" diye bir dizge yok, dolayisiyla hicbir marka denetimi
# goremiyordu, ama ekranda acikca yaziyordu.
#
#   ./tools/gui-test.sh          uygulamayi ac, menulerde gez, kaydet
#   ./tools/gui-test.sh --keep   goruntuleri silme (varsayilan zaten saklar)
#
# Gereksinimler: xvfb-run, xdotool, imagemagick (import)
# Ciktilar: /tmp/skyydesk-gui/*.png  — scp ile indirilip GOZLE bakilmali.
#           Script "hata yok" diyebilir; ekranin dogru oldugunu soyleyemez.

set -u
OUT=/tmp/skyydesk-gui
BIN=${SKYYDESK_BIN:-/usr/bin/skyydesk}

if [ "${1:-}" = "--inner" ]; then
  GDK_BACKEND=x11 "$BIN" > "$OUT/app.log" 2>&1 &
  APP=$!

  # Pencerenin CIZILMESINI bekle — surecin var olmasi yetmiyor.
  W=""
  for i in $(seq 40); do
    for w in $(xdotool search --onlyvisible --name '.' 2>/dev/null); do
      [ "$(xdotool getwindowname "$w" 2>/dev/null)" = "SkyyDesk" ] && W="$w"
    done
    [ -n "$W" ] && break
    sleep 1
  done
  if [ -z "$W" ]; then
    echo "HATA: SkyyDesk penceresi acilmadi (${i}s beklendi)"
    tail -15 "$OUT/app.log"
    exit 1
  fi
  echo "pencere bulundu (${i}s)"

  # Bilinen konum + boyut: tiklama koordinatlari ekran goruntusuyle ayni olsun
  xdotool windowmove "$W" 0 0
  xdotool windowsize "$W" 1000 700
  sleep 4
  import -window root "$OUT/00-anasayfa.png" 2>/dev/null

  tap() {  # ad x y dosya bekleme
    printf '  %-16s (%s,%s) -> %s\n' "$1" "$2" "$3" "$4"
    xdotool mousemove "$2" "$3" click 1
    sleep "${5:-3}"
    import -window root "$OUT/$4" 2>/dev/null
  }

  tap "Adres Defteri" 100 250 "01-adres-defteri.png"
  tap "Favoriler"     100 300 "02-favoriler.png"
  tap "Ana Sayfa"     100 200 "03-ana-sayfa.png"
  tap "Ayarlar"       100 645 "04-ayarlar.png" 5
  # Ayarlar acildiktan sonra sol sutun
  tap "  Guvenlik"    75  164 "05-guvenlik.png"
  tap "  Ag"          75  206 "06-ag.png"
  tap "  Hakkinda"    75  332 "07-hakkinda.png"

  echo "hata/panik: $(grep -icE 'error|panic|exception' "$OUT/app.log")"
  kill $APP 2>/dev/null
  sleep 1
  exit 0
fi

for c in xvfb-run xdotool import; do
  command -v "$c" >/dev/null 2>&1 || { echo "gerekli komut yok: $c"; exit 3; }
done
[ -x "$BIN" ] || { echo "kurulu degil: $BIN"; exit 3; }

rm -rf "$OUT"; mkdir -p "$OUT"
rm -rf "$HOME/.config/skyydesk"   # taze kurulum gibi baslasin
timeout 240 xvfb-run -n 77 -s "-screen 0 1000x700x24" bash "$0" --inner
rc=$?

echo
echo "=== uretilen goruntuler ==="
ls -la "$OUT"/*.png 2>/dev/null | awk '{printf "  %-46s %s bayt\n", $9, $5}'
echo
echo "Bunlari indirip GOZLE bak. Bu script ekranin dogru oldugunu dogrulayamaz,"
echo "yalnizca acildigini ve tiklamalarin hata uretmedigini gosterir."
exit $rc

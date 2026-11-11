# Derleme makinesinin yollarini ikiliye sizdirmamak icin ortak ayar.
#
# NEDEN AYRI DOSYA: ayni bayraklar Linux ve Android derlemelerinde gerekiyor.
# Android betiginde hic yoktu ve 28.09.2026'da olculdu: paketteki
# libskyydesk.so icinde kendi kaynak agacimizdan 604 yol duruyordu. Linux
# tarafi kapaliydi, Android acikti -- iki kopya olsaydi biri yine kayardi.
#
# --remap-path-prefix yollari sabit takma adlara cevirir. Goreli yapi korunur
# (panikte hangi dosya oldugu hala okunur), makineye ait bilgi kalmaz.
# Sirasi ONEMLI: ozel olan once yazilir, genel olan sonra.
#
# C tarafina (-ffile-prefix-map) bilerek DOKUNULMUYOR: openssl-sys, OpenSSL'i
# kendi derlerken derleyicinin tam komut satirini kutuphaneye dizgi olarak
# gomuyor ve bayragin esleme kaynagi kendi kaynak agacimiz oldugu icin
# bayragin KENDISI derleme makinesini anlatiyor.

yol_anonim_bayraklari() {
  _kok="${1:-$(pwd)}"
  printf '%s' \
    "--remap-path-prefix=$HOME/.cargo/registry/src=/paketler" \
    " --remap-path-prefix=$HOME/.cargo/git=/paketler-git" \
    " --remap-path-prefix=$_kok=/skyydesk" \
    " --remap-path-prefix=${VCPKG_ROOT:-$HOME/vcpkg}=/kutuphaneler" \
    " --remap-path-prefix=$HOME=/derleme"
}

# Verilen ikilide derleme makinesinin yolu kaldi mi?
# Kaynaga gore ayirir: vcpkg'nin ONCEDEN derlenmis kutuphaneleri yollarini
# kendi derlenislerinde gomdu, bizim derlememiz onlari degistiremez; kendi
# kodumuzda ise tek bir yol bile sizmamali. Tolerans sayisi tutan bir bekci,
# sayinin dogal buyumesiyle anlamini kaybeder.
# Cikis 1 = kendi kodumuzda sizinti var.
yol_denetimi() {
  _dosya="$1"
  [ -f "$_dosya" ] || { echo "  yol denetimi: dosya yok: $_dosya"; return 1; }
  _tum=$(strings -a "$_dosya" 2>/dev/null | grep "$HOME" || true)
  _bizim=$(printf '%s\n' "$_tum" | grep -v "vcpkg/buildtrees" | grep -c "$HOME" || true)
  _onceden=$(printf '%s\n' "$_tum" | grep -c "vcpkg/buildtrees" || true)
  if [ "${_bizim:-0}" -gt 0 ]; then
    printf '%s\n' "$_tum" | grep -v "vcpkg/buildtrees" | head -3 | sed 's/^/    /'
    echo "  HATA: derleme makinesinin yolu $(basename "$_dosya") icine sizmis ($_bizim kez)."
    return 1
  fi
  echo "  -> $(basename "$_dosya"): kendi kodumuzda yol sizintisi yok"
  if [ "${_onceden:-0}" -gt 0 ]; then
    echo "     onceden derlenmis vcpkg kutuphanelerinde $_onceden yol kaldi"
  fi
  return 0
}

# App Store görselleri

App Store Connect'e elle yüklenir (6.5" iPhone). Yükleme ve form adımları:
[[../../../docs/IOS_YAYIN.md]].

| dosya | boyut |
|---|---|
| `tr-TR/images/iphone65/1-2.png` | 2778×1284 (yatay oturum) |
| `tr-TR/images/iphone65/3-6.png` | 1284×2778 |

Uygulama yalnız iPhone (`TARGETED_DEVICE_FAMILY = 1`), iPad görseli yok.

## Üretim

Android görselleri kullanılamaz: iOS'ta alt menüde yalnız Bağlantı ve Ayarlar
var, Android'deki Ekranı Paylaş/Mesajlaş sekmeleri yok (Guideline 2.3.3).

1. Ham kareler TestFlight kurulumundan, gerçek iPhone'da.
2. Dikey karelerde durum çubuğu (saat, pil, "◂ TestFlight") kırpılır; uzak
   masaüstünde görünen kişisel alanlar (tarayıcı yer imleri) bulanıklaştırılır.
   Bu hazırlık elle yapıldı, betikte yok.
3. `magaza-ios.py ekranlar-ios.json <ham> <çıktı>` — Chromium ve ImageMagick
   gerekiyor, Linux derleme makinesinde ikisi de kurulu. Fontları
   sitenin `/var/www/skydesk/assets/fonts` klasöründen alır. Yatay kare 2778×1284
   tuvale metin solda, dikey kare 1284×2778 tuvale metin üstte çizilir; alfa
   kanalı atılır (App Store kabul etmiyor).

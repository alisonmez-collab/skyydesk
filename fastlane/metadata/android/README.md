# Mağaza görselleri

Play listelemesine giden ikon, öne çıkan görsel ve ekran görüntüleri burada.
Yükleme adımlarının tamamı [[../../docs/ANDROID_YAYIN.md]] içinde.

Buradaki iki dil klasörü (`tr-TR`, `en-US`) fastlane'in beklediği düzendir;
Play görselleri dile göre ayrı gösteriyor, o yüzden metin taşıyan görseller
her dilde ayrı üretilir. Bu dosya ikisi için de geçerli — bir dönem aynı
metin iki klasöre kopyalanmıştı, ikisi ayrışmadan tek kaynağa indirildi.

## Durum

| varlık | boyut | durum |
|---|---|---|
| ikon | 512×512 PNG | **hazır** — `*/images/icon.png` |
| öne çıkan görsel | 1024×500 | **hazır** — `*/images/featureGraphic.png` |
| telefon görüntüsü | 9:16 – 16:9, 320–3840 px | **hazır** — sekiz adet, iki dilde |
| tablet | aynı kural | isteğe bağlı |

Buradaki görseller RustDesk'in kendi ikonu ve ekran görüntüleriydi. Başka bir
ürünün görüntüsüyle yayına çıkmak hem ret sebebi hem marka sorunu olduğu için
bırakılmadı, silindi.

## Ekran görüntüsü nasıl üretilir

**Ham kare doğrudan yüklenemez.** Telefonun karesi 1080×2280, en-boy oranı
0,47 — Play'in istediği 9:16 (0,5625) alt sınırının dışında. O yüzden ham kare
1080×1920 bir tuvale yerleştirilir, durum çubuğu ile gezinme çubuğu kırpılır
(saat, pil yüzdesi ve bildirim rozeti mağaza görselinde işe yaramaz).

Bunu yapan araç **site deposundadır** — marka fontları orada, ikinci bir font
kopyası çıkarmamak için:

    SkyyDesk/tools/magaza-gorselleri.py <ekranlar.json> <ham-dizin> <çıktı-dizin>

Chromium'un başsız kipiyle çizer, yani sitedeki harflerin aynısını kullanır
(Barlow Condensed + Geist) ve renkler `CLAUDE.md` §3.1'deki marka değerleridir.
Chromium Linux derleme makinesinde kurulu; Windows tarafında yok.

Başlıklar `*/images/ekranlar.json` içinde, dile göre. Ham kareler şu adlarla
beklenir: `oturum.png`, `arac-cubugu.png`, `izinler.png`, `ayarlar.png`,
`ayarlar-dil.png`, `ayarlar-guvenlik.png`, `oturum-menu.png`.

Sekiz kare, Play'in üst sınırı. İlk üçü yatay (oturum, denetim çubuğu,
oturum menüsü), kalan beşi dikey.

Yatay kare (telefon yan çevrilmişken alınan uzak masaüstü) kendi tuvaline
çizilir: 1920×1080, metin solda. Dikey kare 1080×1920 olur. Play ikisini de
kabul ediyor; hangisinin kullanılacağını ham karenin yönü belirler, ayrıca
bir şey söylemek gerekmez.

Uygulamanın dili görselde göründüğü için her dil ayrı çekilir:
Ayarlar → Dil → English, sonra tur baştan.

## Ham kare çekerken

    adb exec-out screencap -p > oturum.png

Emülatör kullanma: ekran yakalama yolu orada GPU yüzünden siyah ya da beyaz
çiziyor (bu projede ölçüldü), ayrıca uzak oturum inandırıcı görünmüyor.

**Kareye özel veri girmesin.** Son bağlantı listesinde gerçek makine adları
duruyor (`YAZILIM@desktop-...` gibi); bunlar müşteri bilgisidir, mağazaya
konmaz. Bağlanılacak makine olarak gözetimsiz test eşi kullanılır: masaüstü
istemcide kalıcı parola tanımlanmış, açılışta başlayan bir makine.

> Buradaki bağlantı `docs/TARAYICI_TESTI.md` dosyasına gidiyordu; o dosya
> depoda yok. Gözetimsiz eşin kurulum adımları yazılıp dosya eklendiğinde
> bağlantı geri konmalı.

## Ne gösterilecek, bu sırayla

1. **Canlı uzak oturum** — uzak masaüstü telefonda görünüyor. Ürünü satan tek
   kare budur, ilk sırada olmalı.
2. Cihaz listesi, bir kısmı çevrimiçi.
3. Telefon ile bilgisayar arasında dosya aktarımı.
4. İzinler ekranı — hepsi kapalı geliyor.
5. Bağlantı ekranı, kimlik girilmiş.

Çoğu kişi açıklamayı değil görselleri okur; her karenin üstündeki tek satır
bu yüzden var.

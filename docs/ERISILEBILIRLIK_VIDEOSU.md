# Erişilebilirlik belirgin açıklama videosu

Google Play'in erişilebilirlik beyanı formu, uygulamanın kendi arayüzünde
gösterdiği açıklamayı ve kullanıcının onayını kanıtlayan kısa bir video
istiyor. Bu doküman o videonun nasıl çekileceğini anlatır.

Formun tamamı için [ANDROID_YAYIN.md](ANDROID_YAYIN.md) → "Erişilebilirlik
(AccessibilityService)".

## Neden gerekiyor

`isAccessibilityTool` bilerek ayarlanmadı: SkyyDesk engelli kullanıcılara
yardım için tasarlanmış bir araç değil, uzaktan denetim uygulaması. Onu `true`
yapmak beyanı yanlışlamak olur ve Google bunu hesap askıya alınmasına kadar
giden bir ihlal sayıyor. Doğru yol, belirgin açıklama şartını karşılamak — o da
uygulamada var (`ServerModel.showInputWarnAlert`) ve bu video onu belgeliyor.

## Çekim

Kaydı `adb screenrecord` ile almak en temizi; telefonun kendi ekran
kaydedicisi de olur. Aşağıdaki metin, kaydı alacak kişinin Claude Code'a
olduğu gibi yapıştırabileceği bir istemdir.

```
SkyyDesk adlı Android uygulaması için Google Play'e sunulacak bir "belirgin
açıklama" (prominent disclosure) videosu çekeceğiz. Video, uygulamanın
Erişilebilirlik hizmetini neden ve nasıl kullandığını anlatan ekranı ve
kullanıcının onayını gösterecek. Google inceleme ekibi izleyecek.

SENİN GÖREVİN: telefonu adb ile kaydetmek ve videoyu bana dosya olarak vermek.
Ekrana dokunmaları BEN yapacağım — sen sadece kaydı başlat, bitince çek.

ÖN KOŞULLAR
- Android telefon USB ile bağlı, USB hata ayıklama açık
- USB modu "Dosya Aktarımı (MTP)" olmalı; "yalnızca şarj" modunda adb görmez
- Xiaomi/MIUI ise ayrıca "USB üzerinden yükleme" izni de açık olmalı
- SkyyDesk uygulaması telefonda kurulu olmalı (Play dahili testinden ya da
  bana verilen APK'dan). Paket adı: com.elpo.skyydesk
- Başlamadan önce "adb devices" ile cihazın göründüğünü doğrula

KAYIT
adb screenrecord kullan. Varsayılan sınır 180 saniye, bizim çekim ~90 saniye.
Netlik için bit hızını yükselt:

  adb shell screenrecord --bit-rate 8000000 --time-limit 180 /sdcard/skyydesk-disclosure.mp4

Kayıt sırasında bana "başladı" de, ben adımları yapacağım. Ben "bitti"
dediğimde kaydı durdur (Ctrl+C ya da süre dolmasını bekle), sonra:

  adb pull /sdcard/skyydesk-disclosure.mp4
  adb shell rm /sdcard/skyydesk-disclosure.mp4

Dosyayı bana ver ve süresini/boyutunu söyle.

BEN ŞU ADIMLARI YAPACAĞIM (sen sadece kaydediyorsun)
1. Ana ekrandan SkyyDesk'i açarım
2. Alttaki "Ekranı Paylaş" sekmesine geçerim
3. "Giriş Kontrolü" anahtarına dokunurum
4. Açıklama ekranı çıkar — 4-5 saniye hiç dokunmadan beklerim ki metin okunsun
5. "Anladım, ayarları aç" düğmesine basarım
6. Açılan sistem ayarlarında "SkyyDesk Girişi" hizmetini açarım
7. Uygulamaya dönerim ve kısa bir uzak oturumda uzaktan denetimin çalıştığını
   gösteririm

ÖNEMLİ UYARILAR
- Bazı sistem onay pencereleri (özellikle ekran yakalama izni) adb ile
  tıklanamaz, güvenlik gereği enjekte dokunuşları yok sayar. Sorun değil,
  onlara ben fiziksel olarak dokunacağım. Sen "adb shell input tap" kullanmaya
  çalışma, sadece kaydet.
- Xiaomi/MIUI cihazlarda servis başlatılırken MIUI kendi "Diğer izinler"
  sayfasına yönlendirebilir; bu normal, ben hallederim.
- Kayıt bitince videoyu izleyip bana şunları doğrula: açıklama metni okunacak
  kadar net ve yeterince uzun ekranda kalmış mı, onay düğmesine basıldığı
  görünüyor mu.
- Videoda gerçek makine adı, müşteri bilgisi veya gerçek bağlantı kimliği
  görünürse söyle, o bölümü yeniden çekeriz.

Hazır olduğunda "adb devices" çıktısını göster ve kaydı başlat.
```

## Sonrası

**Yükleme.** Videoyu YouTube'a **liste dışı (unlisted)** koyup linki forma
girin. Herkese açık olması gerekmiyor ama linkten erişilebilir olmalı; Google
Drive bağlantıları inceleme sırasında erişim sorunu çıkarabiliyor.

**Süre.** Sınır 3 dakika, 1-2 dakika yeterli.

**7. adım zorunlu değil.** Formun istediği şey açıklama ekranı ve onay; uzak
oturum gösterimi işi sağlama alır ama bağlantı kurulamıyorsa videoyu onun için
bekletmeyin.

**Gizlilik.** İnceleme ekibi videoyu saklıyor. Karede gerçek makine adı,
müşteri bilgisi ya da gerçek bağlantı kimliği olmasın — gözetimsiz bir test
eşi kullanın.

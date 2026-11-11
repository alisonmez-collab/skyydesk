# SkyyDesk — Google Play yayın kontrol listesi

Bu doküman Android uygulamasının Play Console'a çıkışını anlatır. iOS için
[IOS_YAYIN.md](IOS_YAYIN.md).

Mağaza görsellerinin nasıl üretildiği ayrı bir konu:
[fastlane/metadata/android/README.md](../fastlane/metadata/android/README.md).

---

## 1. Bir kereye mahsus hazırlık

### Geliştirici hesabı

ELPO adına **organizasyon** hesabı açın, bireysel değil. Bireysel hesap 12 test
kullanıcısı × 14 gün kapalı test zorunluluğuna tabi; organizasyon hesabı değil.
Organizasyon hesabı **D-U-N-S numarası** istiyor, temini 1–2 hafta sürebilir —
en uzun süren adım bu, ilk başlatılacak iş.

### İmzalama anahtarı

Upload key'i siz üretip **kalıcı olarak saklarsınız**; kaybedilirse uygulama bir
daha güncellenemez.

```
keytool -genkey -v -keystore skyydesk-upload.jks \
        -keyalg RSA -keysize 4096 -validity 10000 -alias upload
```

Sonra `flutter/android/key.properties` (örneği yanında: `key.properties.example`).
Bu dosya ve `.jks` **gitignore'da**, depoya girmez.

Play App Signing zorunlu: Google dağıtım anahtarını kendi tutar, siz yalnız
upload key ile imzalarsınız.

### Yayına çıkmadan hazır olması gerekenler

| Ne | Nerede | Durum |
|---|---|---|
| Gizlilik politikası (TR + EN, KVKK uyumlu) | `skyydesk.com/gizlilik/` | mağaza açıklamasında linkli |
| Hesap silme sayfası | `skyydesk.com/hesap-silme/` | uygulamada hesap girişi var, Play zorunlu tutuyor |
| AGPL kaynak kodu | `skyydesk.com/lisans` | aşağıya bakın |

**AGPL:** Proje AGPL-3.0 lisanslı. Binary dağıtıyorsanız değiştirilmiş sürümün
tam kaynağını kullanıcılara sunmak zorundasınız. Kaynak GitHub'da açık;
yayından **önce** oradaki kaynağın yayınlanan sürümle aynı olduğunu doğrulayın.

---

## 2. Sürüm çıkarmadan önce

### Sürüm numarası

`flutter/pubspec.yaml` içindeki `version: 1.4.9+67` satırı. `+` sonrası
`versionCode` — Play'de **her yükleme için artmak zorunda**, geri gidilemez.

### Yapı zinciri

Bunlar Play politikası gereği bu değerlerde:

| Ayar | Değer | Neden |
|---|---|---|
| `targetSdkVersion` | 36 | Play, 31.08.2026'dan beri Android 16 istiyor (uzatma hakkı 01.11.2026) |
| `compileSdkVersion` | 36 | targetSdk 36'nın gereği |
| AGP | 8.10.1 | compileSdk 36'yı destekleyen ilk sürüm; 8.9 API 35'te tavan yapıyor |
| Gradle | 8.11.1 | AGP 8.10'un asgarisi |
| `ndkVersion` | 28.2.13676358 (r28c) | 16 KB sayfa boyutu; CI'daki `NDK_VERSION` ile aynı olmalı |
| Flutter (Android) | 3.44.0 | `ANDROID_FLUTTER_VERSION`; 3.24.5 API 36'yı taşımıyor |

`ANDROID_FLUTTER_VERSION` masaüstündeki `FLUTTER_VERSION`'dan **ayrıdır** ve
onun Windows 7 kısıtını etkilemez.

### Yapı

```
cd flutter && ./build_android.sh
```

`flutter build appbundle` çıktısı (`.aab`) Play'e yüklenir. **APK kabul
edilmiyor** — yeni uygulamalar 2021'den beri App Bundle zorunlu.

### Yüklemeden sonra Play Console'da kontrol edin

- **16 KB sayfa boyutu uyarısı** — AAB'yi yükleyince Console söyler. Uyarı
  varsa yerel NDK sürümü `ndkVersion` ile uyuşmuyor demektir.
- **Desteklenen cihaz sayısı** — beklenmedik düşüş, ABI ya da izin
  filtrelemesine işaret eder.

---

## 3. Mağaza listelemesi

Metinler ve görseller `fastlane/metadata/android/{tr-TR,en-US}/` altında,
Play Console'a elle kopyalanır. Limitler: başlık ≤30, kısa açıklama ≤80,
tam açıklama ≤4000 karakter.

Görseller: ikon 512×512, öne çıkan görsel 1024×500, telefon ekran görüntüsü
9:16–16:9 arası, en az 2 en fazla 8 adet.

---

## 4. Beyan formları — asıl zorluk burası

### Erişilebilirlik (AccessibilityService)

Android cihazın uzaktan kontrolü `InputService` üzerinden bu API ile yapılıyor.
Android'in girdi enjekte etmek için başka yolu yok. Play'de yasak değil
(TeamViewer QuickSupport, AnyDesk aynı şekilde yayında) ama:

- Console'da **Accessibility API kullanım beyanı** formu doldurulacak
- Uygulama içinde **belirgin açıklama (prominent disclosure)** ekranı gerekiyor
  — var, `ServerModel.showInputWarnAlert`
- Form bir **demo video** linki istiyor; çekim yönergesi
  [ERISILEBILIRLIK_VIDEOSU.md](ERISILEBILIRLIK_VIDEOSU.md) içinde
- İnceleme haftalara uzayabilir — takvimi buna göre kurun

Formdaki cevaplar:

| soru | cevap | dayanağı |
|---|---|---|
| Kullanım amacı | yalnız **Uygulama işlevselliği** | başka hiçbir amaç yok |
| Hassas veri topluyor/paylaşıyor mu | **Hayır** | `onAccessibilityEvent` boş; `InputService` içinde tek bir FFI ya da ağ çağrısı yok. `canRetrieveWindowContent` sadece odaktaki alana metin yazmak için: mevcut metin ve imleç konumu anlık okunup `ACTION_SET_TEXT` ile geri yazılıyor, hiçbir yere gönderilmiyor. Ekran görüntüsü karşı tarafa bu API'den değil, ayrıca onaylanan MediaProjection'dan gidiyor. |
| `isAccessibilityTool` | **ayarlanmadı, öyle kalmalı** | SkyyDesk engellilik aracı değil; `true` demek yanlış beyan olur |

### Foreground service tipleri

Beyan edilen iki tip ve gerekçeleri:

- `mediaProjection` — uzak oturum için ekran yakalama. Oturum sesi
  (AudioPlaybackCapture) da bu tipin altında.
- `microphone` — yalnız sesli görüşme sırasında. Servis iki tipi birlikte
  **beyan** ediyor ama ikisini birden **üstlenmiyor**; mikrofon tipi
  `startForeground`'a yalnız görüşme başladığında ekleniyor
  (`MainService.startForegroundWithTypes()`).

### Diğer izinler

Her biri için Console'da gerekçe istenir:

| İzin | Gerekçe |
|---|---|
| `SYSTEM_ALERT_WINDOW` | oturum sırasındaki yüzen kontrol penceresi |
| `RECEIVE_BOOT_COMPLETED` | gözetimsiz erişim, cihaz yeniden başladıktan sonra |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | uzun oturumda bağlantının kesilmemesi — Play'in kabul listesi dar, en riskli madde |
| `RECORD_AUDIO` | oturum sesi ve sesli görüşme |

**`MANAGE_EXTERNAL_STORAGE` bilerek kaldırıldı.** Play'in "Tüm Dosyalara Erişim"
politikası bu izni dosya yöneticisi, yedekleme, antivirüs ve doküman yönetimi
kategorilerine veriyor; uzaktan erişim o listede yok. Geri eklemeyin.

### Data Safety

Uygulama ekran görüntüsü, ses ve dosya **aktarıyor** ama bunları sunucuda
**saklamıyor**. Formda bu ayrımı net yapın: taşınan içerik kullanıcı verisidir,
"toplanan veri" değildir. Toplanan tek şey hesap girişindeki e-posta.
iOS'taki `PrivacyInfo.xcprivacy` ile aynı çizgide kalın.

---

## 5. Yayın öncesi cihaz testi

Emülatör yetmez — ekran yakalama yolu emülatörde GPU yüzünden siyah/beyaz
çiziyor. Gerçek cihazda, **Android 14, 15 ve 16** ayrı ayrı:

- [ ] Uzak oturum başlatma (MediaProjection onayı → görüntü akıyor)
- [ ] Oturum sırasında bildirim çubuğundan "Paylaşımı durdur" → uygulama düzgün
      toparlıyor, çökmüyor
- [ ] İkinci oturum: onayın yeniden istenmesi ve bağlanabilme
- [ ] Sesli görüşmeye geçiş ve geri çıkış
- [ ] `RECORD_AUDIO` reddedilmiş cihazda oturum yine de açılıyor
- [ ] Cihazı yeniden başlat → gözetimsiz erişim çalışıyor
- [ ] Edge-to-edge: durum çubuğu ve gezinme çubuğu altındaki içerik, açık ve
      koyu temada ayrı ayrı — ikonlar okunuyor mu, alt satır kesiliyor mu

Son madde Android 15+ için yeni: sistem çubukları artık uygulamanın üstüne
biniyor ve API 36'da bundan çıkış yolu yok.

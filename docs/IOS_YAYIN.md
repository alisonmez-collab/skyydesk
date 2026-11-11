# SkyyDesk — App Store yayın kontrol listesi

Android için [ANDROID_YAYIN.md](ANDROID_YAYIN.md).

---

## 1. Bir kereye mahsus hazırlık

### Apple Developer Program

ELPO adına organizasyon üyeliği (yıllık $99). Organizasyon üyeliği de
**D-U-N-S numarası** istiyor — Play tarafıyla aynı numara kullanılır, ikisini
paralel başlatın.

### Team ID

Ekip kimliği depoda tutulmuyor. Bir kez:

```
cp flutter/ios/Flutter/Signing.xcconfig.example flutter/ios/Flutter/Signing.xcconfig
```

İçindeki `DEVELOPMENT_TEAM = XXXXXXXXXX` satırına gerçek Team ID'yi yazın
(developer.apple.com → Account → Membership Details → Team ID). Dosya
gitignore'da; Android'deki `key.properties` ile aynı düzen.

`project.pbxproj` artık `DEVELOPMENT_TEAM` taşımıyor — değer yalnız buradan
gelir. Daha önce üç yapılandırmada da RustDesk'in ekip kimliği yazılıydı.

### App ID

`com.elpo.skyydesk` bundle ID'sini App Store Connect'te kaydedin. Uygulama
şu an hiçbir özel yetenek (capability) kullanmıyor: `Runner.entitlements`
bilerek boş. Push bildirim ya da başka bir yetenek eklendiğinde hem oraya hem
App ID'ye eklenmesi gerekir.

---

## 2. Yapı

```
cd flutter && ./build_ios.sh
```

Betik `Signing.xcconfig`'ten Team ID'yi okur, `exportOptions.plist`'i
şablondan üretir ve `flutter build ipa --release` çalıştırır. Team ID
girilmemişse anlamlı bir hatayla durur.

`signingStyle: automatic` kullanılıyor, yani profil adı hiçbir yerde sabit
değil — Xcode doğru dağıtım profilini kendisi seçer.

---

## 3. Gizlilik ve uyumluluk

### Privacy manifest

`flutter/ios/Runner/PrivacyInfo.xcprivacy` — Apple 01.05.2024'ten beri zorunlu
tutuyor. Dosya Xcode projesinin **Copy Bundle Resources** fazına eklidir; bir
süre diskte duruyor ama pakete girmiyordu.

App Privacy formuyla birebir aynı olmalı. Beyan edilen üç tür, hepsi hesaba
bağlı, izleme yok, amaç yalnız uygulama işlevi: e-posta (hesap), cihaz kimliği
(SkyyDesk ID), diğer kullanım verisi (bağlantı kayıtları). Uzak oturumda taşınan ekran, ses ve dosyalar
kullanıcı içeriğidir, sunucuda saklanmaz — "toplanan veri" değildir. Aynı
ayrımı Privacy Nutrition Label formunda da yapın.

### İhracat uyumluluğu

Oturumlar libsodium/NaCl ile uçtan uca şifreli; bu, Apple'ın muaf saydığı dar
kategorilerin (yalnız kimlik doğrulama, DRM, HTTPS) dışında kalıyor. Yani beyan
"muaf olmayan şifreleme kullanıyor".

Bu beyan `Info.plist`'te **yapılmıyor**: `ITSAppUsesNonExemptEncryption`
anahtarı bilerek yok. Anahtar `true` iken App Store Connect yüklemede
`ITSEncryptionExportComplianceCode` da istiyor ve yüklemeyi 90592 ile
reddediyor; o kod ancak App Store Connect'e yüklenip onaylanan şifreleme
belgesiyle veriliyor. `false` yazmak ise yanlış beyan olur.

Anahtar yokken her build TestFlight'ta **Missing Compliance** ile bekler.
Build başına bir kez:

- *What type of encryption algorithms does your app implement?* →
  **Standard encryption algorithms instead of, or in addition to, using or
  accessing the encryption within Apple's operating system**
- *Is your app going to be available on the App Store in France?* → **No**.
  Fransa, ANSSI beyanı istediği için Pricing and Availability'de kapalı
  (Çin de kapalı: ICP lisansı yok).

Ayrıca:

1. BIS'e yıllık **self-classification report** (5D992.c) gönderin.
2. Fransa açılacaksa önce ANSSI beyanı.

Bu adım hukuk danışmanınızla teyit edilmeli; kod tarafında yapılacak başka bir
şey yok.

### AGPL ve App Store

Dikkat edilmesi gereken bir gerilim var. Apple'ın kullanım şartları (cihaz
sayısı sınırı, DRM) GPL ailesinin "ek kısıtlama getirilemez" maddesiyle
çelişiyor; VLC bu yüzden App Store'dan kaldırılmıştı. RustDesk kendi
uygulamasını yayınlayabiliyor çünkü telif hakkı sahibi ve kendine istisna
tanıyabiliyor — ELPO telif sahibi değil.

Ayrıca App Store'da zaten RustDesk yayında; aynı kod tabanının farklı isimle
yüklenmesi incelemede **Guideline 4.1 (Copycats)** olarak işaretlenebilir.
İtiraz için hazırlıklı olun: ELPO'nun kurumsal kimliği, kendi sunucu
altyapısı (`rs.skyydesk.com`, kendi anahtarı) ve farklılaşan özellikler.

Google Play'de bu sorun yok; Play şartları GPL ile çelişmiyor.

---

## 4. Codemagic ile yükleme (asıl yol)

Mac olmadan yayın Codemagic'ten yapılıyor; tanım depo kökündeki
`codemagic.yaml`. AX_Automation_Mobil ile aynı düzen: imzalama Codemagic'e
eklenmiş App Store Connect API anahtarıyla (`ELPO_ASC_KEY`) otomatik,
sertifika ve profil depoda yok. `Signing.xcconfig` bu yolda gerekmez.

Bir kereye mahsus:

1. developer.apple.com → Identifiers → `com.elpo.skyydesk` App ID'si.
2. App Store Connect → Uygulamalar → **+** → aynı bundle ID ile uygulama kaydı.
3. Codemagic → Add application → TFS deposu (AX_Automation_Mobil nasıl
   eklendiyse), yapılandırma olarak `codemagic.yaml`.

Sonra her sürüm: `pubspec.yaml`'da `version` arttır, pushla, Codemagic'te
`ios-appstore` iş akışını başlat. Derleme TestFlight'a düşer; App Store'a
gönderim App Store Connect'ten elle.

İş akışı Rust çekirdeğini de derliyor (vcpkg → flutter_rust_bridge → cargo →
`flutter build ipa`). İlk derleme vcpkg yüzünden uzun sürer, sonrakilerde
önbellek devreye girer.

### GitHub Actions

GitHub kullanılmıyor; aşağıdaki not upstream'den kalan iş akışı için.

GitHub Actions **imzalı IPA üretmiyor**. `flutter-build.yml` içindeki iOS işi
`--no-codesign` ile derliyor; bu Flutter'da arşivi kurup export adımını
atlıyor, yani `build/ios/ipa/` hiç oluşmuyor. İş artık imzasız
`Runner.xcarchive`'ı yapı doğrulaması olarak yüklüyor.

Gerçek yüklemeyi CI'a taşımak için üçü de sır olarak saklanacak şunlar gerekir:

- Apple Distribution sertifikası (`.p12`) ve parolası
- App Store Connect API anahtarı (`.p8`, key id, issuer id)
- Anahtarlığı runner'da kuran bir adım (`apple-actions/import-codesign-certs`
  ya da fastlane `match`)

Mac'te elle yayın da mümkün: `flutter/build_ios.sh` → Xcode Organizer ya da
`xcrun altool`.

---

## 5. Mağaza listelemesi

Android tarafındaki `fastlane/metadata/android/` yalnız Play içindir; App
Store görselleri **henüz üretilmedi**. Gerekenler:

- 6.5" iPhone ekran görüntüleri (1284×2778, zorunlu). Android görselleri
  kullanılamaz: iOS'ta alt menüde yalnız Bağlantı ve Ayarlar var.
- iPad görüntüsü gerekmiyor: uygulama şimdilik yalnız iPhone
  (`TARGETED_DEVICE_FAMILY = 1`); iPad'de iPhone uygulaması olarak çalışır.
  Tam iPad desteği açılırsa 13" iPad görüntüleri de gerekecek.
- Açıklama metni Play'dekinden uyarlanabilir, ancak Play'e özgü ifadeler
  (Erişilebilirlik servisi anlatımı gibi) iOS'ta karşılıksız — iOS istemci
  tarafı, kontrol edilen taraf değil.

---

## 6. Yayın öncesi kontrol

- [ ] `Signing.xcconfig` gerçek Team ID ile dolu
- [ ] `build_ios.sh` hatasız tamamlanıyor
- [ ] Xcode Organizer'da arşiv "Validate App" ile geçiyor
- [ ] TestFlight'a yükleniyor ve gerçek cihazda açılıyor
- [ ] QR kod tarama (kamera izni) ve galeriden QR okuma (foto izni) çalışıyor
- [ ] `skyydesk://` derin bağlantısı açılıyor
- [ ] Uygulama adı ve ikonu her yerde SkyyDesk — RustDesk kalıntısı yok

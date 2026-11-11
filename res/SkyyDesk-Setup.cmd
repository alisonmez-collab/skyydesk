@echo off
setlocal enabledelayedexpansion
title SkyyDesk Kurulum

rem SkyyDesk'i indirir, gerekiyorsa gunceller ve sessizce kurar.
rem
rem NEDEN CMD: tarayiciyla inen .exe'ye Windows "internetten geldi" (MOTW)
rem damgasi basar; SmartScreen imzasiz exe'de "bilgisayarinizi korudu" uyarisi
rem cikarir. curl ile inen dosyada o damga olusmaz. Asil cozum kod imzalama
rem (task #43); o zamana kadar bu dosya koprü.
rem
rem NEDEN SURUM KARSILASTIRMASI + SESSIZ KURULUM: onceki surum, SkyyDesk kuruluysa
rem GUNCELLEMEYI ATLIYORDU — yama yayinlansa bile cift tiklama eski surumu
rem aciyor, calisan servis hic degismiyordu. 12.08.2026'da saatlerce buna
rem takildik: kullanici defalarca yeni surumu "kurdu" ama sunucu olcumu hep eski
rem kodu gordu. Artik surum DAMGASI karsilastiriliyor, farkli ise indirip ESKI
rem SERVISI DURDURUP sessizce (--silent-install) yeniden kuruyor.
rem
rem NEDEN BOYUT DEGIL DAMGA: bir donem paket BOYUTU karsilastiriliyordu ve
rem packer'in ciktisi iki surumde de ayni boyda cikinca ("23683072") betik
rem "guncelim" deyip uygulamayi aciyordu. Uygulama ise damgaya bakip hakli
rem olarak "guncelleme var" diyor ve betigi tekrar cagiriyordu: uygulama ->
rem betik -> uygulama, sonsuz dongu. Kurulum hic olmuyor, yukseltme onayi hic
rem cikmiyor, makine sadece durmadan aciliyor (15.08.2026, sahada ve testte).
rem
rem BU BETIK ARTIK OTOMATIK GUNCELLEMENIN PARCASI DEGIL. Kurulu makineyi servis
rem kendisi gunceller (src/updater.rs) -- servis LOCAL SYSTEM oldugu icin ne
rem yonetici onayi cikar ne de siyah bir pencere. Bu dosya iki is icin duruyor:
rem siteden indirip ILK KEZ kuran kisi, ve bir sey bozulursa elle kurtarma.

set "URL=https://skyydesk.com/downloads/SkyyDesk-Windows.exe"
set "SURUMURL=https://skyydesk.com/downloads/surum.txt"
set "HEDEF=%TEMP%\SkyyDesk-Windows.exe"
set "KURULU=%ProgramFiles%\SkyyDesk\SkyyDesk.exe"
set "KILIT=%LOCALAPPDATA%\SkyyDesk\.kurulum"

rem Zorla yeniden kurmak icin: SkyyDesk-Setup.cmd /kur
if /i "%~1"=="/kur" goto :indir
if /i "%~1"=="/install" goto :indir

if not exist "%KURULU%" goto :indir

rem Sunucudaki damga ("1.4.9 2026-08-15 04:42").
set "UZAK="
for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "try{(Invoke-WebRequest -Uri '%SURUMURL%' -UseBasicParsing -TimeoutSec 10).Content.Trim()}catch{}"`) do set "UZAK=%%L"

rem Kurulu surumun damgasi: uygulamanin kendisine soruluyor. Tek dogru kaynak
rem odur; yanina yazilan bir isaret dosyasi kurulum yarida kalirsa yalan soyler.
set "YERLI="
for /f "usebackq delims=" %%L in (`""%KURULU%" --version" 2^>nul`) do set "YERLI=%%L"
for /f "usebackq delims=" %%L in (`""%KURULU%" --build-date" 2^>nul`) do set "YERLI=!YERLI! %%L"

if not defined UZAK goto :baslat
if "%UZAK%"=="!YERLI!" goto :baslat
goto :indir

:baslat
echo.
echo   SkyyDesk guncel, baslatiliyor...
echo.
start "" "%KURULU%"
timeout /t 2 >nul
exit /b 0

:indir
rem YETKIYI BURADA ISTIYORUZ.
rem
rem "--silent-install" kendisi yukseltme ISTEMIYOR (platform/windows.rs
rem install_me icinde run_uac/elevate yok). Yetkisiz calisinca Program Files'a
rem yazamiyor ve sessizce dusuyor: onay penceresi hic cikmiyor, kurulum hic
rem olmuyor, ekranda "Kuruluyor, uygulama birazdan acilacak" yazisi oylece
rem kaliyor. 15.08.2026'da sahada tam bunu gorduk. Yukseltmeyi betik istiyor;
rem boylece taskkill, kopyalama ve servis kurulumu da yetkiyle calisiyor.
rem
rem Kurulum yolu icin gecerli; "guncel, baslatiliyor" yolunda yetki istenmez --
rem uygulama kullanicinin kendi haklariyla acilmali.
net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Kurulum icin yonetici izni gerekiyor. Cikan pencerede Evet deyin.
  echo.
  powershell -NoProfile -Command "try{Start-Process -FilePath '%~f0' -ArgumentList '/kur' -Verb RunAs}catch{exit 1}"
  if errorlevel 1 (
    echo.
    echo   Izin verilmedi, kurulum yapilmadi.
    echo.
    timeout /t 5 >nul
  )
  exit /b 0
)

rem SUREN BIR KURULUMUN USTUNE GIRME.
rem
rem Asagida once butun SkyyDesk sureclerini olduruyoruz. Kurulumu yapan surecin
rem adi da SkyyDesk.exe oldugu icin, ikinci bir kopya calisirsa birincinin
rem kurulumunu tam ortasinda olduruyordu; hicbiri bitmiyor, uygulama surekli
rem kapanip aciliyordu (15.08.2026 sahada yasandi). Kilit dosyasi 5 dakika
rem tazeyse bu kopya cekiliyor.
if exist "%KILIT%" (
  set "YAS="
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try{[int]((Get-Date)-(Get-Item '%KILIT%').LastWriteTime).TotalSeconds}catch{99999}"`) do set "YAS=%%A"
  if defined YAS if !YAS! LSS 300 (
    echo.
    echo   Kurulum zaten suruyor, bu kopya kapaniyor.
    echo.
    timeout /t 3 >nul
    exit /b 0
  )
)
if not exist "%LOCALAPPDATA%\SkyyDesk" mkdir "%LOCALAPPDATA%\SkyyDesk" >nul 2>&1
>"%KILIT%" echo kuruluyor

echo.
echo   SkyyDesk - Uzaktan Erisim
echo   ------------------------
echo.
echo   Indiriliyor...
echo.

if exist "%HEDEF%" del /q "%HEDEF%" >nul 2>&1

rem curl Windows 10 1803 ve sonrasinda hazir gelir; yoksa PowerShell'e dusuyoruz.
where curl.exe >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest -Uri '%URL%' -OutFile '%HEDEF%' -UseBasicParsing"
) else (
  curl -L --fail --progress-bar -o "%HEDEF%" "%URL%"
)

if not exist "%HEDEF%" goto :hata

rem Kisa dosya = indirme yarim kalmis demektir; calistirip hata almaktansa soyle.
for %%F in ("%HEDEF%") do set "BOYUT=%%~zF"
if !BOYUT! LSS 1000000 goto :hata

echo.
echo   Indirildi (!BOYUT! bayt). Eski surum kapatiliyor...
echo.

rem Calisan eski servis/surec kurulumu engelliyor ve dosyalari kilitliyordu;
rem ayrica ayni kimlige iki surec kaydolup baglanan kisi eski surumun parola
rem ekraniyla karsilasiyordu (07.08.2026). Butun olasi marka adlarini durdur,
rem sonra sureclerini oldur. Onceki surum yalniz SkyyDesk/SkyDesk'i durduruyordu;
rem baska adla kurulu eski bir servis kalmissa gozden kaciyordu.
for %%S in (SkyyDesk SkyDesk FixDesk ElpoDesk RustDesk) do net stop %%S >nul 2>&1
for %%P in (SkyyDesk.exe SkyDesk.exe FixDesk.exe ElpoDesk.exe rustdesk.exe RuntimeBroker_rustdesk.exe) do taskkill /f /im %%P >nul 2>&1
timeout /t 3 >nul

echo   Sessiz kuruluyor (yonetici onayi isteyebilir)...
echo.
rem --silent-install packer'dan icteki exe'ye gecer (dogrulandi: libs/portable
rem main.rs:200-209), exe servisi UAC ile kurar (core_main.rs:409). Boylece
rem kullanici arayuzde "Kur"a tiklamak zorunda kalmaz; eski servis gercekten
rem yenisiyle degisir.
start "" "%HEDEF%" --silent-install

rem Kurulan surumun ne oldugunu ayrica bir yere yazmiyoruz: dogru kaynak
rem uygulamanin kendisi ("SkyyDesk.exe --build-date"). Yanina yazilan isaret
rem dosyasi, kurulum yarida kalirsa "kuruldu" diye yalan soyler.

rem Kurulum bitince uygulamayi KENDISI acsin; kullanici elle baslatmasin.
rem DIKKAT: exe'nin VAR olmasi kurulumun bittigi anlamina gelmez — guncellemede
rem eski exe zaten vardir ve --silent-install onu DEGISTIRIRKEN acmak dosya
rem kilidi cakismasi yaratir, kurulumu bozar. Kurulumun bittiginin kesin
rem isareti: servisin YENIDEN calisir duruma gelmesi (kurulum en son servisi
rem baslatir; biz yukarida durdurmustuk). Onu bekle, sonra arayuzu ac.
rem Metin "onay verin" diyordu ama onay penceresi HER ZAMAN cikmiyor (surec
rem zaten yetkiliyse cikmaz). Cikmayinca kullanici bekledigi seyi bekliyor.
echo   Kuruluyor, uygulama birazdan acilacak. Yonetici onayi cikarsa Evet deyin.
set "_bek=0"
:beklekurulum
timeout /t 2 >nul
sc query SkyyDesk 2>nul | find "RUNNING" >nul 2>&1
if not errorlevel 1 goto :kurulumbitti
set /a _bek+=1
if !_bek! lss 30 goto :beklekurulum
:kurulumbitti
rem Servis kalkti = dosyalar yerinde. Kucuk bir pay verip arayuzu ac.
timeout /t 2 >nul
del /q "%KILIT%" >nul 2>&1
rem Arayuz explorer uzerinden aciliyor: bu betik yetkiyle calisiyor ve "start"
rem ile acilan uygulama da yetkili olurdu. Explorer oturumu acan kullanicinin
rem hakkiyla calistigi icin uygulama normal kullanici olarak baslar.
if exist "%KURULU%" explorer.exe "%KURULU%"
exit /b 0

:hata
del /q "%KILIT%" >nul 2>&1
echo.
echo   HATA: Indirilemedi.
echo.
echo   Kontrol edin:
echo     - Internet baglantisi
echo     - Kurum guvenlik duvari skyydesk.com adresini engelliyor olabilir
echo.
echo   Elle indirmek icin: %URL%
echo.
pause
exit /b 1

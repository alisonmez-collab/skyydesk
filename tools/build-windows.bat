@echo off
setlocal enabledelayedexpansion
rem SkyDesk - Windows (tasinabilir .exe) derlemesi.
rem
rem Linux karsiligi tools/build-linux.sh. Ayni kaynak agacindan, ayni sirayla:
rem once Rust kutuphanesi, sonra Flutter kabugu, sonra platformun paketi.
rem
rem   tools\build-windows.bat          derle ve paketle
rem   tools\build-windows.bat --check  sadece on kosullari dogrula

set "ROOT=%~dp0.."
pushd "%ROOT%" || exit /b 1

set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
set "FLUTTER_BIN=C:\ElpoDeskBuild\flutter\bin"
set "PATH=%USERPROFILE%\.cargo\bin;%FLUTTER_BIN%;C:\Program Files\LLVM\bin;%PATH%"
rem Is sayisi disaridan verilebilir: kullanicinin makinesinde calisirken
rem dusuk tutulup makine agirlastirilmiyor (11.08.2026 bir kez yasandi).
if not defined CARGO_BUILD_JOBS set "CARGO_BUILD_JOBS=6"
set "RELDIR=flutter\build\windows\x64\runner\Release"

set "VCPKG_DIR=C:\ElpoDeskBuild\vcpkg"
set "VCPKG_INSTALLED=%VCPKG_DIR%\installed\x64-windows-static"

echo.
echo === on kosullar
if not exist "%VCVARS%" ( echo HATA: MSVC ortami yok: %VCVARS% & popd & exit /b 1 )
echo   msvc     %VCVARS%
for %%C in (cargo.exe flutter.bat python.exe) do (
  where %%C >nul 2>&1 || ( echo HATA: %%C bulunamadi & popd & exit /b 1 )
  echo   %%C bulundu
)
rem Linux'taki pkg-config kontrolunun karsiligi: kutuphaneler gercekten orada mi
for %%L in (opus.lib vpx.lib yuv.lib aom.lib) do (
  if not exist "%VCPKG_INSTALLED%\lib\%%L" (
    echo HATA: %%L yok: %VCPKG_INSTALLED%\lib
    echo        duzeltme: %VCPKG_ROOT%\vcpkg install opus vpx libyuv aom --triplet x64-windows-static
    popd & exit /b 1
  )
  echo   %%L bulundu
)
rem Donanim kodlama (NVENC / AMF / Quick Sync) FFmpeg'e bagli. Eksikse
rem hwcodec ozelligi baglanma asamasinda kopuyor; sebebi orada anlasilmiyor.
for %%L in (avcodec.lib avformat.lib avutil.lib libmfx.lib) do (
  if not exist "%VCPKG_INSTALLED%\lib\%%L" (
    echo HATA: %%L yok: %VCPKG_INSTALLED%\lib
    echo        duzeltme: %VCPKG_DIR%\vcpkg install "ffmpeg[core,amf,nvcodec,qsv]" mfx-dispatch ^
--triplet x64-windows-static --overlay-ports=%CD%\res\vcpkg
    popd & exit /b 1
  )
  echo   %%L bulundu
)
if not exist "%VCPKG_INSTALLED%\include\opus\opus_multistream.h" (
  echo HATA: opus basliklari yok: %VCPKG_INSTALLED%\include\opus
  popd & exit /b 1
)
echo   opus basliklari bulundu
if "%~1"=="--check" ( echo on kosullar tamam & popd & exit /b 0 )

call "%VCVARS%" >nul || ( echo HATA: vcvars64 basarisiz & popd & exit /b 1 )

rem vcvars64 kendi VCPKG_ROOT'unu export ediyor ve Visual Studio ile gelen bos
rem vcpkg'yi isaret ediyor. opus/vpx/libyuv bizim kopyamizda oldugu icin
rem degiskeni vcvars'tan SONRA yaziyoruz — once yazilirsa eziliyor ve
rem magnum-opus "opus_multistream.h bulunamadi" ile duser.
set "VCPKG_ROOT=%VCPKG_DIR%"
echo   vcpkg    %VCPKG_ROOT%

rem SURUM DAMGASI BURADA BIR KEZ BELIRLENIR VE SABIT KALIR.
rem
rem Onceden damgayi build.rs her derlemede "simdi" olarak yeniden yaziyordu.
rem Bir paketlemede Rust birden cok kez derlendigi icin exe'nin icindeki tarih
rem ile paketten sonra uretilen surum.txt farkli cikabiliyordu; sunucudaki
rem damga kurulu surumden yeni gorunuyor, istemci durmadan kurulum baslatiyordu
rem (15.08.2026, sahada: makine "durmadan basliyor, acilmiyor"). Damga tek
rem yerden geliyor artik: hem exe'nin ici hem surum.txt bu degiskenden.
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "(Get-Date).ToString('yyyy-MM-dd HH:mm')"`) do set "SKYDESK_BUILD_DATE=%%D"
if not defined SKYDESK_BUILD_DATE ( echo HATA: derleme damgasi uretilemedi & popd & exit /b 1 )
echo   damga    %SKYDESK_BUILD_DATE%

echo.
echo === markalama degerleri
rem Bu denetim CALISMIYORDU ve kimse fark etmedi: cmd'nin PATH'inde bash da sh
rem de yok, iki cagri da "is not recognized" verip geciyordu. Ustelik ciktisi
rem yalnizca EKRANA basiliyordu — Linux tarafinda ayni degerler derlemeyi
rem dusuruyor, Windows'ta hicbir sey olmuyordu. Urune bize ait olmayan bir
rem adres girseydi Windows paketi onu sessizce tasiyacakti (09.08.2026).
set "SH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "SH=%ProgramFiles%\Git\bin\bash.exe"
if not defined SH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "SH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined SH if exist "%ProgramFiles%\Git\usr\bin\sh.exe" set "SH=%ProgramFiles%\Git\usr\bin\sh.exe"
if not defined SH ( echo HATA: markalama denetimi icin bash bulunamadi ^(Git for Windows^) & popd & exit /b 1 )

set "BRANDOUT=%TEMP%\skyydesk-brand.txt"
"%SH%" tools/brand-check.sh > "%BRANDOUT%" 2>&1 || ( echo HATA: markalama denetimi kosmadi & type "%BRANDOUT%" & popd & exit /b 1 )
type "%BRANDOUT%"

rem Linux'takiyle ayni kapilar. Biri tutmazsa derleme duser.
call :bgate "FOREIGN_ENDPOINTS=yok" "urun bize ait olmayan bir adrese cikiyor" || ( popd & exit /b 1 )
call :bgate "APP_NAME_RAW.*SkyyDesk" "APP_NAME SkyyDesk degil" || ( popd & exit /b 1 )
call :bgate "RENDEZVOUS.*rs\.skyydesk\.com" "rendezvous sunucusu bizim degil" || ( popd & exit /b 1 )
call :bgate "STALE_BRAND=yok" "arayuzde eski marka kalintisi" || ( popd & exit /b 1 )
call :bgate "WINRES_PRODUCT.*SkyyDesk" "dosya ozelliklerindeki urun adi yanlis" || ( popd & exit /b 1 )

echo.
echo === yetim dosya denetimi
rem Paketlenen dizinde git'in yok saydigi bir dosya varsa iki makine farkli
rem icerik dagitir: dosya depoda olmadigi icin digerine hic gitmez, ama
rem pubspec "assets/" dizinini toptan aldigi icin paketin icine girer.
rem Boyle bir dosya (icon.svg.rustdesk-bak) gercekten sadece bu makinede
rem duruyordu ve yalnizca Windows paketine giriyordu.
for /f "delims=" %%O in ('git status --porcelain --ignored flutter/assets res 2^>nul ^| findstr /b "!!"') do (
  echo HATA: paketlenen dizinde git'in gormedigi dosya var: %%O
  popd & exit /b 1
)
echo   -^> yetim dosya yok

echo.
echo === surum damgasi tazeleniyor
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\stamp-version.ps1" || ( echo HATA: surum damgasi yazilamadi & popd & exit /b 1 )

echo.
echo === 1/3 SkyyDesk cekirdegi
rem hwcodec: NVENC / AMF / Quick Sync ile donanimda kodlama. Kapaliyken her
rem kare karsi makinenin islemcisinde yazilimla kodlaniyordu ve esler
rem yetenek olarak "h264:false h265:false" bildiriyordu — tarayici tarafi da
rem ister istemez AV1'e dusuyor, ki yazilimla cozmesi en pahali olan o.
rem Derleme makinesinin yollari ikiliye GOMULUYOR. Rust, panik mesajlarina
rem ve hata ayiklama bilgisine kaynak dosyanin tam yolunu yaziyor; olculdu
rem (28.09.2026): yayinlanan kutuphanede "C:\ElpoDeskBuild" 67 kez, cargo
rem deposu yolu 945 kez geciyor. Musteriye giden dosyada bizim dizin
rem duzenimiz duruyor -- sizma testi raporlarinin "bilgi ifsasi" basligi budur.
rem
rem --remap-path-prefix yollari sabit takma adlara cevirir; goreli yapi
rem korunur (panikte hangi dosya oldugu hala okunur), makineye ait bilgi
rem kalmaz. Sirasi ONEMLI: ozel olan once, genel olan sonra.
set "YOL_ANONIM=--remap-path-prefix=%USERPROFILE%\.cargo\registry\src=/paketler"
set "YOL_ANONIM=%YOL_ANONIM% --remap-path-prefix=%USERPROFILE%\.cargo\git=/paketler-git"
set "YOL_ANONIM=%YOL_ANONIM% --remap-path-prefix=%CD%=/skyydesk"
set "YOL_ANONIM=%YOL_ANONIM% --remap-path-prefix=%VCPKG_ROOT%=/kutuphaneler"
set "YOL_ANONIM=%YOL_ANONIM% --remap-path-prefix=C:\ElpoDeskBuild=/derleme"
rem config.toml bu hedefte statik CRT istiyor. RUSTFLAGS ortam degiskeni
rem config.toml'u EZDIGI icin ayni bayragi buraya da koymak zorundayiz;
rem yoksa hwcodec nesneleri /MT, gerisi /MD derlenip baglanti oluyor.
rem Iki kopyanin ayrismamasi icin config.toml denetleniyor:
findstr /C:"crt-static" .cargo\config.toml >nul 2>&1 || (
  echo HATA: .cargo/config.toml artik crt-static demiyor.
  echo        tools\build-windows.bat icindeki RUSTFLAGS satiri guncellenmeli.
  popd ^& exit /b 1
)
set "RUSTFLAGS=-Ctarget-feature=+crt-static %YOL_ANONIM%"

cargo build --locked --features flutter,hwcodec --lib --release || ( echo HATA: cargo build & popd & exit /b 1 )

rem Marka degisince ikilinin adi degisiyor ama flutter\build icindeki CMake
rem onbellegi eski hedefi tutuyor ve derleme "No target FixDesk" diyerek
rem duduyor — hata kaynakta hicbir sey bulunmadigi icin insani yaniltiyor.
rem Onbellekteki ad bugunkuyle uyusmuyorsa dizini at.
powershell -NoProfile -Command "$b=(Select-String -Path 'flutter\windows\CMakeLists.txt' -Pattern 'BINARY_NAME \"(.+?)\"').Matches[0].Groups[1].Value; $c='flutter\build\windows\x64\CMakeCache.txt'; if (Test-Path $c) { if (-not (Select-String -Path $c -SimpleMatch (\"TARGET_FILE_DIR:\" + $b) -Quiet)) { exit 1 } }; exit 0" || (
  echo   ikili adi degismis — eski CMake onbellegi siliniyor
  rmdir /s /q flutter\build\windows
)

echo.
echo === 2/3 SkyyDesk arayuzu
pushd flutter
call flutter build windows --release || ( echo HATA: flutter build & popd & popd & exit /b 1 )
popd
if not exist "%RELDIR%\SkyyDesk.exe" ( echo HATA: beklenen ikili yok: %RELDIR%\SkyyDesk.exe & popd & exit /b 1 )

rem Yol sizintisi denetimi. Ayri bir .ps1 dosyasindan kosuluyor: tek satirlik
rem PowerShell komutu olarak yazildiginda cmd, PowerShell'e gitmesi gereken
rem boru isaretlerini kendisi yorumluyor ve denetim patliyordu (28.09.2026).
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\yol-denetimi.ps1" -Kutuphane "%RELDIR%\libskyydesk.dll" || (
  echo HATA: yol sizintisi denetimi basarisiz.
  popd & exit /b 1
)

rem --- eski adli artiklar --------------------------------------------------
rem Cekirdek kutuphanenin adi degisti (librustdesk.dll -> libskyydesk.dll).
rem Eski dosya cikti klasorunde kaliyor ve paketleyici klasorun TAMAMINI
rem topladigi icin pakete giriyordu: 15.08.2026'da paket 23,7 MB'tan 32,8 MB'a
rem cikti ve icinde tam da kaldirmaya calistigimiz adla bir dosya vardi.
if exist "%RELDIR%\librustdesk.dll" (
  echo   eski kutuphane siliniyor: librustdesk.dll
  del /f /q "%RELDIR%\librustdesk.dll"
)
if exist "%RELDIR%\RuntimeBroker_rustdesk.exe" del /f /q "%RELDIR%\RuntimeBroker_rustdesk.exe"

rem --- gizlilik ortusu ----------------------------------------------------
rem "Ekrani karart" bu DLL olmadan CALISMAZ: win_topmost_window.rs dosyayi
rem exe'nin yaninda bulamayinca gizliligi sessizce acmayip Ok(false) donuyor,
rem karsi tarafa "Please install plugins" diye ulasiyordu. Pakete girmesi
rem zorunlu; eksikse derleme burada durur.
call libs\WindowInjection\derle.bat "%CD%\%RELDIR%" || ( echo HATA: WindowInjection.dll & popd & exit /b 1 )
if not exist "%RELDIR%\WindowInjection.dll" ( echo HATA: WindowInjection.dll uretilmedi & popd & exit /b 1 )


rem --- kod imzalama (istege bagli) ---------------------------------------
rem SmartScreen'in "Bilgisayariniz korundu" ekrani dosyanin imzasina bakiyor.
rem Imzasiz bir uruende itibar HIC birikmez: itibar dosya ozetine bagli ve
rem ozet her derlemede degisiyor. Cozum tek: kod imzalama sertifikasi.
rem
rem Sertifika iki bicimde verilebilir:
rem   SKYDESK_SIGN_PFX  + SKYDESK_SIGN_PASS   (dosya tabanli)
rem   SKYDESK_SIGN_SHA1                       (donanim token'i, parmak izi)
rem   SKYDESK_SIGN_DLIB + SKYDESK_SIGN_DMDF   (bulut imzalama)
rem
rem Haziran 2023'ten sonra verilen sertifikalarin anahtari DONANIMDA
rem durmak zorunda: yeni sertifika icin pfx indirme yolu yok, ya token ya
rem bulut imzalama kullanilir. Hicbiri tanimli degilse paket imzasiz
rem cikar; durum derleme sonunda yazilir ve SKYDESK_IMZA_ZORUNLU=1
rem verildiyse derleme duser.
rem
rem Zaman damgasi ZORUNLU: damgasiz imza, sertifika suresi dolunca gecersiz
rem olur ve o ana kadar dagitilmis her kurulum uyarmaya baslar.
set "SIGN_TS=http://timestamp.digicert.com"
set "SIGNTOOL="
for /f "delims=" %%S in ('where signtool 2^>nul') do set "SIGNTOOL=%%S"
rem `dir /s` yol ORTASINDA joker kabul etmez; eski desen ("bin\*\x64\")
rem hicbir sey dondurmuyordu ve SIGNTOOL bos kaliyordu -- sertifika
rem tanimli olsa bile imzalama sessizce atlaniyordu (27.09.2026).
rem `%ProgramFiles(x86)%` genisleyince icindeki parantez, tek satirlik
rem `if ... for ...` bilesiginde cmd'nin ayristiricisini bozuyor:
rem ": was unexpected at this time." deyip derleme oluyor. 27.09.2026'da
rem eklenen bu satir Windows derlemesini KIRDI ve kirildigi tek yer
rem derlemenin sonu oldugu icin fark edilmedi -- paket uretilmedi.
rem Cozum: yolu once degiskene al, `if` bilesigini de ayir.
set "KITS86=%ProgramFiles(x86)%\Windows Kits\10\bin"
set "KITS=%ProgramFiles%\Windows Kits\10\bin"
if defined SIGNTOOL goto :signtool_hazir
if exist "!KITS86!" for /f "delims=" %%S in ('dir /b /s "!KITS86!\signtool.exe" 2^>nul ^| findstr /i "x64"') do set "SIGNTOOL=%%S"
if defined SIGNTOOL goto :signtool_hazir
if exist "!KITS!" for /f "delims=" %%S in ('dir /b /s "!KITS!\signtool.exe" 2^>nul ^| findstr /i "x64"') do set "SIGNTOOL=%%S"
:signtool_hazir
goto :sign_done
:sign_one
if not defined SIGNTOOL (
  if defined SKYDESK_SIGN_PFX (
    echo HATA: sertifika tanimli ama signtool bulunamadi
    exit /b 1
  )
  if defined SKYDESK_SIGN_SHA1 (
    echo HATA: sertifika tanimli ama signtool bulunamadi
    exit /b 1
  )
  if defined SKYDESK_SIGN_DLIB (
    echo HATA: bulut imzalama tanimli ama signtool bulunamadi
    exit /b 1
  )
  exit /b 0
)
if defined SKYDESK_SIGN_SHA1 (
  "%SIGNTOOL%" sign /sha1 %SKYDESK_SIGN_SHA1% /fd SHA256 /tr %SIGN_TS% /td SHA256 %1 >nul || ( echo HATA: imzalama basarisiz: %1 & exit /b 1 )
  echo   imzalandi: %~nx1
  exit /b 0
)
rem Bulut imzalama: anahtar saglayicinin donaniminda durur, imza
rem saglayicinin kutuphanesi uzerinden atilir. DMDF, saglayicinin
rem istedigi hesap/sertifika bilgisini tasiyan json dosyasi.
if defined SKYDESK_SIGN_DLIB (
  "%SIGNTOOL%" sign /v /fd SHA256 /tr %SIGN_TS% /td SHA256 /dlib "%SKYDESK_SIGN_DLIB%" /dmdf "%SKYDESK_SIGN_DMDF%" %1 >nul || ( echo HATA: bulut imzalama basarisiz: %1 & exit /b 1 )
  rem Parantez KACIRILMALI: `if (...)` blogunun icinde kacirilmamis ")"
  rem blogu erken kapatiyor, geriye kalan ": %~nx1" cmd icin komut oluyor
  rem ve derleme ": was unexpected at this time." deyip oluyor. Bu satir
  rem imzalama yoluna girilmedigi surece hic parse edilmiyordu; signtool
  rem bulunur bulunmaz (28.09.2026) derlemeyi dusurdu.
  echo   imzalandi ^(bulut^): %~nx1
  exit /b 0
)
if defined SKYDESK_SIGN_PFX (
  "%SIGNTOOL%" sign /f "%SKYDESK_SIGN_PFX%" /p "%SKYDESK_SIGN_PASS%" /fd SHA256 /tr %SIGN_TS% /td SHA256 %1 >nul || ( echo HATA: imzalama basarisiz: %1 & exit /b 1 )
  echo   imzalandi: %~nx1
  exit /b 0
)
exit /b 0
:sign_done

rem Ic ikili paketlenmeden ONCE imzalanir; disaridaki paket sonra.
call :sign_one "%RELDIR%\SkyyDesk.exe"

echo.
echo === 3/3 tasinabilir paket
rem generate.py, cikti dosyasi zaten varsa FileExistsError verir; onceden temizle.
rem Cikti calisma alaninin ortak target dizinine duser, libs\portable\target'a degil:
rem cargo workspace tek bir target paylasiyor.
set "PACKER=target\release\skyydesk-portable-packer.exe"
if exist "%PACKER%" del /q "%PACKER%"
pushd libs\portable
python generate.py -f ../../%RELDIR%/ -o . -e ../../%RELDIR%/SkyyDesk.exe || ( echo HATA: portable packer & popd & popd & exit /b 1 )
popd
if not exist "%PACKER%" (
  echo HATA: packer ciktisi olusmadi: %PACKER%
  popd & exit /b 1
)

rem Surum damgasi: uygulamanin acilista bakacagi tek satirlik dosya
rem (src/updater.rs, skydesk_check_update). Derlemenin kendisinden uretiliyor;
rem elle yazilsa bir gun paketle damga ayrisir ve makineler ya bosuna guncellenir
rem ya da hic guncellenmez.
rem ONCE DOGRULA: derlemenin ici gercekten sabitledigimiz damgayi mi tasiyor?
rem Tasimiyorsa surum.txt ile paket ayrisir ve sahadaki makineler sonsuz
rem kurulum dongusune girer. Ayrisma sessiz kalmasin, derleme burada dursun.
rem Karsilastirmayi PowerShell yapiyor. for /f + ters tirnak denendi ve
rem dustu: desendeki "&str" ifadesindeki & isaretini cmd komut ayraci sanip
rem satiri parcaliyor.
powershell -NoProfile -Command "$d=(Select-String -Path 'src\version.rs' -Pattern 'BUILD_DATE: &str = \"(.+?)\"').Matches[0].Groups[1].Value; if ($d -ne $env:SKYDESK_BUILD_DATE) { Write-Host \"HATA: derleme damgasi kaydi. beklenen '$env:SKYDESK_BUILD_DATE', version.rs '$d'\"; exit 1 }"
if errorlevel 1 ( popd & exit /b 1 )
powershell -NoProfile -Command "$v=(Select-String -Path 'src\version.rs' -Pattern 'VERSION: &str = \"(.+?)\"').Matches[0].Groups[1].Value; $d=(Select-String -Path 'src\version.rs' -Pattern 'BUILD_DATE: &str = \"(.+?)\"').Matches[0].Groups[1].Value; Set-Content -Path 'surum.txt' -Value \"$v $d\" -NoNewline -Encoding ascii"
for /f "usebackq delims=" %%V in ("surum.txt") do echo   surum damgasi: %%V

echo.
echo === sonuc
if exist "SkyyDesk-Windows.exe" del /q "SkyyDesk-Windows.exe"
move /y "%PACKER%" "SkyyDesk-Windows.exe" >nul
call :sign_one "SkyyDesk-Windows.exe"
for %%F in ("SkyyDesk-Windows.exe") do echo   paket : %%~nxF (%%~zF bayt)
powershell -NoProfile -Command "$v=(Get-Item 'SkyyDesk-Windows.exe').VersionInfo; '  urun  : {0}' -f $v.ProductName; '  dosya : {0}' -f $v.OriginalFilename; '  sirket: {0}' -f $v.CompanyName; '  surum : {0}' -f $v.FileVersion"

rem Imza DURUMU her derlemede yazilir. Sessiz atlama yasak: imzasiz bir
rem paket indirende SmartScreen uyarisi cikarir ve bunu ilk goren musteri
rem olur. 27.09.2026'da olculdu: hem yeni derleme hem indirme sayfasindaki
rem paket TAMAMEN imzasizdi, oysa belgede 'kendi sertifikamizla imzali'
rem yaziyordu. Dogrulama signtool ile yapilir (Get-AuthenticodeSignature
rem bu makinede modul yukleyemiyor).
rem SKYDESK_IMZA_ZORUNLU=1 verilirse imzasiz/guvenilmez paket derlemeyi
rem DUSURUR -- yayina cikan surumde bu degisken 1 olmali.
set "IMZA_DURUM=bilinmiyor"
if not defined SIGNTOOL (
  echo   imza  : DOGRULANAMADI - signtool bulunamadi
  if "%SKYDESK_IMZA_ZORUNLU%"=="1" ( popd & exit /b 1 )
) else (
  "%SIGNTOOL%" verify /pa /q "SkyyDesk-Windows.exe" >nul 2>&1
  if errorlevel 1 (
    echo   imza  : YOK ya da zincir guvenilmiyor
    echo           sertifika icin: SKYDESK_SIGN_PFX + SKYDESK_SIGN_PASS
    echo           donanim token icin SKYDESK_SIGN_SHA1
    echo           bulut imzalama icin SKYDESK_SIGN_DLIB + SKYDESK_SIGN_DMDF
    if "%SKYDESK_IMZA_ZORUNLU%"=="1" (
      echo   HATA: imza zorunlu istendi ama paket imzasiz
      popd & exit /b 1
    )
  ) else (
    echo   imza  : gecerli, zincir guvenilir
  )
)

popd
endlocal
exit /b 0

rem --- markalama kapisi -----------------------------------------------------
rem %1 aranan desen, %2 bulunamazsa yazilacak sebep. BRANDOUT yukarida kuruldu.
:bgate
findstr /r /c:%1 "%BRANDOUT%" >nul 2>&1 || (
  echo HATA: denetim: %~2
  exit /b 1
)
exit /b 0

@echo off
rem WindowInjection.dll -- gizlilik ortusu. Ciktisi SkyyDesk.exe'nin YANINA
rem konur; win_topmost_window.rs dosyayi tam olarak orada ariyor.
rem
rem /MT bilerek: DLL, Windows'un RuntimeBroker kopyasina enjekte ediliyor.
rem O surecte bizim vcruntime surumumuzun yuklu olacaginin garantisi yok,
rem statik CRT ile bagimlilik birakmiyoruz.
setlocal
if "%~1"=="" ( echo kullanim: derle.bat ^<cikti-dizini^> & exit /b 1 )
set "CIKTI=%~1"
if not exist "%CIKTI%" ( echo HATA: cikti dizini yok: %CIKTI% & exit /b 1 )
where cl >nul 2>&1 || ( echo HATA: cl.exe yok - once vcvars64 cagrilmali & exit /b 1 )

pushd "%~dp0"
if exist obj rmdir /s /q obj
mkdir obj
cl /nologo /c /O2 /MT /EHsc /W3 /utf-8 /DUNICODE /D_UNICODE /Foobj\ dllmain.cpp || ( popd & exit /b 1 )
link /nologo /DLL /OUT:"%CIKTI%\WindowInjection.dll" obj\dllmain.obj user32.lib gdi32.lib || ( popd & exit /b 1 )
rmdir /s /q obj
popd
echo   WindowInjection.dll -^> %CIKTI%
exit /b 0

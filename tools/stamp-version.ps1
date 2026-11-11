# Derleme damgasini tazeler.
#
# NEDEN VAR: build.rs icindeki gen_version() yalniz Cargo.toml degisince
# calisiyor ("cargo:rerun-if-changed=Cargo.toml"), yani BUILD_DATE surumler
# arasinda DONUP KALIYOR. Uygulamanin acilistaki guncelleme kontrolu bu damgayi
# kiyasliyor (src/updater.rs); damga degismezse yeni paket yayinlansa bile
# hicbir makine kendini guncellemez. 13.08.2026'da paket iki kez ust uste ayni
# damgayla cikti, once bu fark edilmeseydi guncelleme sessizce olu kalacakti.

$ErrorActionPreference = 'Stop'
$kok = Split-Path -Parent $PSScriptRoot
Set-Location $kok

$surum = (Select-String -Path 'Cargo.toml' -Pattern '^version\s*=\s*"(.+?)"' |
    Select-Object -First 1).Matches[0].Groups[1].Value
# Damga paketleme betiginden geliyorsa O kullanilir. Ayni dosyaya build.rs de
# yaziyor; ikisi farkli "simdi" alirsa exe ile surum.txt ayrisir ve makineler
# sonsuz kurulum dongusune girer (15.08.2026). Tek kaynak: SKYDESK_BUILD_DATE.
$damga = if ($env:SKYDESK_BUILD_DATE) { $env:SKYDESK_BUILD_DATE.Trim() }
         else { Get-Date -Format 'yyyy-MM-dd HH:mm' }

$icerik = @"
pub const VERSION: &str = "$surum";
#[allow(dead_code)]
pub const BUILD_DATE: &str = "$damga";
"@

Set-Content -Path 'src\version.rs' -Value $icerik -Encoding ascii
Write-Output "  damga: $surum $damga"

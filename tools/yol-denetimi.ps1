# Yayinlanan kutuphanede derleme makinesinin yolu kalmis mi?
#
# Kaynaga gore ayrilir: vcpkg'nin ONCEDEN derlenmis kutuphaneleri yollarini
# kendi derlenislerinde gommustur ve bizim derlememiz onlari degistiremez;
# kendi kodumuzda ise tek bir yol bile sizmamali.
#
# Ayri dosya olmasinin sebebi: ayni denetim build-windows.bat icinde tek
# satirlik PowerShell komutu olarak duruyordu ve cmd, PowerShell'e gitmesi
# gereken boru isaretlerini kendisi yorumlayip "'Where-Object' is not
# recognized" diyerek dustu (28.09.2026).
param(
    [Parameter(Mandatory = $true)][string]$Kutuphane,
    [string]$Kok = 'C:\ElpoDeskBuild'
)

if (-not (Test-Path $Kutuphane)) {
    Write-Output "HATA: kutuphane bulunamadi: $Kutuphane"
    exit 1
}

$metin = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($Kutuphane))
# The build user's home is searched too: C and C++ sources outside the tree
# (cargo's own copies) wrote it into the library before 11.11.2026.
$desen = '(' + [regex]::Escape($Kok) + '|' + [regex]::Escape($env:USERPROFILE) + ')[^\x00"]{0,90}'
$hepsi = [regex]::Matches($metin, $desen)

$bizim = @($hepsi | Where-Object { $_.Value -notmatch 'vcpkg.buildtrees' })
$onceden = @($hepsi).Count - $bizim.Count

if ($bizim.Count -gt 0) {
    $bizim | Select-Object -First 3 | ForEach-Object { Write-Output ('    ' + $_.Value) }
    Write-Output "HATA: derleme makinesinin yolu kendi kodumuzdan kutuphaneye sizmis ($($bizim.Count) kez)."
    Write-Output "      Yol haritasi bayraklari (YOL_ANONIM) eksik olabilir."
    exit 1
}

Write-Output '  -> kendi kodumuzda yol sizintisi yok'
if ($onceden -gt 0) {
    Write-Output "  -> onceden derlenmis vcpkg kutuphanelerinde $onceden yol kaldi"
    Write-Output '     (o yollar paketler derlenirken gomuldu; temizlenmesi vcpkg'
    Write-Output '      portlarinin yeniden derlenmesini ister)'
}
exit 0

# vcpkg'nin kendi arm64-osx uclusu, alt macOS surumu acikca yazilmis hali.
#
# Surum verilmezse derleyici kutuphaneleri derleme makinesinin SDK'sina
# (Codemagic'te macOS 26) gore uretiyor; uygulama da ancak o surumde calisir.
# 12.3 = ScreenCaptureKit'in en dusugu; build.py, Podfile, Cargo.toml ve Xcode
# projesi Codemagic'te ayni degere cekiliyor (codemagic.yaml > macos-dmg).
# SDK arm64-ios'taki gibi acikca: CMake 4 -isysroot'u kendiliginden secmiyor.
#
# iOS derlemesindeki "host" bagimliliklari da bu ucluyle kuruluyor; zararsiz.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES arm64)
set(VCPKG_OSX_SYSROOT macosx)
set(VCPKG_OSX_DEPLOYMENT_TARGET 12.3)

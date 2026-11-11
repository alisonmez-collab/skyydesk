# vcpkg'nin kendi arm64-ios uclusu, SDK'si ve iOS alt surumu acikca yazilmis hali.
#
# CMake 4 macOS'ta -isysroot'u artik kendiliginden secmiyor. Bu vcpkg surumunun
# iOS toolchain'i ise SDK'yi CMake'e birakiyor. Codemagic'teki Homebrew CMake'i
# (4.x) ile iki sonuc gorduk:
#   1. SDK hic verilmeyince derleyici MacOSX SDK'sini aldi; aom "arm64-ios" diye
#      kuruldu ama icinde macOS nesneleri vardi. Rust baglayicisi soyle durdu:
#        building for 'iOS', but linking in object file (...aom_codec.c.o)
#        built for 'macOS'
#   2. Yalnizca alt surum eklenince CMake MacOSX SDK + iOS hedefini Mac Catalyst
#      sandi (--target=arm64-apple-ios13.0-macabi) ve derleyici testi coktu.
# Ikisini de SDK'yi iphoneos diye sabitlemek cozuyor.
#
# Kutuphaneler 13.0 icin; uygulamanin alt siniri 15.0 (Podfile, proje), 13.0
# nesneler 15.0 uygulamada sorunsuz. Yukseltmek vcpkg onbellegini bosa cikarir.
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphoneos)
set(VCPKG_OSX_DEPLOYMENT_TARGET 13.0)

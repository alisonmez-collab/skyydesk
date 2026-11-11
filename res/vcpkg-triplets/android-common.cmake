# Dort Android triplet'inin ortak yani. Deger tek yerde dursun diye ayri dosya.
#
# NEDEN VAR: NDK'de "as" diye bagimsiz bir assembler yok — clang hem derleyici
# hem assembler surucusudur. CMake'in enable_language(ASM) adimi
# CMAKE_ASM_COMPILER verilmediginde ciplak "as" arar. Windows host'ta boyle bir
# program hic yok (aom yapilandirmasi tam burada duser), Linux host'ta ise
# bulur — ama o HOST'un assembler'i, aarch64 hedefi icin yanlis olan. Her iki
# durumda da dogru cevap NDK'nin clang'idir, o yuzden acikca gosteriyoruz.
#
# DIKKAT: vcpkg triplet dosyasinin icerigini paket kimliginde (ABI hash)
# kullanir; include edilen bu dosya o hash'e girmez. Burayi degistirirsen
# ikili onbellegi temizle: vcpkg remove --outdated ya da %LOCALAPPDATA%\vcpkg\archives.

set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_CMAKE_SYSTEM_VERSION 21)

if(NOT DEFINED ENV{ANDROID_NDK_HOME})
    message(FATAL_ERROR "ANDROID_NDK_HOME tanimli degil; Android derlemesi icin gerekli.")
endif()

file(TO_CMAKE_PATH "$ENV{ANDROID_NDK_HOME}" _ndk_root)

if(CMAKE_HOST_WIN32)
    set(_ndk_bin "${_ndk_root}/toolchains/llvm/prebuilt/windows-x86_64/bin")
    set(_ndk_exe ".exe")
elseif(CMAKE_HOST_APPLE)
    set(_ndk_bin "${_ndk_root}/toolchains/llvm/prebuilt/darwin-x86_64/bin")
    set(_ndk_exe "")
else()
    set(_ndk_bin "${_ndk_root}/toolchains/llvm/prebuilt/linux-x86_64/bin")
    set(_ndk_exe "")
endif()

set(SKYDESK_ANDROID_ASM "${_ndk_bin}/clang${_ndk_exe}")
if(NOT EXISTS "${SKYDESK_ANDROID_ASM}")
    message(FATAL_ERROR "NDK clang bulunamadi: ${SKYDESK_ANDROID_ASM}")
endif()

# SkyyDesk

Remote desktop by ELPO Bilişim. This repository is the complete source of the SkyyDesk
clients and of the library that lets an application be connected to from SkyyDesk.

Website and downloads: https://skyydesk.com

## What is here

| folder | what it is |
|---|---|
| `src/`, `libs/` | the Rust core: connection, video, input, file transfer |
| `flutter/` | the desktop and Android interface |
| `embed/` | the embedding library (`skyydesk.dll`, `libskyydesk.so`), its C header, the .NET wrapper and examples in C, C#, Java and Delphi. Start with [embed/README.md](embed/README.md) |
| `tools/` | build scripts |
| `res/` | icons, installers, desktop files |

## Building

```sh
./tools/build-linux.sh          # Linux .deb
tools\build-windows.bat         # Windows .exe
./tools/build-android.sh        # Android .apk
```

Each script checks its prerequisites first; `--check` runs only that step.

The embedding library comes out of the same build: the Rust core is built as
`liblibskyydesk.so` on Linux and `libskyydesk.dll` on Windows, and is shipped as
`libskyydesk.so` / `skyydesk.dll`.

## Licence

AGPL-3.0, see [LICENCE](LICENCE).

SkyyDesk is a fork of [RustDesk](https://github.com/rustdesk/rustdesk). The changes cover the
brand, the default servers, the account and licence flow, and the embedding library.

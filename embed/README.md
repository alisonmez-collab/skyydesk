# SkyyDesk embedding library

`skyydesk.dll` (Windows) and `libskyydesk.so` (Linux) make the machine your application runs on
reachable from SkyyDesk. People connect to it from the SkyyDesk app or from
`https://skyydesk.com/webclient`; your application decides who gets in.

The library has no sign-in. Users, address books and licences are managed at
`https://skyydesk.com/panel`. The machine does not use a licence; the person who connects does.

## What you need

| | |
|---|---|
| Windows 10/11 64-bit | `skyydesk.dll` and the DLLs shipped next to it |
| Linux 64-bit (X11) | `libskyydesk.so` and the system packages below |
| An enrollment key (optional) | panel → Settings → Enrollment keys |

Android, iOS and web pages cannot be the machine that is connected to through this library.
See [Platforms](#platforms).

On Debian or Ubuntu, the library needs the same packages as the SkyyDesk desktop client:

```sh
sudo apt install libgtk-3-0 libxcb-randr0 libxdo3 libxfixes3 libxcb-shape0 libxcb-xfixes0 \
  libasound2 libsystemd0 libva2 libva-drm2 libva-x11-2 libgstreamer-plugins-base1.0-0 \
  libpam0g gstreamer1.0-pipewire libpulse0
```

On Ubuntu 24.04 and later, write `libgtk-3-0t64` and `libasound2t64` instead of the two without `t64`.

## Five steps

1. Put the library next to your executable.
2. Call `skyydesk_init` once, as the first thing in `main`. The library starts copies of your
   executable for its own helper roles, and those copies exit inside this call; code that runs
   before it runs in them too.
3. Set an event callback. Without one, `skyydesk_start` refuses to start: a connection nobody
   can see or approve is not allowed.
4. If you have an enrollment key, set it: `skyydesk_set_option("enroll-key", "sdk_...")`.
   The machine then appears in the key owner's address book by itself.
5. Call `skyydesk_start`. Show `skyydesk_my_id` (and the one-time password, if you allow
   passwords) to whoever will connect.

```c
skyydesk_init("./skyydesk-data");
skyydesk_set_event_callback(on_event, NULL);
skyydesk_set_option("enroll-key", "sdk_...");
skyydesk_start(0);              /* 0: every connection waits for skyydesk_accept */
```

## Events

The callback runs on a library thread. Copy what you need; the payload is freed when the call
returns. In a GUI, move to the UI thread before touching any window.

| kind | payload | what to do |
|---|---|---|
| `1` incoming | JSON: `id`, `name`, `peer_id`, `authorized`, … | if `authorized` is false, call `skyydesk_accept(id)` or `skyydesk_close(id)` |
| `2` closed | connection id | |
| `3` enrolled | `{"ok":true}` or `{"ok":false,"error":"..."}` | an invalid or revoked key shows here |

## Where settings are kept

In the user's configuration folder, under the name `SkyyDeskHost`, apart from a SkyyDesk client
installed on the same machine:

| | |
|---|---|
| Windows | `%APPDATA%\SkyyDeskHost\config` |
| Linux | `~/.config/skyydeskhost` |

The machine's ID is stored there. Keep that folder and the machine keeps its ID and its place
in address books; delete it and the machine gets a new ID. The folder passed to `skyydesk_init`
is used only on platforms without such a folder.

The enrollment key is kept there as well. Set it once and the library sends it again on every
start, so a revoked key keeps reporting an error in event `3` until you clear it with
`skyydesk_set_option("enroll-key", "")`.

## Passwords and settings

| call | |
|---|---|
| `skyydesk_password` / `skyydesk_new_password` | one-time password |
| `skyydesk_set_password("...")` | permanent password; `""` removes it |
| `verification-method` | `use-temporary-password`, `use-permanent-password`, `use-both-passwords` |
| `enable-keyboard`, `enable-clipboard`, `enable-file-transfer`, `enable-audio` | `Y` / `N` |

Server and account options (`api-server`, `custom-rendezvous-server`, `relay-server`, `key`,
`access_token`, `user_info`) return `-1`: the library always connects to SkyyDesk's servers.

## Languages

All of them call the same C functions in [`skyydesk.h`](skyydesk.h).

| language | example |
|---|---|
| C / C++ | [`examples/c/host.c`](examples/c/host.c) |
| C# — .NET 8 and .NET 10 | package [`dotnet/SkyyDesk`](dotnet/SkyyDesk), example [`examples/dotnet`](examples/dotnet) |
| Java (JNA) | [`examples/java/SkyyDeskHost.java`](examples/java/SkyyDeskHost.java) |
| Delphi | [`examples/delphi`](examples/delphi) |

```csharp
var desk = new SkyyDeskHost(appDataDir);
desk.Incoming += (_, c) => { if (!c.Authorized) desk.Accept(c.Id); };
desk.SetEnrollKey("sdk_...");
desk.Start(allowPassword: false);
```

### .NET package

`SkyyDesk.1.4.10.nupkg` is downloaded from `https://skyydesk.com/gelistiriciler/`, not from nuget.org.
Put it in a folder and add that folder as a package source:

```sh
dotnet nuget add source ./packages --name skyydesk
dotnet add package SkyyDesk --version 1.4.10
```

The package carries the native library for Windows x64 and Linux x64; it is copied next to your
executable on build.

## Platforms

| platform | as the machine connected to | note |
|---|---|---|
| Windows 10/11 | yes | |
| Linux (X11) | yes | Wayland asks the user to share the screen every session |
| Android | not yet | Android lets an app share its screen only through its own permission screens and services; a package for that is in progress |
| iOS | no | iOS does not let an app control the screen |
| web page | no | a browser does not let a page control the computer. To connect **from** a web application, open `https://skyydesk.com/webclient` |

## Licence

AGPL-3.0, like the SkyyDesk client it is built from. Source: this repository.

| what you do | what AGPL asks of you |
|---|---|
| use your application only inside your own company | nothing more |
| ship it in an open-source application | release that application under an AGPL-compatible licence |
| ship or sell it in a closed-source application | publish your application's source, or launch the SkyyDesk app instead of embedding the library |

This table is a summary, not legal advice.

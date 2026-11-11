// WindowInjection.dll -- gizlilik kipinin ortu penceresi.
//
// src/privacy_mode/win_topmost_window.rs bu DLL'i, Windows'un kendi
// RuntimeBroker.exe kopyasina (RuntimeBroker_rustdesk.exe) enjekte eder.
// Beklenen davranis tamamen o dosyadan okunuyor:
//
//   * sinif adi  RustDeskPrivacyWindowClass, pencere adi RustDeskPrivacyWindow
//     (FindWindowExA ile aranir, adlar birebir ayni kalmali)
//   * her monitor icin bir pencere, monitorun tamamini kaplayacak
//     (count_covered_monitors GetWindowRect ile olcuyor)
//   * pencereler ONCE GIZLI acilir; gostermek/gizlemek icin
//     WM_APP+3 / WM_APP+4 postalanir
//
// Ortu ekranin onunde durur ama YAKALAMADAN cikarilir: makinenin basindaki
// kisi ekrani goremez, uzaktan baglanan kisi masaustunu gormeye devam eder.
// Bunu SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE) yapiyor; zaten
// varsayilan uygulama (win_exclude_from_capture) tam da bu bayragin geldigi
// yapiya (Windows 10 2004 / 19041) bakip kendini secikir. Daha eski
// Windows'ta bayrak yok, orada yakalama buyutec yolundan yapilir ve ortuyu
// kendi filtresiyle disarida birakir -- o yuzden basarisiz cagri sorun degil.
//
// Ekran duz siyah birakilmaz: hem urunun renk dili siyah kullanmiyor, hem de
// bombos siyah ekran makine basindakine ariza gibi gorunur. Ne oldugunu
// yazan bir ortu, kapali bir ekrandan daha durustur.

#include <windows.h>
#include <vector>

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif

static const wchar_t* SINIF_ADI = L"RustDeskPrivacyWindowClass";
static const wchar_t* PENCERE_ADI = L"RustDeskPrivacyWindow";

#define WM_ORTU_GOSTER (WM_APP + 3)
#define WM_ORTU_GIZLE (WM_APP + 4)
#define WM_ORTU_TAZELE (WM_APP + 64)

#define ZAMANLAYICI_USTTE_KAL 1

// CLAUDE.md 3.1 -- koyu yuzey ELPO laciverdi, vurgu turkuaz.
static const COLORREF ZEMIN = RGB(0x00, 0x1A, 0x2C);
static const COLORREF TURKUAZ = RGB(0x3F, 0xC9, 0xCF);
static const COLORREF METIN = RGB(0xD7, 0xE6, 0xEE);
static const COLORREF SOLUK = RGB(0x7E, 0x9A, 0xAB);

static const wchar_t* MARKA = L"SkyyDesk";
// Kaynak dosyanin kodlamasindan bagimsiz olsun diye kacis dizileriyle.
static const wchar_t* SATIR_TR =
    L"Bu bilgisayara uzaktan bağlanıldı — ekran gizlendi";
static const wchar_t* SATIR_EN = L"Remote session in progress — screen hidden";

static HINSTANCE g_modul = NULL;
static std::vector<HWND> g_ortuler;
static bool g_gorunur = false;

static void YakalamadanCikar(HWND hwnd) {
    typedef BOOL(WINAPI * AffiniteAyarla)(HWND, DWORD);
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (!user32) {
        return;
    }
    AffiniteAyarla ayarla =
        (AffiniteAyarla)GetProcAddress(user32, "SetWindowDisplayAffinity");
    if (ayarla) {
        ayarla(hwnd, WDA_EXCLUDEFROMCAPTURE);
    }
}

static void DpiFarkindaligiAyarla() {
    typedef BOOL(WINAPI * BaglamAyarla)(HANDLE);
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (user32) {
        BaglamAyarla ayarla =
            (BaglamAyarla)GetProcAddress(user32, "SetProcessDpiAwarenessContext");
        // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
        if (ayarla && ayarla((HANDLE)-4)) {
            return;
        }
    }
    // Sureç manifestinden zaten farkindaysa bu da basarisiz olur, sorun degil:
    // onemli olan monitor dikdortgenlerini Rust tarafiyla ayni olcekte gormek.
    SetProcessDPIAware();
}

static UINT PencereninDpisi(HWND hwnd) {
    typedef UINT(WINAPI * DpiAl)(HWND);
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (user32) {
        DpiAl al = (DpiAl)GetProcAddress(user32, "GetDpiForWindow");
        if (al) {
            UINT dpi = al(hwnd);
            if (dpi >= 72) {
                return dpi;
            }
        }
    }
    return 96;
}

static HFONT YaziKur(int punto, UINT dpi, int kalinlik) {
    return CreateFontW(-MulDiv(punto, dpi, 72), 0, 0, 0, kalinlik, FALSE, FALSE,
                       FALSE, DEFAULT_CHARSET, OUT_TT_PRECIS, CLIP_DEFAULT_PRECIS,
                       CLEARTYPE_QUALITY, VARIABLE_PITCH, L"Segoe UI");
}

static void SatirYaz(HDC hdc, const wchar_t* yazi, RECT alan, HFONT yazitipi,
                     COLORREF renk) {
    HGDIOBJ eski = SelectObject(hdc, yazitipi);
    SetTextColor(hdc, renk);
    DrawTextW(hdc, yazi, -1, &alan, DT_CENTER | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(hdc, eski);
}

static void Ciz(HWND hwnd, HDC hdc, const RECT& alan) {
    HBRUSH firca = CreateSolidBrush(ZEMIN);
    FillRect(hdc, &alan, firca);
    DeleteObject(firca);

    UINT dpi = PencereninDpisi(hwnd);
    HFONT marka = YaziKur(34, dpi, FW_SEMIBOLD);
    HFONT govde = YaziKur(15, dpi, FW_NORMAL);
    HFONT ufak = YaziKur(11, dpi, FW_NORMAL);

    int orta = (alan.top + alan.bottom) / 2;
    int adim = MulDiv(34, dpi, 96);

    SetBkMode(hdc, TRANSPARENT);

    RECT r = alan;
    r.top = orta - adim * 2;
    r.bottom = r.top + adim * 2;
    SatirYaz(hdc, MARKA, r, marka, TURKUAZ);

    r.top = orta + adim / 2;
    r.bottom = r.top + adim;
    SatirYaz(hdc, SATIR_TR, r, govde, METIN);

    r.top = orta + adim * 3 / 2;
    r.bottom = r.top + adim;
    SatirYaz(hdc, SATIR_EN, r, ufak, SOLUK);

    DeleteObject(marka);
    DeleteObject(govde);
    DeleteObject(ufak);
}

static void UsteAl(HWND hwnd) {
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

static void Goster(HWND hwnd) {
    ShowWindow(hwnd, SW_SHOWNA);
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    // Sonradan acilan baska bir en-ustte pencere ortunun onune gecebilir;
    // gizlilik acikken ustte kalmayi surekli tazeliyoruz.
    SetTimer(hwnd, ZAMANLAYICI_USTTE_KAL, 1000, NULL);
}

static LRESULT CALLBACK OrtuYordami(HWND hwnd, UINT mesaj, WPARAM wp, LPARAM lp) {
    switch (mesaj) {
        case WM_ORTU_GOSTER:
            g_gorunur = true;
            Goster(hwnd);
            return 0;

        case WM_ORTU_GIZLE:
            g_gorunur = false;
            KillTimer(hwnd, ZAMANLAYICI_USTTE_KAL);
            ShowWindow(hwnd, SW_HIDE);
            return 0;

        case WM_TIMER:
            if (wp == ZAMANLAYICI_USTTE_KAL && IsWindowVisible(hwnd)) {
                UsteAl(hwnd);
            }
            return 0;

        case WM_DISPLAYCHANGE:
            // Ekran duzeni degisti: ortuleri yeni monitorlere gore yeniden kur.
            // Pencere yordamindan degil, ileti dongusunden yapiliyor -- burada
            // kendimizi yok edemeyiz.
            PostThreadMessage(GetCurrentThreadId(), WM_ORTU_TAZELE, 0, 0);
            return 0;

        case WM_MOUSEACTIVATE:
            // Ortu odagi almaz: uzaktan gelen klavye altta kalan pencereye gitsin.
            return MA_NOACTIVATE;

        case WM_NCHITTEST:
            // Ortu fareye GORUNMEZ olmali. Karartma acikken uzaktan baglanan
            // kisi calismaya devam ediyor ve tiklamalari SendInput ile
            // gonderiliyor; ortu isaretcinin altinda oldugu icin o tiklamalari
            // yutardi -- ekran kararir, kumanda olurdu. Makine basindaki kisi
            // bu delikten iceri giremez: yerel girdi ayrica engelleniyor
            // (win_input::hook, turn_on_privacy icinde cagriliyor).
            return HTTRANSPARENT;

        case WM_ERASEBKGND: {
            RECT alan;
            GetClientRect(hwnd, &alan);
            Ciz(hwnd, (HDC)wp, alan);
            return 1;
        }

        case WM_PAINT: {
            PAINTSTRUCT boya;
            HDC hdc = BeginPaint(hwnd, &boya);
            RECT alan;
            GetClientRect(hwnd, &alan);
            Ciz(hwnd, hdc, alan);
            EndPaint(hwnd, &boya);
            return 0;
        }

        case WM_CLOSE:
            // Ortuyu yalniz biz kapatiriz.
            return 0;

        case WM_DESTROY:
            return 0;
    }
    return DefWindowProcW(hwnd, mesaj, wp, lp);
}

static BOOL CALLBACK MonitorGeldi(HMONITOR monitor, HDC, LPRECT, LPARAM) {
    MONITORINFO bilgi;
    bilgi.cbSize = sizeof(bilgi);
    if (!GetMonitorInfoW(monitor, &bilgi)) {
        return TRUE;
    }
    const RECT& r = bilgi.rcMonitor;
    // WS_EX_TRANSPARENT tek basina yetmiyor: tiklamanin gercekten alttaki
    // pencereye gecmesi icin pencerenin ayrica KATMANLI olmasi gerekiyor.
    // Olculdu -- katmansiz surumde tiklama ortude kaliyordu.
    HWND hwnd = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
            WS_EX_TRANSPARENT | WS_EX_LAYERED,
        SINIF_ADI, PENCERE_ADI, WS_POPUP, r.left, r.top, r.right - r.left,
        r.bottom - r.top, NULL, NULL, g_modul, NULL);
    if (!hwnd) {
        return TRUE;
    }
    // Tamamen opak: katmanlilik saydamlik icin degil, tiklama geciriyor diye.
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
    YakalamadanCikar(hwnd);
    g_ortuler.push_back(hwnd);
    return TRUE;
}

static void OrtuleriKur() {
    for (size_t i = 0; i < g_ortuler.size(); i++) {
        KillTimer(g_ortuler[i], ZAMANLAYICI_USTTE_KAL);
        DestroyWindow(g_ortuler[i]);
    }
    g_ortuler.clear();

    EnumDisplayMonitors(NULL, NULL, MonitorGeldi, 0);

    if (g_gorunur) {
        for (size_t i = 0; i < g_ortuler.size(); i++) {
            Goster(g_ortuler[i]);
        }
    }
}

static DWORD WINAPI Isci(LPVOID) {
    DpiFarkindaligiAyarla();

    WNDCLASSEXW sinif;
    ZeroMemory(&sinif, sizeof(sinif));
    sinif.cbSize = sizeof(sinif);
    sinif.lpfnWndProc = OrtuYordami;
    sinif.hInstance = g_modul;
    sinif.hCursor = LoadCursorW(NULL, IDC_ARROW);
    sinif.hbrBackground = NULL;
    sinif.lpszClassName = SINIF_ADI;
    if (!RegisterClassExW(&sinif)) {
        if (GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return 1;
        }
    }

    OrtuleriKur();

    MSG mesaj;
    BOOL sonuc;
    while ((sonuc = GetMessageW(&mesaj, NULL, 0, 0)) != 0) {
        if (sonuc == -1) {
            break;
        }
        if (mesaj.hwnd == NULL && mesaj.message == WM_ORTU_TAZELE) {
            OrtuleriKur();
            continue;
        }
        TranslateMessage(&mesaj);
        DispatchMessageW(&mesaj);
    }
    return 0;
}

BOOL APIENTRY DllMain(HMODULE modul, DWORD sebep, LPVOID) {
    if (sebep == DLL_PROCESS_ATTACH) {
        g_modul = (HINSTANCE)modul;
        DisableThreadLibraryCalls(modul);
        // Yukleyici kilidi altindayiz; is parcacigi DllMain donunce calisir.
        HANDLE is = CreateThread(NULL, 0, Isci, NULL, 0, NULL);
        if (is) {
            CloseHandle(is);
        }
    }
    return TRUE;
}

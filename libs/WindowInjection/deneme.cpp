// WindowInjection.dll deneme kosumu.
//
// DLL'i yukler ve win_topmost_window.rs'in yaptigi denetimin AYNISINI yapar:
// pencereleri FindWindowExA ile sinif+ad uzerinden bulur, her monitorun
// kapsanip kapsanmadigina GetWindowRect ile bakar, WM_APP+3 / WM_APP+4
// postalayip gorunurlugu olcer.
//
// --yuklemeden ile calistirilirsa DLL'i hic yuklemez: denemenin kendisinin
// gecerli oldugunu gormek icin. O kosumda "0 ortu" cikmali; cikmiyorsa
// deneme bir sey olcmuyor demektir.

#include <windows.h>
#include <stdio.h>
#include <vector>

#define WM_ORTU_GOSTER (WM_APP + 3)
#define WM_ORTU_GIZLE (WM_APP + 4)

static std::vector<RECT> g_monitorler;

static BOOL CALLBACK MonitorGeldi(HMONITOR monitor, HDC, LPRECT, LPARAM) {
    MONITORINFO bilgi;
    bilgi.cbSize = sizeof(bilgi);
    if (GetMonitorInfoW(monitor, &bilgi)) {
        g_monitorler.push_back(bilgi.rcMonitor);
    }
    return TRUE;
}

static std::vector<HWND> OrtuleriBul() {
    std::vector<HWND> bulunan;
    HWND sonra = NULL;
    while (true) {
        HWND hwnd = FindWindowExA(NULL, sonra, "RustDeskPrivacyWindowClass",
                                  "RustDeskPrivacyWindow");
        if (!hwnd) {
            break;
        }
        bulunan.push_back(hwnd);
        sonra = hwnd;
    }
    return bulunan;
}

static bool Kapsiyor(const RECT& pencere, const RECT& monitor) {
    return pencere.left <= monitor.left && pencere.top <= monitor.top &&
           pencere.right >= monitor.right && pencere.bottom >= monitor.bottom;
}

static int KapsananMonitorler(const std::vector<HWND>& ortuler, bool gorunurSart) {
    int sayi = 0;
    for (size_t m = 0; m < g_monitorler.size(); m++) {
        for (size_t o = 0; o < ortuler.size(); o++) {
            if (gorunurSart && !IsWindowVisible(ortuler[o])) {
                continue;
            }
            RECT r;
            if (!GetWindowRect(ortuler[o], &r)) {
                continue;
            }
            if (Kapsiyor(r, g_monitorler[m])) {
                sayi++;
                break;
            }
        }
    }
    return sayi;
}

static void Bekle(int ms) { Sleep(ms); }

static LONG g_tiklamaSayisi = 0;

static LRESULT CALLBACK YardimciYordam(HWND hwnd, UINT mesaj, WPARAM wp,
                                       LPARAM lp) {
    if (mesaj == WM_LBUTTONDOWN) {
        InterlockedIncrement(&g_tiklamaSayisi);
    }
    return DefWindowProcW(hwnd, mesaj, wp, lp);
}

static void IletileriBosalt(int ms) {
    DWORD son = GetTickCount() + ms;
    MSG mesaj;
    while (GetTickCount() < son) {
        while (PeekMessageW(&mesaj, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&mesaj);
            DispatchMessageW(&mesaj);
        }
        Sleep(10);
    }
}

// Ortu goruniyorken altindaki pencereye tiklama ulasiyor mu?
static bool TiklamaAltaGecti(const std::vector<HWND>& ortuler) {
    WNDCLASSEXW sinif;
    ZeroMemory(&sinif, sizeof(sinif));
    sinif.cbSize = sizeof(sinif);
    sinif.lpfnWndProc = YardimciYordam;
    sinif.hInstance = GetModuleHandleW(NULL);
    sinif.hCursor = LoadCursorW(NULL, IDC_ARROW);
    sinif.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    sinif.lpszClassName = L"OrtuDenemeAltPencere";
    RegisterClassExW(&sinif);

    const RECT& ekran = g_monitorler[0];
    int mx = (ekran.left + ekran.right) / 2;
    int my = (ekran.top + ekran.bottom) / 2;

    HWND alt = CreateWindowExW(0, L"OrtuDenemeAltPencere", L"alt pencere",
                               WS_POPUP | WS_VISIBLE, mx - 100, my - 100, 200,
                               200, NULL, NULL, sinif.hInstance, NULL);
    if (!alt) {
        printf("  (alt pencere acilamadi, olcum yapilamadi)\n");
        return false;
    }
    // Ortu en ustte oldugu icin alt pencerenin onune geciyor; tiklama
    // noktasinda ustte ortu var.
    for (size_t i = 0; i < ortuler.size(); i++) {
        SetWindowPos(ortuler[i], HWND_TOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    IletileriBosalt(200);

    g_tiklamaSayisi = 0;
    POINT eskiImlec;
    GetCursorPos(&eskiImlec);
    SetCursorPos(mx, my);
    IletileriBosalt(120);

    INPUT girdi[2];
    ZeroMemory(girdi, sizeof(girdi));
    girdi[0].type = INPUT_MOUSE;
    girdi[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    girdi[1].type = INPUT_MOUSE;
    girdi[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(2, girdi, sizeof(INPUT));

    IletileriBosalt(500);
    SetCursorPos(eskiImlec.x, eskiImlec.y);

    LONG geldi = g_tiklamaSayisi;
    DestroyWindow(alt);
    IletileriBosalt(100);
    return geldi > 0;
}

int main(int argc, char** argv) {
    typedef BOOL(WINAPI * BaglamAyarla)(HANDLE);
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    BaglamAyarla dpi =
        (BaglamAyarla)GetProcAddress(user32, "SetProcessDpiAwarenessContext");
    if (dpi) {
        dpi((HANDLE)-4);
    }

    bool yukle = true;
    // --tut <saniye>: ortuyu ekranda tutar. Ortu normalde yakalamadan
    // cikarildigi icin ekran goruntusunde GORUNMEZ; cizimin dogrulugu ancak
    // affinitesi kapatilmis bir surumle, bu bekleme sirasinda bakilabilir.
    int tutSaniye = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--yuklemeden") == 0) {
            yukle = false;
        } else if (strcmp(argv[i], "--tut") == 0 && i + 1 < argc) {
            tutSaniye = atoi(argv[++i]);
        }
    }

    EnumDisplayMonitors(NULL, NULL, MonitorGeldi, 0);
    printf("monitor sayisi: %d\n", (int)g_monitorler.size());

    if (yukle) {
        HMODULE dll = LoadLibraryW(L"WindowInjection.dll");
        if (!dll) {
            printf("BASARISIZ: DLL yuklenemedi, hata %lu\n", GetLastError());
            return 1;
        }
        printf("DLL yuklendi\n");
    } else {
        printf("DLL YUKLENMEDI (deneme gecerlilik kosumu)\n");
    }

    std::vector<HWND> ortuler;
    for (int i = 0; i < 40; i++) {
        ortuler = OrtuleriBul();
        if (ortuler.size() >= g_monitorler.size() && !ortuler.empty()) {
            break;
        }
        Bekle(50);
    }
    printf("bulunan ortu: %d\n", (int)ortuler.size());
    if (ortuler.empty()) {
        printf("SONUC: ortu yok\n");
        return yukle ? 1 : 0;
    }

    printf("baslangicta gorunur mu: ");
    bool baslangictaGorunur = false;
    for (size_t i = 0; i < ortuler.size(); i++) {
        if (IsWindowVisible(ortuler[i])) {
            baslangictaGorunur = true;
        }
    }
    printf("%s (gizli olmali)\n", baslangictaGorunur ? "EVET - HATA" : "hayir");

    printf("kapsanan monitor (gizliyken): %d/%d\n",
           KapsananMonitorler(ortuler, false), (int)g_monitorler.size());

    for (size_t i = 0; i < ortuler.size(); i++) {
        DWORD affinite = 0;
        if (GetWindowDisplayAffinity(ortuler[i], &affinite)) {
            printf("ortu %d yakalama affinitesi: 0x%02lX %s\n", (int)i, affinite,
                   affinite == 0x11 ? "(yakalamadan cikarilmis)" : "(CIKARILMAMIS)");
        } else {
            printf("ortu %d affinite okunamadi, hata %lu\n", (int)i, GetLastError());
        }
    }

    printf("\n-- goster --\n");
    for (size_t i = 0; i < ortuler.size(); i++) {
        PostMessageA(ortuler[i], WM_ORTU_GOSTER, 0, 0);
    }
    int gorunurKapsam = 0;
    for (int i = 0; i < 40; i++) {
        Bekle(50);
        gorunurKapsam = KapsananMonitorler(ortuler, true);
        if (gorunurKapsam == (int)g_monitorler.size()) {
            break;
        }
    }
    printf("gorunur ortunun kapsadigi monitor: %d/%d\n", gorunurKapsam,
           (int)g_monitorler.size());

    // Ortu fareyi yutuyor mu? Karartma acikken uzaktan baglanan kisi
    // calismaya devam ediyor ve tiklamalari SendInput ile geliyor; ortu
    // isaretcinin altinda oldugu icin onlari yutarsa ekran kararir ama
    // kumanda olur.
    //
    // Bu, ortunun bayraklarina bakarak degil GERCEKTEN olculuyor: ortunun
    // ALTINA kendi penceremizi koyuyoruz, ustune tikliyoruz ve tiklamanin
    // bize ulasip ulasmadigina bakiyoruz. (WindowFromPoint bu isi gormuyor --
    // WS_EX_TRANSPARENT pencereyi yine donduruyor.)
    bool yutuyor = !TiklamaAltaGecti(ortuler);
    printf("fare ortuyu deliyor mu: %s\n",
           yutuyor ? "HAYIR - tiklamalar ortude kalir, HATA" : "evet");

    if (tutSaniye > 0) {
        printf("ortu %d saniye ekranda tutuluyor\n", tutSaniye);
        for (int i = 0; i < tutSaniye * 10; i++) {
            Bekle(100);
        }
    } else {
        Bekle(800);
    }

    printf("\n-- gizle --\n");
    for (size_t i = 0; i < ortuler.size(); i++) {
        PostMessageA(ortuler[i], WM_ORTU_GIZLE, 0, 0);
    }
    bool halaGorunur = true;
    for (int i = 0; i < 40; i++) {
        Bekle(50);
        halaGorunur = false;
        for (size_t j = 0; j < ortuler.size(); j++) {
            if (IsWindowVisible(ortuler[j])) {
                halaGorunur = true;
            }
        }
        if (!halaGorunur) {
            break;
        }
    }
    printf("gizlendi mi: %s\n", halaGorunur ? "HAYIR - HATA" : "evet");

    bool tamam = !baslangictaGorunur && gorunurKapsam == (int)g_monitorler.size() &&
                 !yutuyor && !halaGorunur;
    printf("\nSONUC: %s\n", tamam ? "GECTI" : "KALDI");
    return tamam ? 0 : 1;
}

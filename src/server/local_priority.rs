// Makinenin BASINDAKI kisinin onceligi.
//
// Uzaktan bagli kisi ile makinenin basindaki kisi ayni anda fare oynatinca
// imlec ikisi arasinda zipliyor ve ikisi de is yapamaz hale geliyor. Yerel
// kullanici kontrolu geri alamiyor, cunku kontrol "en son girdi goendereni"
// izliyor ve uzak taraf saniyede onlarca olay yolluyor.
//
// Upstream'de bu bir istek olarak acildi ve kapandi (rustdesk#15488,
// "Local mouse and keyboard input should take priority ... like AnyDesk"),
// uygulanmadi. Buradaki karsiligi:
//
//   Fiziksel bir fare/klavye olayi gorulunce, kisa bir sure (varsayilan
//   300 ms) uzaktan gelen girdi yok sayilir. Yerel kullanici elini cekince
//   uzak taraf kaldigi yerden devam eder.
//
// SEZGISEL DEGIL: fiziksel girdi HAM GIRDI (raw input) ile dinleniyor ve
// SendInput ile enjekte edilen olaylar ham girdi uretmiyor. Yani "aygittan
// mi geldi" sorusunu isletim sistemi yanitliyor; bizim tahminimize gerek yok.
// Ayrintili gerekce ve neden dusuk seviyeli kancadan vazgecildigi asagida,
// `imp` modulunun basinda.
//
// Hicbir sey ENGELLENMIYOR, yalnizca zaman not ediliyor; yerel kullanicinin
// girdisi her zaman gecer.

use hbb_common::log;
use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};

/// Fiziksel girdiden sonra uzak girdinin yok sayilacagi sure.
/// Upstream isteginde onerilen aralik 100-300 ms; ust sinir secildi, cunku
/// insan eli iki hareket arasinda bu kadar duraklayabiliyor ve daha kisa
/// sure "yerel kullanici yine de kaybediyor" demek oluyor.
const SUPPRESS_MS: i64 = 300;

static LOCAL_INPUT_AT: AtomicI64 = AtomicI64::new(0);
static HOOKED: AtomicBool = AtomicBool::new(false);

/// Makinenin basindaki kisi az once girdi yapti mi.
#[inline]
pub fn local_user_active() -> bool {
    if !enabled() {
        return false;
    }
    let last = LOCAL_INPUT_AT.load(Ordering::Relaxed);
    last != 0 && hbb_common::get_time() - last < SUPPRESS_MS
}

fn enabled() -> bool {
    // Kapatilabilir olmali: bazi kurulumlarda makinenin basinda kimse yok ama
    // dokunmatik ekran/kiosk yazilimi olay uretiyor olabilir.
    hbb_common::config::Config::get_option("local-input-priority") != "N"
}

// Uzak girdi bastirildiginda saniyede bir satir. Fiziksel girdinin kendisi
// GUNLUGE YAZILMIYOR: dogrulama sirasinda yaziliyordu ve saniyede bir satir
// uretmek disinda bir ise yaramiyor.
static LAST_LOG_OUT: AtomicI64 = AtomicI64::new(0);

#[inline]
fn throttled(slot: &AtomicI64, now: i64) -> bool {
    if now - slot.load(Ordering::Relaxed) > 1000 {
        slot.store(now, Ordering::Relaxed);
        return true;
    }
    false
}

#[inline]
fn note_local_input() {
    LOCAL_INPUT_AT.store(hbb_common::get_time(), Ordering::Relaxed);
}

/// Uzak girdinin bu yuzden dusuruldugunu gunluge yazar (saniyede bir).
pub fn note_suppressed() {
    let now = hbb_common::get_time();
    if throttled(&LAST_LOG_OUT, now) {
        log::info!("local input priority: remote input yielded");
    }
}

#[cfg(windows)]
mod imp {
    use super::*;
    use std::sync::mpsc::channel;
    use winapi::{
        shared::{
            minwindef::{LPARAM, LRESULT, UINT, WPARAM},
            ntdef::NULL,
            windef::HWND,
        },
        um::winuser::*,
    };

    // Fiziksel girdiyi HAM GIRDI ile dinliyoruz, dusuk seviyeli kanca ile
    // degil.
    //
    // Once WH_MOUSE_LL/WH_KEYBOARD_LL denendi ve calismadi: Windows, geri
    // cagrisi LowLevelHooksTimeout icinde donmeyen kancayi sessizce
    // kaldiriyor. Olculdu (09.08.2026): kanca ilk olayi gordu, sonra hicbir
    // sey gelmedi ve "son fiziksel girdi" yasi buyumeye devam etti. Geri
    // cagri gunluge yaziyordu; dosya G/C girdi yolunda yapilacak is degil.
    //
    // Ham girdinin iki ustunlugu var: (1) geri cagri girdi yolunda degil,
    // yavaslasa da girdiyi geciktirmiyor ve kaldirilmiyor; (2) SendInput ile
    // enjekte edilen olaylar ham girdi URETMIYOR — yani "bu bizim mi" ayrimi
    // icin imza karsilastirmaya bile gerek kalmiyor, aygittan gelmeyen olay
    // buraya hic dusmuyor.
    const RIDEV_INPUTSINK: u32 = 0x0000_0100;
    const HID_USAGE_PAGE_GENERIC: u16 = 0x01;
    const HID_USAGE_MOUSE: u16 = 0x02;
    const HID_USAGE_KEYBOARD: u16 = 0x06;

    /// Bu olay gercek bir AYGITTAN mi geldi.
    ///
    /// Onceki surumde bu soru hic sorulmuyordu: "olayin gelmis olmasi zaten
    /// aygitta biri var demek" diye yazilmisti, gerekcesi de SendInput ile
    /// enjekte edilen olaylarin ham girdi uretmedigiydi. O gerekce YANLIS —
    /// enjekte edilen olaylar da WM_INPUT dusuruyor. Sonucu 11.08.2026'da
    /// kullanici bildirdi: kendi enjeksiyonumuz kendi kotamizi yiyordu.
    /// Fare hareketi enjekte ediliyor, 300 ms kapaniyor, hemen ardindaki
    /// down/up dusuyor — "ilk tiklama calismiyor, ikinci ucuncude tutuyor".
    /// Klavyede ise tuslar saniyede uctan sik geldigi icin ilk tustan
    /// sonrasi tamamen dusuyor ve yazmak hic calismiyor.
    ///
    /// Ayrimi isletim sistemi veriyor: enjekte edilen olayda `hDevice` NULL,
    /// gercek aygitta gecerli bir tutamactir. Yalniz basligi okuyoruz, yuku
    /// degil — girdi yolunda yapilacak en ucuz is.
    ///
    /// Okunamazsa ESKI davranisa donuluyor (fiziksel say): yerel kullanicinin
    /// onceligini kaybetmektense uzak tarafin bir olayini feda etmek yeglenir.
    unsafe fn is_physical(l: LPARAM) -> bool {
        let mut header: RAWINPUTHEADER = std::mem::zeroed();
        let mut size = std::mem::size_of::<RAWINPUTHEADER>() as u32;
        let got = GetRawInputData(
            l as HRAWINPUT,
            RID_HEADER,
            &mut header as *mut _ as _,
            &mut size,
            std::mem::size_of::<RAWINPUTHEADER>() as u32,
        );
        if got == u32::MAX {
            return true;
        }
        !header.hDevice.is_null()
    }

    unsafe extern "system" fn wnd_proc(
        hwnd: HWND,
        msg: UINT,
        w: WPARAM,
        l: LPARAM,
    ) -> LRESULT {
        if msg == WM_INPUT && is_physical(l) {
            super::note_local_input();
        }
        DefWindowProcW(hwnd, msg, w, l)
    }

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    pub fn start() {
        if HOOKED.swap(true, Ordering::SeqCst) {
            return;
        }
        let (tx, rx) = channel();
        std::thread::spawn(move || unsafe {
            let class = wide("SkyyDeskLocalInput");
            let mut wc: WNDCLASSEXW = std::mem::zeroed();
            wc.cbSize = std::mem::size_of::<WNDCLASSEXW>() as u32;
            wc.lpfnWndProc = Some(wnd_proc);
            wc.lpszClassName = class.as_ptr();
            RegisterClassExW(&wc);

            // Yalniz ileti alan pencere: ekranda hicbir sey gorunmuyor.
            let hwnd = CreateWindowExW(
                0,
                class.as_ptr(),
                class.as_ptr(),
                0,
                0,
                0,
                0,
                0,
                HWND_MESSAGE,
                NULL as _,
                NULL as _,
                NULL as _,
            );
            if hwnd.is_null() {
                let _ = tx.send(false);
                return;
            }

            let devices = [
                RAWINPUTDEVICE {
                    usUsagePage: HID_USAGE_PAGE_GENERIC,
                    usUsage: HID_USAGE_MOUSE,
                    dwFlags: RIDEV_INPUTSINK,
                    hwndTarget: hwnd,
                },
                RAWINPUTDEVICE {
                    usUsagePage: HID_USAGE_PAGE_GENERIC,
                    usUsage: HID_USAGE_KEYBOARD,
                    dwFlags: RIDEV_INPUTSINK,
                    hwndTarget: hwnd,
                },
            ];
            if RegisterRawInputDevices(
                devices.as_ptr(),
                devices.len() as u32,
                std::mem::size_of::<RAWINPUTDEVICE>() as u32,
            ) == 0
            {
                DestroyWindow(hwnd);
                let _ = tx.send(false);
                return;
            }
            let _ = tx.send(true);

            let mut msg: MSG = std::mem::zeroed();
            while HOOKED.load(Ordering::SeqCst) {
                if GetMessageW(&mut msg, NULL as _, 0, 0) <= 0 {
                    break;
                }
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
            DestroyWindow(hwnd);
        });

        match rx.recv_timeout(std::time::Duration::from_secs(3)) {
            Ok(true) => log::info!("local input priority: watching raw input"),
            _ => {
                HOOKED.store(false, Ordering::SeqCst);
                log::warn!("local input priority: raw input unavailable, remote input unrestricted");
            }
        }
    }

    pub fn stop() {
        if HOOKED.swap(false, Ordering::SeqCst) {
            LOCAL_INPUT_AT.store(0, Ordering::Relaxed);
        }
    }
}

#[cfg(not(windows))]
mod imp {
    // Linux'ta X11/uinput, macOS'ta CGEventTap ile ayni sey yapilabilir;
    // henuz yazilmadi. Bu platformlarda davranis eskisi gibi kaliyor.
    pub fn start() {}
    pub fn stop() {}
}

pub use imp::{start, stop};

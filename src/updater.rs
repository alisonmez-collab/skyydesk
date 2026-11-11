use crate::{common::do_check_software_update, hbbs_http::create_http_client_with_url_strict};
use hbb_common::{bail, config, log, ResultType};
use std::{
    io::Write,
    path::{Component, Path, PathBuf},
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{channel, Receiver, Sender},
        Mutex,
    },
    time::{Duration, Instant},
};

enum UpdateMsg {
    CheckUpdate,
    Exit,
}

lazy_static::lazy_static! {
    static ref TX_MSG : Mutex<Sender<UpdateMsg>> = Mutex::new(start_auto_update_check());
}

static CONTROLLING_SESSION_COUNT: AtomicUsize = AtomicUsize::new(0);

const DUR_ONE_DAY: Duration = Duration::from_secs(60 * 60 * 24);

// Guncelleme kontrol araligi. Gunde bir kez azdi: gece yayinlanan bir duzeltme,
// gun boyu acik duran makinelere ertesi gune kadar ulasmiyordu. Saatte bir
// kontrol yalnizca bir satirlik surum.txt istegi; baglanti varken zaten
// atlaniyor, yani calisan bir oturumu bolmuyor.
const DUR_KONTROL: Duration = Duration::from_secs(60 * 60);

pub fn update_controlling_session_count(count: usize) {
    CONTROLLING_SESSION_COUNT.store(count, Ordering::SeqCst);
}

#[allow(dead_code)]
pub fn start_auto_update() {
    let _sender = TX_MSG.lock().unwrap();
}

#[allow(dead_code)]
pub fn manually_check_update() -> ResultType<()> {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::CheckUpdate)?;
    Ok(())
}

#[allow(dead_code)]
pub fn stop_auto_update() {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::Exit).unwrap_or_default();
}

#[inline]
fn has_no_active_conns() -> bool {
    let conns = crate::Connection::alive_conns();
    conns.is_empty() && has_no_controlling_conns()
}

#[cfg(any(not(target_os = "windows"), feature = "flutter"))]
fn has_no_controlling_conns() -> bool {
    CONTROLLING_SESSION_COUNT.load(Ordering::SeqCst) == 0
}

#[cfg(not(any(not(target_os = "windows"), feature = "flutter")))]
fn has_no_controlling_conns() -> bool {
    let app_exe = format!("{}.exe", crate::get_app_name().to_lowercase());
    for arg in [
        "--connect",
        "--play",
        "--file-transfer",
        "--view-camera",
        "--port-forward",
        "--rdp",
    ] {
        if !crate::platform::get_pids_of_process_with_first_arg(&app_exe, arg).is_empty() {
            return false;
        }
    }
    true
}

fn start_auto_update_check() -> Sender<UpdateMsg> {
    let (tx, rx) = channel();
    std::thread::spawn(move || start_auto_update_check_(rx));
    return tx;
}

// SkyDesk kendi surumunu kendi sunucusundan gunceller.
//
// Upstream'in surum ucu kaldirildi (istegi cihaz parmak izi tasiyordu, bkz.
// common.rs) ve yerine hicbir sey konmamisti: sahadaki bir kurulum, duzeltme
// yayinlansa bile eski kodda kaliyor, guncellemeyi birinin elle yapmasi
// gerekiyordu. 12.08.2026'da gun boyu bunun bedeli odendi.
//
// Uc tek satirlik bir metin: yayindaki paketin surumu ve derleme damgasi.
// Kendi damgamizdan farkliysa kurulum betigi uygulamanin KURULU OLDUGU
// klasore indirilip calistiriliyor. Betigi indirmek yerine isi burada
// tekrarlamak ikinci bir kurulum yolu acardi; Setup.cmd zaten sahada
// dogrulanmis olan yol (#82): paketi indirir, eski servisi durdurur, sessizce
// kurar ve uygulamayi yeniden acar.
#[cfg(target_os = "windows")]
const SURUM_URL: &str = "https://skyydesk.com/downloads/surum.txt";

#[cfg(target_os = "windows")]
const PAKET_URL: &str = "https://skyydesk.com/downloads/SkyyDesk-Windows.exe";

// Test kanali. Yeni surum once buraya konur; kurulusu "test" kanalinda olan
// makineler (ELPO belirler, Cortex) onu canlidan ONCE alir. Surum orada
// denenip onaylaninca canliya cikar ve herkes kendiliginden gunceller.
// Boylece deneme icin hicbir makineye elle kurulum yapilmaz (29.09.2026).
#[cfg(target_os = "windows")]
const TEST_SURUM_URL: &str = "https://test.skyydesk.com/downloads/surum.txt";

#[cfg(target_os = "windows")]
const TEST_PAKET_URL: &str = "https://test.skyydesk.com/downloads/SkyyDesk-Windows.exe";

// Kurulum betigi UYGULAMANIN ICINDE tasiniyor, sunucudan indirilmiyor.
//
// Once indiriliyordu ve bu iki yerden kirilgandi: sunucudaki dosya silinse ya
// da adi degisse guncelleme sessizce olurdu, ayrica ayni is iki kaynaktan
// (depodaki dosya ve sunucudaki kopya) beslendigi icin bir gun ayrisirlardi.
// Simdi tek kaynak var -- res/SkyyDesk-Setup.cmd -- ve o hem exe'nin icine
// gomuluyor hem de sunucuya ayni dosyadan yayinlaniyor. Klasorde betik yoksa
// ya da eskiyse uygulama onu KENDISI yaziyor (kullanici istegi, 13.08.2026).
//
// CRLF: cmd, LF satir sonlu betikte "komut taninmadi" verir. Dosya depoda
// CRLF ile duruyor; include_str! icerigi oldugu gibi tasidigi icin burada
// ayrica donusturmeye gerek yok, ama dosyanin CRLF kaldigi
// .gitattributes ile korunuyor.
#[cfg(target_os = "windows")]
const SETUP_CMD: &str = include_str!("../res/SkyyDesk-Setup.cmd");

// AYNI surum icin sinirsiz kurulum denemesi = makineyi kilitleyen dongu.
//
// 15.08.2026, sahada: kurulum bir sebeple tamamlanmayinca (yukseltme onayi
// gelmiyor, dosya kilitli kaliyor, kurulum yarida oluyor) uygulama her
// acilista guncellemeyi YENIDEN baslatiyordu; kurulum betigi de once calisan
// sureclere taskkill atip sonra uygulamayi geri aciyordu. Boylece kurulum ->
// oldur -> ac -> kurulum diye donen, ust uste binen kurulumlarin birbirini
// oldurdugu icin hicbiri bitmeyen bir dongu olustu. Kullanicinin gordugu:
// "durmadan baslatiliyor, aciliyor, baslamiyor" -- ve her turda 23 MB indirme.
//
// Betigin yazma zamanina bakan 180 saniyelik kontrol bunu YAKALAMIYOR: betik
// yalniz icerigi degistiginde yeniden yaziliyor, ikinci turda icerik ayni
// oldugu icin zaman damgasi tazelenmiyor.
//
// Kayit: "<damga>|<unix_saniye>|<deneme_sayisi>". Ayni damga icin 10 dakika
// icinde tekrar denenmez, 3 denemeden sonra hic denenmez -- sunucuya YENI bir
// damga cikana kadar. Boylece basarisiz bir yayin makineyi kilitlemiyor,
// yalnizca guncellenmemis kaliyor.
#[cfg(target_os = "windows")]
fn deneme_kaydi_yolu() -> Option<PathBuf> {
    let kok = std::env::var("LOCALAPPDATA").ok()?;
    Some(PathBuf::from(kok).join("SkyyDesk").join(".guncelleme"))
}

#[cfg(target_os = "windows")]
fn simdi_saniye() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Kayittaki damga `uzak` ile ayniysa (zaman, deneme) doner.
#[cfg(target_os = "windows")]
fn onceki_deneme(uzak: &str) -> Option<(u64, u32)> {
    let icerik = std::fs::read_to_string(deneme_kaydi_yolu()?).ok()?;
    let mut p = icerik.trim().splitn(3, '|');
    if p.next()? != uzak {
        return None;
    }
    let zaman = p.next().unwrap_or("0").trim().parse().unwrap_or(0);
    let sayi = p.next().unwrap_or("0").trim().parse().unwrap_or(0);
    Some((zaman, sayi))
}

#[cfg(target_os = "windows")]
fn deneme_siniri_asildi(uzak: &str) -> bool {
    match onceki_deneme(uzak) {
        Some((zaman, sayi)) => {
            simdi_saniye().saturating_sub(zaman) < 600 || sayi >= 3
        }
        None => false,
    }
}

#[cfg(target_os = "windows")]
fn denemeyi_kaydet(uzak: &str) {
    let yol = match deneme_kaydi_yolu() {
        Some(y) => y,
        None => return,
    };
    let sayi = onceki_deneme(uzak).map(|(_, s)| s).unwrap_or(0);
    if let Some(dizin) = yol.parent() {
        let _ = std::fs::create_dir_all(dizin);
    }
    let _ = std::fs::write(&yol, format!("{}|{}|{}", uzak, simdi_saniye(), sayi + 1));
}

/// Damgayi "surum" ve "tarih" diye ayirir: "1.4.9 2026-08-13 01:14".
fn damga_ayir(s: &str) -> (Vec<u64>, &str) {
    let mut p = s.splitn(2, ' ');
    let surum = p.next().unwrap_or("");
    let tarih = p.next().unwrap_or("").trim();
    let sayilar = surum
        .split('.')
        .map(|x| x.trim().parse::<u64>().unwrap_or(0))
        .collect();
    (sayilar, tarih)
}

/// Uzaktaki damga bizimkinden yeni mi? Surum SAYIYLA, esitlikte tarih metinle.
fn daha_yeni(uzak: &str, bizim: &str) -> bool {
    let (us, ut) = damga_ayir(uzak);
    let (bs, bt) = damga_ayir(bizim);
    let n = us.len().max(bs.len());
    for i in 0..n {
        let a = us.get(i).copied().unwrap_or(0);
        let b = bs.get(i).copied().unwrap_or(0);
        if a != b {
            return a > b;
        }
    }
    ut > bt
}

// Guncelleme baslatildiysa true doner; cagiran surece cikar.
/// Kurulusun guncelleme politikasi (sunucudan).
///
/// `mod` uc degerden biri: "otomatik" (varsayilan), "planli", "elle".
/// Planlida `saat`/`sure` bakim penceresini, `gunler` ("0,6" gibi; 0=Pazar)
/// hangi gunleri gosterir. Bos gunler = her gun.
#[cfg(target_os = "windows")]
#[derive(Debug, Clone)]
struct GuncellemePolitikasi {
    mod_: String,
    saat: u32,
    sure: u32,
    gunler: String,
    kanal: String,
}

#[cfg(target_os = "windows")]
impl GuncellemePolitikasi {
    /// (surum.txt, paket) adresleri. Test disindaki her deger kararli sayilir.
    fn adresler(&self) -> (&'static str, &'static str) {
        if self.kanal == "test" {
            (TEST_SURUM_URL, TEST_PAKET_URL)
        } else {
            (SURUM_URL, PAKET_URL)
        }
    }
}

#[cfg(target_os = "windows")]
impl Default for GuncellemePolitikasi {
    fn default() -> Self {
        Self {
            mod_: "otomatik".to_owned(),
            saat: 2,
            sure: 4,
            gunler: String::new(),
            kanal: "kararli".to_owned(),
        }
    }
}

/// Politikayi sunucudan okur. Ulasilamazsa OTOMATIK doner.
///
/// Neden otomatik: politika okunamadi diye makineyi eski surumde birakmak,
/// bir guvenlik duzeltmesini geciktirmek olur. Kurulus "kapali" dediyse o
/// bilgi sunucuda durur ve bir sonraki turda gelir.
#[cfg(target_os = "windows")]
fn guncelleme_politikasi() -> GuncellemePolitikasi {
    let taban = crate::get_api_server(
        config::Config::get_option("api-server"),
        config::Config::get_option("custom-rendezvous-server"),
    );
    if taban.is_empty() {
        return GuncellemePolitikasi::default();
    }
    let url = format!(
        "{}/api/guncelleme/istemci?id={}",
        taban,
        config::Config::get_id()
    );
    let istek = match create_http_client_with_url_strict(&url) {
        Ok(c) => c,
        Err(_) => return GuncellemePolitikasi::default(),
    };
    let govde = match istek.get(&url).timeout(Duration::from_secs(10)).send() {
        Ok(y) => y.text().unwrap_or_default(),
        Err(e) => {
            log::debug!("update: politika okunamadi ({e}), otomatik varsayiliyor");
            return GuncellemePolitikasi::default();
        }
    };
    let v: serde_json::Value = match serde_json::from_str(&govde) {
        Ok(v) => v,
        Err(_) => return GuncellemePolitikasi::default(),
    };
    let d = &v["data"];
    let mut p = GuncellemePolitikasi::default();
    if let Some(m) = d["mod"].as_str() {
        if m == "planli" || m == "elle" || m == "otomatik" {
            p.mod_ = m.to_owned();
        }
    }
    if let Some(n) = d["saat"].as_u64() {
        if n <= 23 {
            p.saat = n as u32;
        }
    }
    if let Some(n) = d["sure"].as_u64() {
        if n >= 1 && n <= 24 {
            p.sure = n as u32;
        }
    }
    if let Some(g) = d["gunler"].as_str() {
        p.gunler = g.to_owned();
    }
    if d["kanal"].as_str() == Some("test") {
        p.kanal = "test".to_owned();
    }
    p
}

/// Simdi bakim penceresinde miyiz? Yerel saate gore.
#[cfg(target_os = "windows")]
fn pencerede_mi(p: &GuncellemePolitikasi) -> bool {
    let simdi = chrono::Local::now();
    let gun = simdi.format("%w").to_string(); // 0=Pazar
    let gunler: Vec<&str> = p
        .gunler
        .split(',')
        .map(|x| x.trim())
        .filter(|x| !x.is_empty())
        .collect();
    if !gunler.is_empty() && !gunler.contains(&gun.as_str()) {
        return false;
    }
    let saat: u32 = simdi.format("%H").to_string().parse().unwrap_or(0);
    let bas = p.saat;
    let bit = (p.saat + p.sure) % 24;
    if p.sure >= 24 {
        return true;
    }
    if bas <= bit {
        saat >= bas && saat < bit
    } else {
        // Pencere gece yarisini asiyor (orn. 23:00 + 4 saat -> 03:00).
        saat >= bas || saat < bit
    }
}

/// Politika kuruluma izin veriyor mu? Vermiyorsa SEBEBI gunluge yazilir --
/// "neden guncellenmedi" sorusu sahada ilk sorulan sey.
#[cfg(target_os = "windows")]
fn kurulum_serbest(p: &GuncellemePolitikasi) -> bool {
    match p.mod_.as_str() {
        "elle" => {
            log::info!("update: kurulus politikasi 'kapali', kurulum yapilmiyor (surum bildirimi kalir)");
            false
        }
        "planli" => {
            if pencerede_mi(p) {
                true
            } else {
                log::info!(
                    "update: bakim penceresi disinda (saat {}, {} saat, gunler '{}'), kurulum bekliyor",
                    p.saat, p.sure, p.gunler
                );
                false
            }
        }
        _ => true,
    }
}

#[cfg(target_os = "windows")]
pub fn skydesk_check_update(zaman_asimi: Duration) -> ResultType<bool> {
    // Tasinabilir (kurulu olmayan) calistirmada guncelleme yapilmaz: kullanici
    // exe'yi nereye koyduysa oradan calistiriyor, uzerine yazmak dogru degil.
    if !crate::platform::is_installed() {
        return Ok(false);
    }
    let exe = std::env::current_exe()?;
    let dir = match exe.parent() {
        Some(d) => d.to_path_buf(),
        None => bail!("update: install directory not found"),
    };
    let betik = dir.join("SkyyDesk-Setup.cmd");
    // Ayni anda iki surec (arayuz ve servis) kontrol edebiliyor. Betik az once
    // yazildiysa kurulum zaten basladi demektir; ikinci kez calistirmak iki
    // kurulumu ust uste bindirirdi.
    if let Ok(m) = std::fs::metadata(&betik) {
        if let Ok(t) = m.modified() {
            if t.elapsed().map(|e| e < Duration::from_secs(180)).unwrap_or(false) {
                return Ok(false);
            }
        }
    }
    // Politika surumden ONCE okunuyor: hangi surum.txt'ye bakilacagini kanal
    // belirliyor. Politika okunamazsa kararli kanal + otomatik doner.
    let politika = guncelleme_politikasi();
    let (surum_url, paket_url) = politika.adresler();
    let uzak = create_http_client_with_url_strict(surum_url)?
        .get(surum_url)
        .timeout(zaman_asimi)
        .send()?
        .text()?;
    let uzak = uzak.trim().to_string();
    let bizim = format!("{} {}", crate::VERSION, crate::BUILD_DATE);
    if uzak.is_empty() {
        return Ok(false);
    }
    // Sunucudaki ESKI ya da AYNI ise dokunmuyoruz.
    //
    // METIN KIYASI YETMIYOR. Damga "1.4.9 2026-08-13 01:14" bicimindedir ve
    // tarih kismi metin olarak dogru siralanir; ama surum numarasi oyle
    // siralanmaz: "1.4.10" < "1.4.9" cikar, cunku dorduncu karakterde '1'
    // ile '9' karsilasir. 1.4.9'dan 1.4.10'a gecilen gun her istemci kendini
    // daha yeni sanip guncellemeyi ATLARDI -- ve bu, ancak guncelleme
    // gerektigi gun fark edilecek bir sessiz ariza olurdu. Surum sayilarla,
    // esitlik halinde tarih metinle karsilastiriliyor.
    if !daha_yeni(&uzak, &bizim) {
        return Ok(false);
    }
    // Yeni surum VAR. Kurulusun politikasi kuruluma izin vermiyorsa burada
    // duruyoruz; arayuzdeki "yeni surum var" bildirimi check_update ile
    // ayrica geliyor, yani kullanici haberdar olur ama makine calisma
    // saatinde kendini yeniden baslatmaz.
    if !kurulum_serbest(&politika) {
        return Ok(false);
    }
    // Kurulum tamamlanmiyorsa dur; yoksa makine kurulum dongusune giriyor.
    if deneme_siniri_asildi(&uzak) {
        log::warn!("update: {} icin deneme siniri asildi, kurulum baslatilmiyor", uzak);
        return Ok(false);
    }
    // Betik kurulum klasorunde guncel tutuluyor ama ARTIK OTOMATIK GUNCELLEME
    // ONU CALISTIRMIYOR (asagiya bak). Orada durmasinin sebebi, makinede bir
    // sey bozulursa elle kurtarma yolu olmasi.
    let yazmali = match std::fs::read_to_string(&betik) {
        Ok(mevcut) => mevcut != SETUP_CMD,
        Err(_) => true,
    };
    if yazmali {
        std::fs::write(&betik, SETUP_CMD.as_bytes())?;
    }

    // GUNCELLEMEYI SERVIS YAPAR, ARAYUZ DEGIL.
    //
    // Servis LOCAL SYSTEM olarak calisiyor; Program Files'a yazma yetkisi
    // zaten var. Arayuz ise kullanicinin haklariyla calisiyor ve o yetki
    // yok. Onceden guncellemeyi arayuz bir cmd betigi acarak yapmaya
    // calisiyordu: betik "--silent-install" cagiriyor, o da KENDILIGINDEN
    // yukseltme ISTEMIYOR (platform/windows.rs install_me icinde run_uac
    // yok), dolayisiyla Program Files'a yazamayip sessizce dusuyordu.
    // Ekranda "Kuruluyor, uygulama birazdan acilacak" yazisi kaliyor, onay
    // penceresi hic cikmiyor, kurulum hic olmuyordu (15.08.2026, sahada).
    //
    // Uzaktan erisim urununde makinenin basinda kimse olmayabilir; guncelleme
    // bir insanin "Evet"ine bagli olamaz. Bu yuzden isi, zaten yetkili olan
    // servis ustleniyor: paketi kendisi indiriyor ve "--update" ile
    // calistiriyor. update_me() dosyalari kopyalayip servisi yeniden baslatiyor
    // ve arayuzu KULLANICININ oturumunda geri aciyor.
    if !crate::platform::is_root() {
        log::info!("update: {} -> {}, kurulumu servis yapacak", bizim, uzak);
        return Ok(false);
    }
    denemeyi_kaydet(&uzak);
    let paket = paketi_indir(paket_url)?;
    log::info!(
        "update: {} -> {} (kanal {}), running {:?} --update",
        bizim, uzak, politika.kanal, paket
    );
    std::process::Command::new(&paket).arg("--update").spawn()?;
    Ok(true)
}

/// Yeni paketi gecici klasore indirir, yolunu doner.
#[cfg(target_os = "windows")]
fn paketi_indir(paket_url: &str) -> ResultType<PathBuf> {
    let hedef = std::env::temp_dir().join("SkyyDesk-Guncelleme.exe");
    let mut yanit = create_http_client_with_url_strict(paket_url)?
        .get(paket_url)
        .timeout(Duration::from_secs(600))
        .send()?;
    if !yanit.status().is_success() {
        bail!("update: paket indirilemedi, {}", yanit.status());
    }
    let mut dosya = std::fs::File::create(&hedef)?;
    std::io::copy(&mut yanit, &mut dosya)?;
    dosya.sync_all()?;
    drop(dosya);
    // Yarim inen dosyayi calistirmak, kurulumu bozup makineyi kurulumsuz
    // birakirdi. Paket 20 MB'in ustunde; bunun altindaki her sey bozuktur.
    let boyut = std::fs::metadata(&hedef)?.len();
    if boyut < 20_000_000 {
        bail!("update: paket eksik indi ({} bayt)", boyut);
    }
    Ok(hedef)
}

// Arayuz acilirken guncelleme YAPILMAZ, yalnizca durum gunluge yazilir.
//
// Bir donem burada kurulum baslatiliyor ve yeni surum varsa pencere hic
// acilmiyordu. Artik kurulumu servis yapiyor (skydesk_check_update): arayuzun
// Program Files'a yazma yetkisi yok, oradan baslatilan kurulum sessizce
// dusuyordu. Ayrica her acilista sunucuyu beklemek acilisi gereksiz
// geciktiriyordu.
//
// Donus degeri hep false: acilisi bu fonksiyon durdurmuyor.
#[cfg(target_os = "windows")]
pub fn skydesk_update_on_start() -> bool {
    std::thread::spawn(|| {
        // Kurulumu servis yapar; arayuzun yetkisi yok. Ama beklemesin diye
        // servise "simdi bak" deniyor. Kullanici uygulamayi kapatip actiginda
        // yeni surumun hemen gelmesini bekliyor (16.08.2026); servisin
        // saatlik dongusunu beklemek "guncellemedi" gibi gorunuyordu.
        if let Err(e) = crate::ipc::guncellemeyi_simdi_kontrol_et() {
            log::info!("update check request failed: {}", e);
            // Servise ulasilamadiysa (durdurulmus olabilir) kendimiz bakariz;
            // yetki yoksa zaten kurulum baslatmaz, yalniz gunluge yazar.
            if let Err(e2) = skydesk_check_update(Duration::from_secs(15)) {
                log::info!("update check on start skipped: {}", e2);
            }
        }
    });
    false
}

fn start_auto_update_check_(rx_msg: Receiver<UpdateMsg>) {
    // Guncellemeyi servis yapiyor (skydesk_check_update), bu dongu de serviste
    // donuyor. Ilk kontrol ACILISTA yapilir: makine kapaliyken bir duzeltme
    // yayinlandiysa acildiginda alsin. Once bu satir yoktu ve ilk kontrol
    // dongunun ilk beklemesinden SONRA geliyordu -- yani makine bir gun boyunca
    // eski surumde kaliyordu.
    std::thread::sleep(Duration::from_secs(30));
    #[cfg(target_os = "windows")]
    if let Err(e) = skydesk_check_update(Duration::from_secs(15)) {
        log::error!("SkyDesk update check failed: {}", e);
    }
    if let Err(e) = check_update(false) {
        log::error!("Error checking for updates: {}", e);
    }

    const MIN_INTERVAL: Duration = Duration::from_secs(60 * 10);
    const RETRY_INTERVAL: Duration = Duration::from_secs(60 * 30);
    let mut last_check_time = Instant::now();
    let mut check_interval = DUR_KONTROL;
    loop {
        let recv_res = rx_msg.recv_timeout(check_interval);
        match &recv_res {
            Ok(UpdateMsg::CheckUpdate) | Err(_) => {
                if last_check_time.elapsed() < MIN_INTERVAL {
                    // log::debug!("Update check skipped due to minimum interval.");
                    continue;
                }
                // Don't check update if there are alive connections.
                if !has_no_active_conns() {
                    check_interval = RETRY_INTERVAL;
                    continue;
                }
                #[cfg(target_os = "windows")]
                if let Err(e) = skydesk_check_update(Duration::from_secs(15)) {
                    log::error!("SkyDesk update check failed: {}", e);
                }
                if let Err(e) = check_update(matches!(recv_res, Ok(UpdateMsg::CheckUpdate))) {
                    log::error!("Error checking for updates: {}", e);
                    check_interval = RETRY_INTERVAL;
                } else {
                    last_check_time = Instant::now();
                    check_interval = DUR_KONTROL;
                }
            }
            Ok(UpdateMsg::Exit) => break,
        }
    }
}

fn check_update(manually: bool) -> ResultType<()> {
    #[cfg(target_os = "windows")]
    let update_msi = crate::platform::is_msi_installed()? && !crate::is_custom_client();
    if !(manually || config::Config::get_bool_option(config::keys::OPTION_ALLOW_AUTO_UPDATE)) {
        return Ok(());
    }
    if do_check_software_update().is_err() {
        // ignore
        return Ok(());
    }

    let update_url = crate::common::SOFTWARE_UPDATE_URL.lock().unwrap().clone();
    if update_url.is_empty() {
        log::debug!("No update available.");
    } else {
        let download_url = update_url.replace("tag", "download");
        let version = download_url.split('/').last().unwrap_or_default();
        #[cfg(target_os = "windows")]
        let download_url = if cfg!(feature = "flutter") {
            let Some(arch) = crate::platform::windows::release_arch_suffix() else {
                bail!(
                    "Unsupported Windows release architecture: {}",
                    std::env::consts::ARCH
                );
            };
            format!(
                "{}/rustdesk-{}-{}.{}",
                download_url,
                version,
                arch,
                if update_msi { "msi" } else { "exe" }
            )
        } else {
            format!("{}/rustdesk-{}-x86-sciter.exe", download_url, version)
        };
        log::debug!("New version available: {}", &version);
        let client = create_http_client_with_url_strict(&download_url)?;
        let Some(file_path) = get_download_file_from_url(&download_url) else {
            bail!("Failed to get the file path from the URL: {}", download_url);
        };
        let mut is_file_exists = false;
        if file_path.exists() {
            // Check if the file size is the same as the server file size
            // If the file size is the same, we don't need to download it again.
            let file_size = std::fs::metadata(&file_path)?.len();
            let response = client.head(&download_url).send()?;
            if !response.status().is_success() {
                bail!("Failed to get the file size: {}", response.status());
            }
            let total_size = response
                .headers()
                .get(reqwest::header::CONTENT_LENGTH)
                .and_then(|ct_len| ct_len.to_str().ok())
                .and_then(|ct_len| ct_len.parse::<u64>().ok());
            let Some(total_size) = total_size else {
                bail!("Failed to get content length");
            };
            if file_size == total_size {
                is_file_exists = true;
            } else {
                std::fs::remove_file(&file_path)?;
            }
        }
        if !is_file_exists {
            let response = client.get(&download_url).send()?;
            if !response.status().is_success() {
                bail!(
                    "Failed to download the new version file: {}",
                    response.status()
                );
            }
            let file_data = response.bytes()?;
            let mut file = std::fs::File::create(&file_path)?;
            file.write_all(&file_data)?;
        }
        // We have checked if the `conns` is empty before, but we need to check again.
        // No need to care about the downloaded file here, because it's rare case that the `conns` are empty
        // before the download, but not empty after the download.
        if has_no_active_conns() {
            #[cfg(target_os = "windows")]
            update_new_version(update_msi, &version, &file_path);
        }
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn update_new_version(update_msi: bool, version: &str, file_path: &PathBuf) {
    log::debug!(
        "New version is downloaded, update begin, update msi: {update_msi}, version: {version}, file: {:?}",
        file_path.to_str()
    );
    if let Some(p) = file_path.to_str() {
        if let Some(session_id) = crate::platform::get_current_process_session_id() {
            if update_msi {
                match crate::platform::update_me_msi(p, true) {
                    Ok(_) => {
                        log::debug!("New version \"{}\" updated.", version);
                    }
                    Err(e) => {
                        log::error!(
                            "Failed to install the new msi version  \"{}\": {}",
                            version,
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                    }
                }
            } else {
                let custom_client_staging_dir = if crate::is_custom_client() {
                    let custom_client_staging_dir =
                        crate::platform::get_custom_client_staging_dir();
                    if let Err(e) = crate::platform::handle_custom_client_staging_dir_before_update(
                        &custom_client_staging_dir,
                    ) {
                        log::error!(
                            "Failed to handle custom client staging dir before update: {}",
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                        return;
                    }
                    Some(custom_client_staging_dir)
                } else {
                    // Clean up any residual staging directory from previous custom client
                    let staging_dir = crate::platform::get_custom_client_staging_dir();
                    hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                        &staging_dir
                    ));
                    None
                };
                let update_launched = match crate::platform::launch_privileged_process(
                    session_id,
                    &format!("{} --update", p),
                ) {
                    Ok(h) => {
                        if h.is_null() {
                            log::error!("Failed to update to the new version: {}", version);
                            false
                        } else {
                            log::debug!("New version \"{}\" is launched.", version);
                            true
                        }
                    }
                    Err(e) => {
                        log::error!("Failed to run the new version: {}", e);
                        false
                    }
                };
                if !update_launched {
                    if let Some(dir) = custom_client_staging_dir {
                        hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                            &dir
                        ));
                    }
                    std::fs::remove_file(&file_path).ok();
                }
            }
        } else {
            log::error!(
                "Failed to get the current process session id, Error {}",
                std::io::Error::last_os_error()
            );
            std::fs::remove_file(&file_path).ok();
        }
    } else {
        // unreachable!()
        log::error!(
            "Failed to convert the file path to string: {}",
            file_path.display()
        );
    }
}

pub fn get_update_download_file_from_url(url: &str) -> Option<PathBuf> {
    let parsed = url::Url::parse(url).ok()?;
    // Check the raw prefix before Url normalizes default ports.
    if !url.starts_with("https://github.com/")
        || parsed.scheme() != "https"
        || parsed.host_str() != Some("github.com")
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.port().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        return None;
    }

    let mut segments = parsed.path_segments()?;
    let owner = segments.next()?;
    let repo = segments.next()?;
    let releases = segments.next()?;
    let download = segments.next()?;
    let tag = segments.next()?;
    let filename = segments.next()?;

    if owner != "rustdesk"
        || repo != "rustdesk"
        || releases != "releases"
        || download != "download"
        || tag.is_empty()
        || segments.next().is_some()
        || !is_plain_update_filename(filename)
    {
        return None;
    }

    Some(std::env::temp_dir().join(filename))
}

fn is_plain_update_filename(filename: &str) -> bool {
    if filename.is_empty()
        || filename.contains('/')
        || filename.contains('\\')
        || filename.contains(':')
    {
        return false;
    }

    let mut components = Path::new(filename).components();
    matches!(
        components.next(),
        Some(Component::Normal(name)) if name.to_str() == Some(filename)
    ) && components.next().is_none()
}

pub fn get_download_file_from_url(url: &str) -> Option<PathBuf> {
    get_update_download_file_from_url(url)
}

#[cfg(test)]
mod tests {
    use super::get_download_file_from_url;

    #[test]
    fn update_download_file_accepts_expected_github_asset_urls() {
        let file = get_download_file_from_url(
            "https://github.com/rustdesk/rustdesk/releases/download/1.4.0/rustdesk-1.4.0-x86_64.dmg",
        )
        .expect("valid GitHub release asset URL");

        assert_eq!(
            file.file_name().and_then(|name| name.to_str()),
            Some("rustdesk-1.4.0-x86_64.dmg")
        );
    }

    #[test]
    fn update_download_file_rejects_untrusted_or_malformed_urls() {
        for url in [
            "http://github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe",
            "https://example.com/rustdesk.exe",
            "https://github.com/other/project/releases/download/1/rustdesk.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1/",
            "https://github.com/rustdesk/rustdesk/releases/download/1/nested/rustdesk.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1/C:rustdesk.exe",
            "https://user@github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe",
            "https://github.com:443/rustdesk/rustdesk/releases/download/1/rustdesk.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe?download=1",
            "https://github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe#download",
            "not a url",
        ] {
            assert!(get_download_file_from_url(url).is_none(), "{url}");
        }
    }
}

#[cfg(all(test, target_os = "windows"))]
mod skydesk_kanal_testleri {
    use super::*;

    // Test surumu bir musteriye ancak kurulusu acikca "test" kanalindaysa
    // gitmeli. Bos, bilinmeyen ya da okunamayan kanal kararlidir.
    #[test]
    fn yalniz_test_kanali_test_adresine_gider() {
        let mut p = GuncellemePolitikasi::default();
        assert_eq!(p.adresler(), (SURUM_URL, PAKET_URL));
        p.kanal = "test".to_owned();
        assert_eq!(p.adresler(), (TEST_SURUM_URL, TEST_PAKET_URL));
        p.kanal = "Test".to_owned();
        assert_eq!(p.adresler(), (SURUM_URL, PAKET_URL));
    }
}

#[cfg(test)]
mod skydesk_surum_testleri {
    use super::{daha_yeni};

    // Bu testin varlik sebebi: onceki surum damgalari METIN olarak
    // karsilastiriliyordu ve "1.4.10" < "1.4.9" cikiyordu. Yani 1.4.9'dan
    // 1.4.10'a gecilen gun hicbir istemci guncellenmezdi ve bunu ancak
    // guncelleme gerektigi gun fark ederdik.
    #[test]
    fn iki_haneli_yama_surumu_eski_sanilmaz() {
        assert!(daha_yeni("1.4.10 2026-08-14 10:00", "1.4.9 2026-08-13 02:21"));
        assert!(daha_yeni("1.10.0 2026-01-01 00:00", "1.9.9 2026-12-31 23:59"));
    }

    #[test]
    fn ayni_surumde_tarih_karar_verir() {
        assert!(daha_yeni("1.4.9 2026-08-14 10:00", "1.4.9 2026-08-13 02:21"));
        assert!(!daha_yeni("1.4.9 2026-08-13 02:21", "1.4.9 2026-08-13 02:21"));
        assert!(!daha_yeni("1.4.9 2026-08-12 09:00", "1.4.9 2026-08-13 02:21"));
    }

    #[test]
    fn eski_surum_yeni_tarihli_olsa_bile_yuklenmez() {
        // Sunucuya yanlislikla eski bir paket konursa geri donus olmamali.
        assert!(!daha_yeni("1.4.8 2026-12-31 23:59", "1.4.9 2026-08-13 02:21"));
    }

    #[test]
    fn bozuk_damga_guncelleme_baslatmaz() {
        assert!(!daha_yeni("", "1.4.9 2026-08-13 02:21"));
        assert!(!daha_yeni("bozuk", "1.4.9 2026-08-13 02:21"));
    }
}

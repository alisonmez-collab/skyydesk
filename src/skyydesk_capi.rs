//! C interface for embedding SkyyDesk in a host application (`skyydesk.dll`, `libskyydesk.so`).
//!
//! The library is the side that is connected to: it lets SkyyDesk users reach this machine
//! from the SkyyDesk client or the web panel. Connecting out, signing in and managing users
//! stay in the client and the panel; there is no sign-in here.
//!
//! Strings crossing the boundary are UTF-8 and NUL-terminated. A pointer handed to the event
//! callback is valid only for the duration of that call, which runs on a library thread.

use hbb_common::{config::Config, log, password_security};
use std::{
    ffi::{c_char, c_int, c_void, CStr, CString},
    sync::RwLock,
};

/// `kind` passed to [`SkyyDeskEventCb`].
pub const SKYYDESK_EVENT_INCOMING: c_int = 1; // payload: client JSON; "authorized":false waits for skyydesk_accept
pub const SKYYDESK_EVENT_INCOMING_CLOSED: c_int = 2; // payload: connection id
pub const SKYYDESK_EVENT_ENROLLED: c_int = 3; // payload: {"ok":true} or {"ok":false,"error":"..."}

pub type SkyyDeskEventCb = unsafe extern "C" fn(kind: c_int, payload: *const c_char, user: *mut c_void);

lazy_static::lazy_static! {
    // The user pointer is stored as an address: it belongs to the host and is only handed back.
    static ref EVENT_CB: RwLock<Option<(SkyyDeskEventCb, usize)>> = Default::default();
}

const OPTION_ENROLL_KEY: &str = "enroll-key";
const OPTION_OWN_ID: &str = "embed-own-id";
const EMBED_APP_NAME: &str = "SkyyDeskHost";
// The core starts helper processes from its own executable, which here is the host
// application: `--check-hwcodec-config` at start-up, the others in the desktop client's
// process layout. The host knows none of these flags and would start over, spawning again.
const HELPER_ROLES: &[&str] = &["--check-hwcodec-config", "--cm", "--cm-no-ui", "--tray", "--server", "--service"];
// The role the library itself starts a copy for travels here rather than as an argument:
// the host's own argument parsing runs first and would not know it.
const HELPER_ENV: &str = "SKYYDESK_EMBED_HELPER";

/// Starts the host again the way it was started, so that an interpreter (`java -cp ...`,
/// `dotnet app.dll`) runs the same program rather than being handed an unknown flag.
#[cfg(feature = "hwcodec")]
fn hwcodec_check_command() -> Option<std::process::Command> {
    let mut command = std::process::Command::new(std::env::current_exe().ok()?);
    command.args(std::env::args_os().skip(1)).env(HELPER_ENV, "--check-hwcodec-config");
    Some(command)
}
// Server and account options are not the host's to change: they would point the machine
// somewhere other than our servers, or stand in for a sign-in this library does not have.
const LOCKED_OPTIONS: &[&str] = &[
    "access_token",
    "user_info",
    "api-server",
    "custom-rendezvous-server",
    "relay-server",
    "key",
];

fn emit(kind: c_int, payload: &str) {
    let Some((cb, user)) = *EVENT_CB.read().unwrap() else {
        return;
    };
    let Ok(payload) = CString::new(payload) else {
        return;
    };
    unsafe { cb(kind, payload.as_ptr(), user as *mut c_void) };
}

unsafe fn str_arg(p: *const c_char) -> Option<String> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok().map(str::to_owned)
}

/// Copies `s` with a trailing NUL. Returns its length, or -1 if `out` is too small.
unsafe fn copy_out(s: &str, out: *mut c_char, len: c_int) -> c_int {
    if out.is_null() || len <= 0 || s.len() + 1 > len as usize {
        return -1;
    }
    std::ptr::copy_nonoverlapping(s.as_ptr() as *const c_char, out, s.len());
    *out.add(s.len()) = 0;
    s.len() as c_int
}

/// Call once, as the first thing in `main`: helper-role copies of the host executable
/// exit inside this call. On desktop, settings live in the user's configuration folder;
/// `app_dir` is used only on platforms without one.
#[no_mangle]
pub unsafe extern "C" fn skyydesk_init(app_dir: *const c_char) -> c_int {
    let Some(app_dir) = str_arg(app_dir) else {
        return -1;
    };
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        *hbb_common::config::APP_DIR.write().unwrap() = app_dir;
        crate::load_custom_client();
        // A machine can also have the SkyyDesk client installed. Under its name the two would
        // share one settings file, one IPC socket and one ID, and each would take the other's
        // connections. Set before the first read of the configuration, which picks the path.
        *hbb_common::config::APP_NAME.write().unwrap() = EMBED_APP_NAME.to_owned();
        hbb_common::init_log(false, "skyydesk");
        let role = std::env::var(HELPER_ENV)
            .ok()
            .or_else(|| std::env::args().nth(1))
            .filter(|a| HELPER_ROLES.contains(&a.as_str()));
        if let Some(role) = role {
            if role == "--check-hwcodec-config" {
                #[cfg(feature = "hwcodec")]
                crate::ipc::hwcodec_process();
            }
            // The library runs everything else in the host's own process.
            std::process::exit(0);
        }
        // The desktop client derives its ID from the machine, so it would be the installed
        // client's ID too. The library draws its own once, nine digits like the desktop IDs
        // the web page and the clients expect.
        if Config::get_option(OPTION_OWN_ID).is_empty() {
            use hbb_common::rand::Rng;
            Config::set_id(&hbb_common::rand::thread_rng().gen_range(100_000_000u32..1_000_000_000).to_string());
            Config::set_option(OPTION_OWN_ID.to_owned(), "Y".to_owned());
        }
        #[cfg(feature = "hwcodec")]
        {
            *scrap::hwcodec::CHECK_COMMAND.write().unwrap() = Some(hwcodec_check_command);
        }
        crate::common::global_init();
    });
    0
}

/// Receives every event of the library. NULL stops them.
#[no_mangle]
pub extern "C" fn skyydesk_set_event_callback(cb: Option<SkyyDeskEventCb>, user: *mut c_void) {
    *EVENT_CB.write().unwrap() = cb.map(|cb| (cb, user as usize));
}

/// This machine's SkyyDesk ID.
#[no_mangle]
pub unsafe extern "C" fn skyydesk_my_id(out: *mut c_char, len: c_int) -> c_int {
    copy_out(&Config::get_id(), out, len)
}

// ---- Incoming connections ------------------------------------------------------------------
//
// The core asks a connection manager what to do with each incoming connection; the desktop
// client shows a window for it. Here the host application is that window: it receives every
// connection as an event and decides with skyydesk_accept / skyydesk_close.

#[derive(Clone)]
struct HostCm;

impl crate::ui_cm_interface::InvokeUiCM for HostCm {
    fn add_connection(&self, client: &crate::ui_cm_interface::Client) {
        emit(
            SKYYDESK_EVENT_INCOMING,
            &serde_json::to_string(client).unwrap_or_default(),
        );
    }

    fn remove_connection(&self, id: i32, _close: bool) {
        emit(SKYYDESK_EVENT_INCOMING_CLOSED, &id.to_string());
    }

    fn new_message(&self, _id: i32, _text: String) {}

    fn change_theme(&self, _dark: String) {}

    fn change_language(&self) {}

    fn show_elevation(&self, _show: bool) {}

    fn update_voice_call_state(&self, _client: &crate::ui_cm_interface::Client) {}

    fn file_transfer_log(&self, _action: &str, _log: &str) {}
}

/// Lets SkyyDesk users connect to this machine. With `allow_password` 0, every connection
/// waits for skyydesk_accept; otherwise the password also lets it in.
/// Returns 0, or -2 if no event callback is set.
///
/// If a SkyyDesk client already runs on this machine, it keeps serving connections.
#[no_mangle]
pub extern "C" fn skyydesk_start(allow_password: c_int) -> c_int {
    if EVENT_CB.read().unwrap().is_none() {
        // A connection nobody can see or approve must not be possible.
        return -2;
    }
    let mode = if allow_password != 0 { "" } else { "click" };
    Config::set_option("approve-mode".to_owned(), mode.to_owned());
    if password_security::temporary_password().is_empty() {
        password_security::update_temporary_password();
    }
    static START: std::sync::Once = std::sync::Once::new();
    START.call_once(|| {
        #[cfg(target_os = "linux")]
        std::thread::spawn(crate::ipc::start_pa);
        let cm = crate::ui_cm_interface::ConnectionManager { ui_handler: HostCm };
        std::thread::spawn(move || crate::ui_cm_interface::start_ipc(cm));
        // This process is the server; the desktop client runs it as a separate service.
        std::thread::spawn(|| crate::start_server(true, false));
        std::thread::spawn(enroll);
    });
    0
}

#[no_mangle]
pub extern "C" fn skyydesk_accept(connection: c_int) {
    crate::ui_cm_interface::authorize(connection);
}

#[no_mangle]
pub extern "C" fn skyydesk_close(connection: c_int) {
    crate::ui_cm_interface::close(connection);
}

// ---- Passwords -----------------------------------------------------------------------------

/// The one-time password, if passwords are allowed.
#[no_mangle]
pub unsafe extern "C" fn skyydesk_password(out: *mut c_char, len: c_int) -> c_int {
    copy_out(&password_security::temporary_password(), out, len)
}

#[no_mangle]
pub extern "C" fn skyydesk_new_password() {
    password_security::update_temporary_password();
}

/// Sets the permanent password; an empty string removes it.
/// Returns 0, or -1 if it could not be stored or changing it is disabled.
#[no_mangle]
pub unsafe extern "C" fn skyydesk_set_password(password: *const c_char) -> c_int {
    let Some(password) = str_arg(password) else {
        return -1;
    };
    if !Config::is_disable_change_permanent_password() && Config::set_permanent_password(&password) {
        0
    } else {
        -1
    }
}

// ---- Settings ------------------------------------------------------------------------------
//
// The same keys as the desktop client's settings page, e.g. `verification-method`
// (`use-permanent-password`, `use-temporary-password`, `use-both-passwords`),
// `enable-keyboard`, `enable-clipboard`, `enable-file-transfer`, `enable-audio`;
// and `enroll-key`, the key from the panel that puts this machine in its owner's address book.

#[no_mangle]
pub unsafe extern "C" fn skyydesk_get_option(key: *const c_char, out: *mut c_char, len: c_int) -> c_int {
    match str_arg(key) {
        Some(key) => copy_out(&Config::get_option(&key), out, len),
        None => -1,
    }
}

/// Sets `key` to `value`; an empty value restores the default.
/// Returns 0, or -1 for a server or account option, which the library does not change.
#[no_mangle]
pub unsafe extern "C" fn skyydesk_set_option(key: *const c_char, value: *const c_char) -> c_int {
    let (Some(key), Some(value)) = (str_arg(key), str_arg(value)) else {
        return -1;
    };
    if LOCKED_OPTIONS.contains(&key.as_str()) {
        return -1;
    }
    let enroll_key_changed = key == OPTION_ENROLL_KEY;
    Config::set_option(key, value);
    if enroll_key_changed && crate::common::is_server_running() {
        std::thread::spawn(enroll);
    }
    0
}

// ---- Enrollment ----------------------------------------------------------------------------
//
// With an enroll key the machine adds itself to the key owner's address book. The server
// answers "already" when it is there, which counts as done, so this can run on every start.

fn enroll() {
    let key = Config::get_option(OPTION_ENROLL_KEY);
    if key.is_empty() {
        return;
    }
    let body = serde_json::json!({
        "key": key,
        "id": Config::get_id(),
        "alias": crate::common::hostname(),
        "platform": whoami_platform(),
    })
    .to_string();
    let url = format!("{}/ab-api/enroll", crate::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    ));
    // Offline at start-up is normal for a laptop; keep trying, but not hard.
    let mut wait = 30;
    loop {
        match crate::common::post_request_sync(url.clone(), body.clone(), "") {
            Ok(res) => {
                let v: serde_json::Value = serde_json::from_str(&res).unwrap_or_default();
                let ok = v["ok"].as_bool().unwrap_or(false) || v["already"].as_bool().unwrap_or(false);
                let event = if ok {
                    serde_json::json!({"ok": true})
                } else {
                    serde_json::json!({"ok": false, "error": v["error"].as_str().unwrap_or(&res)})
                };
                emit(SKYYDESK_EVENT_ENROLLED, &event.to_string());
                return;
            }
            Err(e) => {
                log::warn!("enroll: {}", e);
                std::thread::sleep(std::time::Duration::from_secs(wait));
                wait = (wait * 2).min(1800);
            }
        }
    }
}

fn whoami_platform() -> &'static str {
    if cfg!(windows) {
        "Windows"
    } else if cfg!(target_os = "macos") {
        "Mac OS"
    } else {
        "Linux"
    }
}

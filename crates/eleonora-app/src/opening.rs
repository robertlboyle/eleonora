//! Files opened with Eleonora: a double-clicked .eml or Outlook .msg shows in the message viewer, a
//! program of its own (msgview.rs, 2026-11-11), without being added to the library (an .eml the
//! Mac's Finder hands the running window shows in a message window there); an .ics shows its
//! events, each of which can be added to one of the user's calendars.
//!
//! One Eleonora window at a time: the first holds a lock in Eleonora's own folder; a second start
//! (Windows starts the program again for each file opened) hands its files to the first, by a
//! file in that folder the window looks for, and ends. The lock is a file lock (the standard
//! library's, every OS); the Mac hands files to the running program itself (RunEvent::Opened).

use std::path::{Path, PathBuf};
use std::sync::Mutex;
use tauri::Manager;

/// The kinds of file Eleonora opens (an .msg in a viewer of its own: msgview.rs; a .vcf or
/// .vcard, contacts to add or update).
const KINDS: [&str; 5] = ["eml", "ics", "msg", "vcf", "vcard"];

/// How the .msg viewer hands a message to the window for Reply, Reply All, or Forward:
/// `eudora-compose:<mode>:<an .eml in msgview::answers_dir>`.
pub const COMPOSE_PREFIX: &str = "eleonora-compose:";
/// Its name before 2.0.0 (a viewer started by Eudora 1.x, still open while 2.0.0 installs).
pub const OLD_COMPOSE_PREFIX: &str = "eudora-compose:";

fn is_compose(path: &Path) -> bool {
    path.to_str().is_some_and(|s| s.starts_with(COMPOSE_PREFIX) || s.starts_with(OLD_COMPOSE_PREFIX))
}

fn kind_of(path: &Path) -> Option<&'static str> {
    let ext = path.extension()?.to_string_lossy().to_ascii_lowercase();
    KINDS.iter().find(|k| **k == ext).copied()
}

/// A `mailto:` link handed to Eleonora as the system's mail program (it travels with the files).
fn is_mailto(path: &Path) -> bool {
    path.to_str().is_some_and(|s| s.get(..7).is_some_and(|p| p.eq_ignore_ascii_case("mailto:")))
}

/// The command line: the library folder named (if any) and the files (and mailto: links) to open.
pub fn sort_args() -> (Option<PathBuf>, Vec<PathBuf>) {
    let mut library = None;
    let mut files = Vec::new();
    for arg in std::env::args_os().skip(1).map(PathBuf::from) {
        // (Linux passes files as file:// addresses too)
        let arg = match arg.to_str().and_then(|s| s.strip_prefix("file://")) {
            Some(rest) => PathBuf::from(eudora_core_url_path(rest)),
            None => arg,
        };
        if is_mailto(&arg) || is_compose(&arg) {
            files.push(arg);
        } else if kind_of(&arg).is_some() && arg.is_file() {
            files.push(std::path::absolute(&arg).unwrap_or(arg));
        } else if library.is_none() {
            library = Some(arg);
        }
    }
    (library, files)
}

/// A file:// address's path (%XX decoded).
fn eudora_core_url_path(rest: &str) -> String {
    let b = rest.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Some(v) = std::str::from_utf8(&b[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Where a second start leaves its files for the window already open.
fn requests_dir() -> Option<PathBuf> {
    eleonora_core::library::app_data_dir().map(|d| d.join("open-requests"))
}

/// The window's lock, held while it runs (desktops: a phone runs one copy of an app by itself).
#[cfg(desktop)]
static LOCK: std::sync::OnceLock<std::fs::File> = std::sync::OnceLock::new();

/// Takes the window's lock; when another Eleonora window holds it, hands it the files (or, with
/// none, asks it to come to the front) and says so: this start should end. A library named on
/// the command line always starts a window of its own (another library).
#[cfg(desktop)]
pub fn hand_over(files: &[PathBuf], library_named: bool) -> bool {
    let Some(dir) = eleonora_core::library::app_data_dir() else { return false };
    let _ = std::fs::create_dir_all(&dir);
    let Ok(file) = std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(dir.join("window.lock")) else { return false };
    match file.try_lock() {
        Ok(()) => {
            let _ = LOCK.set(file);
            false
        }
        Err(_) if library_named && files.is_empty() => false,
        Err(_) => {
            let Some(requests) = requests_dir() else { return false };
            let _ = std::fs::create_dir_all(&requests);
            let name = format!("{}-{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0), std::process::id());
            let text: Vec<String> = files.iter().map(|f| f.to_string_lossy().into_owned()).collect();
            let tmp = requests.join(format!("{name}.tmp"));
            // (written whole, then named for the window to take: never read half-written)
            std::fs::write(&tmp, text.join("\n")).is_ok() && std::fs::rename(&tmp, requests.join(format!("{name}.txt"))).is_ok()
        }
    }
}

/// The window: opens the files it was started with, then those later starts hand it.
pub fn watch(handle: tauri::AppHandle, files: Vec<PathBuf>) {
    std::thread::spawn(move || {
        for f in files {
            open_or_say(&handle, &f);
        }
        let Some(dir) = requests_dir() else { return };
        loop {
            std::thread::sleep(std::time::Duration::from_millis(500));
            let Ok(entries) = std::fs::read_dir(&dir) else { continue };
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().is_none_or(|e| e != "txt") {
                    continue;
                }
                let text = std::fs::read_to_string(&path).unwrap_or_default();
                let _ = std::fs::remove_file(&path);
                let asked: Vec<PathBuf> = text.lines().map(str::trim).filter(|l| !l.is_empty()).map(PathBuf::from).collect();
                if asked.is_empty() {
                    if let Some(main) = handle.get_webview_window("main") {
                        #[cfg(desktop)]
                        let _ = main.unminimize();
                        let _ = main.show();
                        let _ = main.set_focus();
                    }
                }
                for f in asked {
                    open_or_say(&handle, &f);
                }
            }
        }
    });
}

/// Opens a file; a problem is said in the main window's status bar.
pub fn open_or_say(handle: &tauri::AppHandle, path: &Path) {
    use tauri::Emitter;
    if let Err(why) = open_file(handle, path) {
        let name = if is_mailto(path) { "the mail link".to_string() } else { path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default() };
        let _ = handle.emit_to("main", "outbox", vec![format!("Couldn't open {name}: {why}")]);
    }
}

fn read_limited(path: &Path, max: u64) -> Result<Vec<u8>, String> {
    let size = std::fs::metadata(path).map_err(|e| e.to_string())?.len();
    if size > max {
        return Err(format!("it's {} MB, too big for this kind of file", size / 1_048_576));
    }
    std::fs::read(path).map_err(|e| e.to_string())
}

/// Calendar files opened, by number (for their window).
static ICS: Mutex<Vec<(String, eleonora_core::ics::IcsFile)>> = Mutex::new(Vec::new());

/// Contact files (.vcf) opened, by number (for their window): the file's name and its contacts.
static VCF: Mutex<Vec<(String, Vec<eleonora_core::cards::Card>)>> = Mutex::new(Vec::new());

/// The most a contact file may be (a whole address book exported: thousands of contacts).
const VCF_MAX: u64 = 32 * 1_048_576;

fn open_file(handle: &tauri::AppHandle, path: &Path) -> Result<(), String> {
    use std::sync::atomic::{AtomicU32, Ordering};
    static NEXT: AtomicU32 = AtomicU32::new(1);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    if is_mailto(path) {
        return crate::open_mailto_now(handle, &path.to_string_lossy());
    }
    #[cfg(desktop)]
    if is_compose(path) {
        return answer_from_viewer(handle, &path.to_string_lossy());
    }
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    match kind_of(path) {
        Some("eml") => {
            let bytes = read_limited(path, eleonora_core::library::OPEN_FILE_MAX)?;
            let subject = eleonora_core::parse::display(&bytes, eleonora_core::library::now()).parsed.subject;
            let id = eleonora_core::library::open_message_file(bytes);
            let title: String = if subject.trim().is_empty() { name } else { subject.trim().to_string() };
            let title: String = title.chars().filter(|c| !c.is_control()).take(120).collect();
            tauri::WebviewWindowBuilder::new(handle, format!("reader-file-{n}"), tauri::WebviewUrl::App(format!("index.html?message={id}").into()))
                .title(format!("{title} – Eleonora"))
                .inner_size(900.0, 760.0)
                .min_inner_size(420.0, 300.0)
                .build()
                .map_err(|e| e.to_string())?;
        }
        Some("ics") => {
            let bytes = read_limited(path, eleonora_core::ics::ICS_MAX)?;
            let file = eleonora_core::ics::read(&String::from_utf8_lossy(&bytes));
            let number = {
                let mut list = ICS.lock().unwrap_or_else(|e| e.into_inner());
                list.push((name.clone(), file));
                list.len() - 1
            };
            tauri::WebviewWindowBuilder::new(handle, format!("ics-{n}"), tauri::WebviewUrl::App(format!("ics.html?file={number}").into()))
                .title(format!("{name} – Eleonora"))
                .inner_size(720.0, 640.0)
                .min_inner_size(420.0, 300.0)
                .build()
                .map_err(|e| e.to_string())?;
        }
        Some("vcf" | "vcard") => {
            let bytes = read_limited(path, VCF_MAX)?;
            let cards = eleonora_core::cards::from_vcard(&String::from_utf8_lossy(&bytes));
            if cards.is_empty() {
                return Err(format!("{name} holds no contacts Eleonora can read"));
            }
            let number = {
                let mut list = VCF.lock().unwrap_or_else(|e| e.into_inner());
                list.push((name.clone(), cards));
                list.len() - 1
            };
            tauri::WebviewWindowBuilder::new(handle, format!("ics-vcf-{n}"), tauri::WebviewUrl::App(format!("vcf.html?file={number}").into()))
                .title(format!("{name} – Eleonora"))
                .inner_size(760.0, 640.0)
                .min_inner_size(420.0, 300.0)
                .build()
                .map_err(|e| e.to_string())?;
        }
        // (the Mac hands Finder's files to the running window: a viewer of its own all the same)
        #[cfg(desktop)]
        Some("msg") => crate::msgview::spawn(path)?,
        _ => return Err("Eleonora opens .eml, .msg, .ics, and .vcf files".into()),
    }
    Ok(())
}

/// Reply, Reply All, or Forward from the .msg viewer: the message it left (only from its own
/// folder, only an .eml) opened as a message file is, and a new message started from it.
#[cfg(desktop)]
fn answer_from_viewer(handle: &tauri::AppHandle, arg: &str) -> Result<(), String> {
    let rest = arg.strip_prefix(COMPOSE_PREFIX).or_else(|| arg.strip_prefix(OLD_COMPOSE_PREFIX)).unwrap_or_default();
    let (mode, file) = rest.split_once(':').ok_or("the viewer's request wasn't understood")?;
    if !["reply", "replyAll", "forward"].contains(&mode) {
        return Err(format!("“{mode}” isn't a way to answer a message"));
    }
    let path = PathBuf::from(file);
    let inside = std::fs::canonicalize(crate::msgview::answers_dir()).ok().zip(std::fs::canonicalize(&path).ok()).is_some_and(|(dir, p)| p.starts_with(dir));
    if !inside || path.extension().is_none_or(|e| !e.eq_ignore_ascii_case("eml")) {
        return Err("the viewer's message isn't where Eleonora left it".into());
    }
    let bytes = read_limited(&path, eleonora_core::library::OPEN_FILE_MAX)?;
    let _ = std::fs::remove_file(&path);
    let id = eleonora_core::library::open_message_file(bytes);
    crate::compose_window(handle, mode, Some(id), None, &[])
}

/// A calendar file opened: its name, what it's for, and its events.
#[tauri::command]
pub async fn ics_file(file: usize) -> Result<serde_json::Value, String> {
    let list = ICS.lock().unwrap_or_else(|e| e.into_inner());
    let (name, f) = list.get(file).ok_or("that calendar file isn't open any more")?;
    Ok(serde_json::json!({ "name": name, "method": f.method, "events": f.events }))
}

/// Adds one of a calendar file's events to a calendar. Never with its people: adding it here
/// mustn't send them invitations (it's the user's own copy).
#[tauri::command]
pub async fn ics_add(handle: tauri::AppHandle, file: usize, event: usize, calendar: i64) -> Result<i64, String> {
    let e = {
        let list = ICS.lock().unwrap_or_else(|e| e.into_inner());
        list.get(file).and_then(|(_, f)| f.events.get(event).cloned()).ok_or("that event isn't in the file any more")?
    };
    let new = eleonora_core::meetings::NewEvent::from_ics(calendar, &e);
    tauri::async_runtime::spawn_blocking(move || handle.state::<crate::App>().with(|l| l.new_appointment(&new)))
        .await
        .map_err(|e| e.to_string())?
}

/// A contact file opened: its name, each contact in it with the contacts already in the address
/// book that share one of its email addresses or phone numbers (the same person), and the
/// accounts a new contact can go to.
#[tauri::command]
pub async fn vcf_file(handle: tauri::AppHandle, file: usize) -> Result<serde_json::Value, String> {
    let (name, cards) = {
        let list = VCF.lock().unwrap_or_else(|e| e.into_inner());
        list.get(file).cloned().ok_or("that contact file isn't open any more")?
    };
    tauri::async_runtime::spawn_blocking(move || {
        handle.state::<crate::App>().with_free(|l| {
            let all = l.cards("", None)?;
            let digits = |p: &str| -> String { let d: String = p.chars().filter(char::is_ascii_digit).collect(); d[d.len().saturating_sub(10)..].to_string() };
            let contacts: Vec<serde_json::Value> = cards
                .iter()
                .map(|c| {
                    let emails: Vec<String> = c.emails.iter().map(|e| e.value.trim().to_lowercase()).filter(|e| !e.is_empty()).collect();
                    let phones: Vec<String> = c.phones.iter().map(|p| digits(&p.value)).filter(|p| p.len() >= 7).collect();
                    let matches: Vec<&eleonora_core::cards::CardRow> = all
                        .iter()
                        .filter(|r| {
                            r.card.emails.iter().any(|e| emails.contains(&e.value.trim().to_lowercase()))
                                || r.card.phones.iter().any(|p| { let d = digits(&p.value); d.len() >= 7 && phones.contains(&d) })
                        })
                        .take(10)
                        .collect();
                    serde_json::json!({ "card": c, "shown": c.shown(), "matches": matches })
                })
                .collect();
            Ok(serde_json::json!({ "name": name, "contacts": contacts, "targets": l.contact_targets()?, "new_in": l.new_contact_account()? }))
        })
    })
    .await
    .map_err(|e| e.to_string())?
}

/// One contact of a contact file: added to an account's address book (`account`), or
/// updating a contact already there (`update`: its id). An update takes the file's values where
/// the two differ (the file is the newer word) and keeps every email address, phone number,
/// address, website, and note the contact already had. Either goes to its server with the next
/// check. Returns the contact's id.
#[tauri::command]
pub async fn vcf_save(handle: tauri::AppHandle, file: usize, contact: usize, account: Option<i64>, update: Option<i64>) -> Result<i64, String> {
    let card = {
        let list = VCF.lock().unwrap_or_else(|e| e.into_inner());
        list.get(file).and_then(|(_, cards)| cards.get(contact).cloned()).ok_or("that contact isn't in the file any more")?
    };
    tauri::async_runtime::spawn_blocking(move || {
        handle.state::<crate::App>().with(|l| {
            if let Some(id) = update {
                let existing = l.cards("", None)?.into_iter().find(|r| r.id == id).ok_or_else(|| eleonora_core::Error::Other("that contact isn't in the address book any more".into()))?;
                let merged = eleonora_core::cards::merge_of(&card, &[&existing.card]);
                l.update_card(id, &merged)?;
                return Ok(id);
            }
            let account = account.ok_or_else(|| eleonora_core::Error::Other("choose an address book".into()))?;
            let book = l.contact_targets()?.into_iter().find(|t| t.account == account).map(|t| t.book).unwrap_or_default();
            let id = l.create_card(account, &book, &card)?;
            l.set_new_contact_account(account)?;
            Ok(id)
        })
    })
    .await
    .map_err(|e| e.to_string())?
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    /// The files Eleonora opens, by kind (a .vcf or .vcard: contacts, 2026-11-18); anything else is
    /// a library folder named on the command line.
    #[test]
    fn contact_files_are_opened_too() {
        assert_eq!(super::kind_of(Path::new("C:/Users/x/Desktop/Eleonora contacts.vcf")), Some("vcf"));
        assert_eq!(super::kind_of(Path::new("ann.VCARD")), Some("vcard"));
        assert_eq!(super::kind_of(Path::new("note.ics")), Some("ics"));
        assert_eq!(super::kind_of(Path::new("C:/Mail/Library")), None);
        let cards = eleonora_core::cards::from_vcard("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ann Smith\r\nN:Smith;Ann;;;\r\nEMAIL;TYPE=WORK:ann@example.com\r\nTEL;TYPE=CELL:+1 555 123 4567\r\nEND:VCARD\r\nBEGIN:VCARD\r\nVERSION:3.0\r\nFN:Bo Lee\r\nEMAIL:bo@example.org\r\nEND:VCARD\r\n");
        assert_eq!(cards.len(), 2);
        assert_eq!(cards[0].emails[0].value, "ann@example.com");
    }
}

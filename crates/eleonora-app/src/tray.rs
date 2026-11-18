//! The tray icon: Eleonora's falcon icon, with an orange dot when new mail has come in since the window was last looked at; in the Classic Eudora look classic Eudora's own, the blue
//! in-tray, empty or with the green arrow. The window's icon follows the look too. Classic's tray menu: Open Eleonora, New Message, Check Mail, Work Offline, Minimize to Tray, Exit.
//! A click on the icon brings the window back. On the Mac this is the menu bar item. The pictures are made by scripts/classic_icons.sh.

use std::sync::atomic::{AtomicBool, Ordering};

use tauri::menu::{CheckMenuItemBuilder, MenuBuilder, MenuItemBuilder};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{Emitter, Manager};

const NO_MAIL: tauri::image::Image<'static> = tauri::include_image!("icons/tray-eleonora-nomail.png");
const NEW_MAIL: tauri::image::Image<'static> = tauri::include_image!("icons/tray-eleonora-newmail.png");
const CLASSIC_NO_MAIL: tauri::image::Image<'static> = tauri::include_image!("icons/tray-nomail.png");
const CLASSIC_NEW_MAIL: tauri::image::Image<'static> = tauri::include_image!("icons/tray-newmail.png");
const WINDOW: tauri::image::Image<'static> = tauri::include_image!("icons/128x128@2x.png");
const CLASSIC_WINDOW: tauri::image::Image<'static> = tauri::include_image!("icons/classic-256.png");

/// The Classic Eudora look: classic Eudora's icons in the tray and on the window.
static CLASSIC: AtomicBool = AtomicBool::new(false);

/// The tray's picture for now.
fn tray_icon(new: bool) -> tauri::image::Image<'static> {
    match (CLASSIC.load(Ordering::Relaxed), new) {
        (true, true) => CLASSIC_NEW_MAIL,
        (true, false) => CLASSIC_NO_MAIL,
        (false, true) => NEW_MAIL,
        (false, false) => NO_MAIL,
    }
}

/// The look changed (Classic Eudora or not): the tray's and the windows' icons follow it.
pub fn set_classic(app: &tauri::AppHandle, on: bool) {
    CLASSIC.store(on, Ordering::Relaxed);
    if let Some(tray) = app.tray_by_id("eleonora") {
        let _ = tray.set_icon(Some(tray_icon(NEW.load(Ordering::Relaxed))));
    }
    for (_, window) in app.webview_windows() {
        let _ = window.set_icon(if on { CLASSIC_WINDOW } else { WINDOW });
    }
}

/// Minimize to Tray (classic's option): a minimized window leaves the taskbar for the tray.
pub static MINIMIZE_TO_TRAY: AtomicBool = AtomicBool::new(false);
static NEW: AtomicBool = AtomicBool::new(false);
/// Whether the icon is in the tray: a Linux desktop without the tray library (libayatana-
/// appindicator) has none, and then nothing is ever minimized to it.
pub static SHOWN: AtomicBool = AtomicBool::new(false);

fn show_window(app: &tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
    }
}

/// Puts the icon in the tray (at start).
pub fn install(app: &tauri::AppHandle) -> tauri::Result<()> {
    let minimize = CheckMenuItemBuilder::with_id("tray-minimize", "Minimize to Tray").checked(MINIMIZE_TO_TRAY.load(Ordering::Relaxed)).build(app)?;
    let menu = MenuBuilder::new(app)
        .item(&MenuItemBuilder::with_id("tray-open", "Open Eleonora").build(app)?)
        .separator()
        .item(&MenuItemBuilder::with_id("new", "New Message").build(app)?)
        .item(&MenuItemBuilder::with_id("check", "Check Mail").build(app)?)
        .item(&MenuItemBuilder::with_id("work-offline", "Work Offline").build(app)?)
        .separator()
        .item(&minimize)
        .separator()
        .item(&MenuItemBuilder::with_id("exit", "Exit").build(app)?)
        .build()?;
    let builder = TrayIconBuilder::with_id("eleonora")
        .icon(tray_icon(false))
        .tooltip("Eleonora")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(move |app, event| {
            let id = event.id().as_ref().to_string();
            match id.as_str() {
                "tray-open" => show_window(app),
                "tray-minimize" => {
                    let on = !MINIMIZE_TO_TRAY.load(Ordering::Relaxed);
                    MINIMIZE_TO_TRAY.store(on, Ordering::Relaxed);
                    let _ = app.emit_to("main", "tray-minimize", on);
                }
                "exit" => app.exit(0),
                other => {
                    // the same commands as the menu bar's: the window does them
                    if other == "new" {
                        show_window(app);
                    }
                    let _ = app.emit_to("main", "menu", other.to_string());
                }
            }
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                show_window(tray.app_handle());
            }
        });
    // (Linux: Tauri's tray loads libayatana-appindicator when it's made and panics when the
    // system has none, as a bare Fedora: Eleonora then runs without a tray icon)
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| builder.build(app))) {
        Ok(made) => {
            made?;
            SHOWN.store(true, Ordering::Relaxed);
        }
        Err(_) => eprintln!("Eleonora: no tray icon (this system has no tray library: libayatana-appindicator)"),
    }
    Ok(())
}

/// New mail (`on`) or none to show: the icon changes.
pub fn set_new_mail(app: &tauri::AppHandle, on: bool) {
    if NEW.swap(on, Ordering::Relaxed) == on {
        return;
    }
    if let Some(tray) = app.tray_by_id("eleonora") {
        let _ = tray.set_icon(Some(tray_icon(on)));
        let _ = tray.set_tooltip(Some(if on { "Eleonora: new mail" } else { "Eleonora" }));
    }
}

// No console window behind release builds on Windows.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

//! Eleonora on a desktop: the window is the library `eleonora_app_lib` (shared with the phone apps).

fn main() {
    eleonora_app_lib::run();
}

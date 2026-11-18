//! Who this build of Eleonora belongs to: the Microsoft app registration it signs in with, the
//! server it updates from, and the Apple team its Mac updates must be signed by.
//!
//! The published source has these empty, so a build made from it signs in to Microsoft and updates
//! itself only once its builder sets their own, either in this file or, without editing it,
//! through these variables when building (BUILDING.md says how to get each):
//!
//! - `ELEONORA_MICROSOFT_CLIENT_ID`: an app registration's Application (client) ID
//! - `ELEONORA_UPDATE_URL_DEFAULT`: the folder the update files are published in
//! - `ELEONORA_DOWNLOAD_PAGE`: the web page to download Eleonora by hand
//! - `ELEONORA_MAC_TEAM`: the Apple team ID that signs the Mac app

/// The value given when building, else `official`.
const fn or(given: Option<&'static str>, official: &'static str) -> &'static str {
    match given {
        Some(v) => v,
        None => official,
    }
}

/// The Microsoft app registration Eleonora signs in with (empty: Microsoft sign-in unavailable).
pub const MICROSOFT_CLIENT_ID: &str = or(option_env!("ELEONORA_MICROSOFT_CLIENT_ID"), "");
/// Where Eleonora looks for updates (empty: this build doesn't update itself).
pub const UPDATE_URL: &str = or(option_env!("ELEONORA_UPDATE_URL_DEFAULT"), "");
/// Where to get Eleonora by hand.
pub const DOWNLOAD_PAGE: &str = or(option_env!("ELEONORA_DOWNLOAD_PAGE"), "");
/// The Apple team a Mac update must be signed by (empty: the Mac never installs an update itself).
pub const MAC_TEAM: &str = or(option_env!("ELEONORA_MAC_TEAM"), "");

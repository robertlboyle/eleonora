//! Where sync keeps its envelopes for accounts that aren't Microsoft's: an IMAP account's "Eleonora
//! Sync" folder on its server, a Gmail account's hidden "Eleonora Sync" label. Each envelope part
//! is a small message (as in Microsoft 365's sync folder): a line asking people to leave it, the
//! sealed bytes attached, the part's name as its subject, and `X-Eleonora-Settings: 1`. The
//! downloads leave the folder and the label out, so these never show as mail. (POP3 has no folders
//! on the server: a POP3-only computer keeps its settings in a home account of another kind.)

use base64::Engine;

use crate::error::{Error, Result};
use crate::graph::{OLD_SYNC_FOLDER, SYNC_FOLDER};
#[cfg(test)]
use crate::graph::SYNC_SUBJECT;
use crate::sync_run::SyncStore;

/// The most one part carries (servers commonly take 20-35 MB a message; parts stay well under).
pub const ITEM_LIMIT: usize = 8 * 1024 * 1024;

/// An envelope part as a message.
pub fn item_message(name: &str, bytes: &[u8]) -> Vec<u8> {
    let encoded = base64::engine::general_purpose::STANDARD.encode(bytes);
    let lines: Vec<&str> = encoded.as_bytes().chunks(76).map(|c| std::str::from_utf8(c).unwrap_or("")).collect();
    let date = chrono::Utc::now().format("%a, %d %b %Y %H:%M:%S +0000");
    // (the name is ASCII and the separators "·" are not: the subject is encoded)
    let subject = format!("=?UTF-8?B?{}?=", base64::engine::general_purpose::STANDARD.encode(name.as_bytes()));
    format!(
        "From: Eleonora <eleonora-sync@localhost>\r\nSubject: {subject}\r\nDate: {date}\r\nX-Eleonora-Settings: 1\r\nMIME-Version: 1.0\r\n\
Content-Type: multipart/mixed; boundary=\"eudora-sync\"\r\n\r\n--eudora-sync\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\
Eleonora keeps your settings and how your mail is filed here, encrypted, for your other computers. Please leave it.\r\n\
--eudora-sync\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"eudora-sync.bin\"\r\nContent-Transfer-Encoding: base64\r\n\r\n{}\r\n--eudora-sync--\r\n",
        lines.join("\r\n")
    )
    .into_bytes()
}

/// A message's envelope part: (its name, its bytes); None for anything else.
pub fn item_of(raw: &[u8]) -> Option<(String, Vec<u8>)> {
    let m = mail_parser::MessageParser::default().parse(raw)?;
    let name = m.subject()?.to_string();
    if !crate::graph::is_sync_subject(&name) {
        return None;
    }
    let bytes = m.attachments().next()?.contents().to_vec();
    Some((name, bytes))
}

/// Whether a folder is sync's own (left out of downloads): "Eleonora Sync" (or "Eleonora Sync",
/// its name before 2.0.0), at the top or under the inbox ("INBOX.Eleonora Sync" on servers that
/// keep every folder there).
pub fn is_sync_folder(path: &str) -> bool {
    let last = path.rsplit(['/', '.']).next().unwrap_or(path);
    last.eq_ignore_ascii_case(SYNC_FOLDER) || last.eq_ignore_ascii_case(OLD_SYNC_FOLDER)
}

/// Whether a folder is sync's own under its name before 2.0.0.
fn is_old_sync_folder(path: &str) -> bool {
    path.rsplit(['/', '.']).next().unwrap_or(path).eq_ignore_ascii_case(OLD_SYNC_FOLDER)
}

/// An IMAP account's "Eleonora Sync" folder (made when missing; the one from before 2.0.0
/// renamed).
pub struct ImapStore {
    session: crate::imap_sync::Session,
    folder: String,
    uidplus: bool,
}

fn imap_err(what: &str, e: imap::Error) -> Error {
    Error::Other(format!("the sync folder: {what}: {e}"))
}

impl ImapStore {
    pub fn open(config: &crate::imap_sync::ImapConfig) -> Result<ImapStore> {
        let mut session = crate::imap_sync::open_session(config)?;
        let uidplus = session.capabilities().map(|c| c.has_str("UIDPLUS")).unwrap_or(false);
        let names = session.list(Some(""), Some("*")).map_err(|e| imap_err("listing the folders", e))?;
        let decoded = |n: &imap::types::Name| crate::imap_sync::decode_utf7(n.name());
        let new_one = names.iter().find(|n| is_sync_folder(&decoded(n)) && !is_old_sync_folder(&decoded(n))).map(|n| n.name().to_string());
        let old_one = names.iter().find(|n| is_old_sync_folder(&decoded(n))).map(|n| n.name().to_string());
        let found = new_one.clone().or_else(|| old_one.clone());
        let delimiter = names.iter().find_map(|n| n.delimiter().map(str::to_string)).unwrap_or_else(|| "/".into());
        drop(names);
        // both there: an older Eudora (1.x, on a computer not updated yet) made "Eudora Sync"
        // again after it was renamed; its envelopes are copied in and the old folder deleted, each
        // time, until nothing makes it again. Nothing is deleted unless every
        // copy was stored; a failure leaves it for next time.
        if let (Some(new), Some(old)) = (&new_one, &old_one) {
            if let Err(why) = fold_imap_folder(&mut session, old, new) {
                eprintln!("The old \"{OLD_SYNC_FOLDER}\" folder stays for now (tried again next time): {why}");
            }
        }
        let folder = match found {
            // (the folder from before 2.0.0: renamed where it is, its envelopes kept)
            Some(f) if is_old_sync_folder(&crate::imap_sync::decode_utf7(&f)) => {
                let renamed = format!("{}{SYNC_FOLDER}", &f[..f.len() - OLD_SYNC_FOLDER.len()]);
                if f.len() >= OLD_SYNC_FOLDER.len() && session.rename(&f, &renamed).is_ok() { renamed } else { f }
            }
            Some(f) => f,
            None => {
                // at the top, else under the inbox (servers that keep every folder there)
                let top = SYNC_FOLDER.to_string();
                match session.create(&top) {
                    Ok(()) => top,
                    Err(first) => {
                        let under = format!("INBOX{delimiter}{SYNC_FOLDER}");
                        session.create(&under).map_err(|_| imap_err("making it", first))?;
                        under
                    }
                }
            }
        };
        Ok(ImapStore { session, folder, uidplus })
    }
}

/// Copies every envelope in the IMAP folder `old` into `new`, then deletes `old`.
fn fold_imap_folder(session: &mut crate::imap_sync::Session, old: &str, new: &str) -> Result<usize> {
    let mailbox = session.select(old).map_err(|e| imap_err("opening the old folder", e))?;
    let mut items = Vec::new();
    if mailbox.exists > 0 {
        let fetches = session.uid_fetch("1:*", "(UID BODY.PEEK[])").map_err(|e| imap_err("reading the old folder", e))?;
        items = fetches.iter().filter_map(|f| f.body()).filter_map(item_of).collect::<Vec<_>>();
    }
    let _ = session.close();
    for (name, bytes) in &items {
        session.append(new, &item_message(name, bytes)).flag(imap::types::Flag::Seen).finish().map_err(|e| imap_err("copying a part", e))?;
    }
    session.delete(old).map_err(|e| imap_err("deleting the old folder", e))?;
    Ok(items.len())
}

impl SyncStore for ImapStore {
    fn list(&mut self) -> Result<Vec<(String, String, Vec<u8>)>> {
        let mailbox = self.session.select(&self.folder).map_err(|e| imap_err("opening it", e))?;
        if mailbox.exists == 0 {
            return Ok(Vec::new());
        }
        let fetches = self.session.uid_fetch("1:*", "(UID BODY.PEEK[])").map_err(|e| imap_err("reading it", e))?;
        Ok(fetches.iter().filter_map(|f| Some((f.uid?, f.body()?))).filter_map(|(uid, raw)| item_of(raw).map(|(name, bytes)| (uid.to_string(), name, bytes))).collect())
    }

    fn put(&mut self, name: &str, bytes: &[u8]) -> Result<String> {
        if bytes.len() > ITEM_LIMIT {
            return Err(Error::Other(format!("a sync part of {} KB is over the {} KB one message carries", bytes.len() / 1024, ITEM_LIMIT / 1024)));
        }
        self.session
            .append(&self.folder, &item_message(name, bytes))
            .flag(imap::types::Flag::Seen)
            .finish()
            .map_err(|e| imap_err("storing a part", e))?;
        Ok(name.to_string())
    }

    fn delete(&mut self, id: &str) -> Result<()> {
        self.session.select(&self.folder).map_err(|e| imap_err("opening it", e))?;
        self.session.uid_store(id, "+FLAGS.SILENT (\\Deleted)").map_err(|e| imap_err("removing an old part", e))?;
        // (only sync's own items are in this folder: expunging all of it is safe too)
        if self.uidplus {
            self.session.uid_expunge(id).map_err(|e| imap_err("removing an old part", e))?;
        } else {
            self.session.expunge().map_err(|e| imap_err("removing an old part", e))?;
        }
        Ok(())
    }

    fn writable(&self) -> bool {
        true
    }

    fn max_item(&self) -> usize {
        ITEM_LIMIT
    }
}

impl Drop for ImapStore {
    fn drop(&mut self) {
        let _ = self.session.logout();
    }
}

/// A Gmail account's hidden "Eleonora Sync" label (made when missing: not in the label list, its
/// messages out of every view).
pub struct GmailStore {
    client: crate::google::GoogleClient,
    label: String,
}

impl GmailStore {
    pub fn open(address: &str) -> Result<GmailStore> {
        let mut client = crate::google::GoogleClient::resume(address)?;
        let labels = client.labels()?;
        let old_label = labels.iter().find(|(_, name, _)| name.eq_ignore_ascii_case(OLD_SYNC_FOLDER)).map(|(id, ..)| id.clone());
        let label = match labels.iter().find(|(_, name, _)| name.eq_ignore_ascii_case(SYNC_FOLDER)) {
            Some((id, ..)) => {
                // both there: an older Eudora made "Eudora Sync" again after it was renamed; its
                // messages move to this label and the old label goes, each time, until nothing
                // makes it again
                if let Some(old) = &old_label {
                    if let Err(why) = fold_gmail_label(&mut client, old, id) {
                        eprintln!("The old \"{OLD_SYNC_FOLDER}\" label stays for now (tried again next time): {why}");
                    }
                }
                id.clone()
            }
            // (the label from before 2.0.0: renamed, its envelopes kept)
            None => match labels.iter().find(|(_, name, _)| name.eq_ignore_ascii_case(OLD_SYNC_FOLDER)) {
                Some((id, ..)) => {
                    let _ = client.rename_label(id, SYNC_FOLDER);
                    id.clone()
                }
                None => client.make_hidden_label(SYNC_FOLDER)?,
            },
        };
        Ok(GmailStore { client, label })
    }

    /// The label's id (the Gmail download leaves its messages out).
    pub fn label(&self) -> &str {
        &self.label
    }
}

/// Moves every message under the Gmail label `old` to `new` (the label changed: the message
/// itself stays), then deletes `old`.
fn fold_gmail_label(client: &mut crate::google::GoogleClient, old: &str, new: &str) -> Result<usize> {
    let ids = client.message_ids(old, &|_| {})?;
    for id in &ids {
        client.modify(id, &[new], &[old])?;
    }
    client.delete_label(old)?;
    Ok(ids.len())
}

impl SyncStore for GmailStore {
    fn list(&mut self) -> Result<Vec<(String, String, Vec<u8>)>> {
        let ids = self.client.message_ids(&self.label, &|_| {})?;
        let mut out = Vec::new();
        for id in ids {
            let (raw, _) = self.client.raw_message(&id)?;
            if let Some((name, bytes)) = item_of(&raw) {
                out.push((id, name, bytes));
            }
        }
        Ok(out)
    }

    fn put(&mut self, name: &str, bytes: &[u8]) -> Result<String> {
        if bytes.len() > ITEM_LIMIT {
            return Err(Error::Other(format!("a sync part of {} KB is over the {} KB one message carries", bytes.len() / 1024, ITEM_LIMIT / 1024)));
        }
        self.client.insert_message(&item_message(name, bytes), &[&self.label])
    }

    fn delete(&mut self, id: &str) -> Result<()> {
        self.client.delete_message(id)
    }

    fn writable(&self) -> bool {
        true
    }

    fn max_item(&self) -> usize {
        ITEM_LIMIT
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_part_survives_being_a_message() {
        let name = format!("{SYNC_SUBJECT} · settings · all · k1 · pc-a · 00019a2b3c4d · 1/1");
        let bytes: Vec<u8> = (0..=255u8).cycle().take(10_000).collect();
        let raw = item_message(&name, &bytes);
        assert!(String::from_utf8_lossy(&raw).contains("X-Eleonora-Settings: 1"));
        assert_eq!(item_of(&raw), Some((name, bytes)));
        assert_eq!(item_of(b"From: a@b.c\r\nSubject: Hello\r\n\r\nhi\r\n"), None, "ordinary mail isn't a part");
    }

    /// On a real Gmail account (ELEONORA_GMAIL=address), each step said as it goes:
    /// `cargo test -p eleonora-core --lib gmail_store_steps -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn gmail_store_steps() {
        let address = std::env::var("ELEONORA_GMAIL").expect("ELEONORA_GMAIL");
        eprintln!("signing in");
        let mut client = crate::google::GoogleClient::resume(&address).unwrap();
        eprintln!("signed in; reading the labels");
        let labels = client.labels().unwrap();
        eprintln!("{} labels: {:?}", labels.len(), labels.iter().find(|(_, n, _)| n.eq_ignore_ascii_case(SYNC_FOLDER)));
        drop(client);
        let mut store = GmailStore::open(&address).unwrap();
        eprintln!("label {}", store.label());
        eprintln!("listing: {}", store.list().unwrap().len());
        let name = format!("{SYNC_SUBJECT} · check · test");
        eprintln!("storing");
        let id = store.put(&name, b"hello").unwrap();
        eprintln!("stored as {id}; listing");
        let items = store.list().unwrap();
        eprintln!("{} items; deleting", items.len());
        store.delete(&id).unwrap();
        eprintln!("deleted; listing: {}", store.list().unwrap().len());
    }

    #[test]
    fn the_sync_folder_is_known_wherever_the_server_keeps_it() {
        for p in ["Eleonora Sync", "INBOX.Eleonora Sync", "Eleonora Sync", "INBOX.Eleonora Sync", "INBOX/Eleonora Sync", "eudora sync"] {
            assert!(is_sync_folder(p), "{p}");
        }
        for p in ["Inbox", "Eleonora Sync Old", "Projects/Sync"] {
            assert!(!is_sync_folder(p), "{p}");
        }
    }
}

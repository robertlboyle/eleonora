//! Which Microsoft 365 shared mailboxes are in Eleonora.
//!
//! Microsoft offers no list of the mailboxes a user may open, so Eleonora reads the directory and
//! tries each one (`graph_sync::find_mailboxes`, a minute or so). What it found is kept here
//! (`shared-found`), so Settings ▸ Accounts ▸ Shared mailboxes shows it at once, and checked
//! again daily by the window (or at once with Check Now):
//!
//! * **a mailbox newly open to the user** is offered, never added by itself: once per mailbox
//! (`shared-offered`); * **a mailbox the user can no longer open** stays with the mail already
//! here, marked "no access" (`shared-no-access`), and the download stops checking it; *
//! **removing one** (unticking it) takes it out of the sidebar and the download at once
//! (`shared-removing`); the download then removes its copies in the background, a batch a round
//! ([`Library::remove_shared_step`]): a message only in it goes (`purge_message`), one also in
//! another mailbox only loses its place there; then its folders, address books, calendars, and
//! the account. The mail stays on Microsoft's server, and ticking it again brings it back.
//!
//! These settings belong to this computer (not synced): each computer chooses its own.

use std::collections::HashSet;

use rusqlite::{OptionalExtension, params};
use serde::{Deserialize, Serialize};

use crate::Result;
use crate::library::{Library, now};

pub const FOUND: &str = "shared-found";
pub const OFFERED: &str = "shared-offered";
pub const NO_ACCESS: &str = "shared-no-access";
pub const REMOVING: &str = "shared-removing";

/// How often the window looks again by itself.
pub const CHECK_EVERY_SECS: i64 = 24 * 3600;

/// One mailbox the user can open, as found.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Found {
    pub address: String,
    pub name: String,
    pub inbox: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct FoundList {
    at: i64,
    mailboxes: Vec<Found>,
}

/// One row of Settings ▸ Accounts ▸ Shared mailboxes.
#[derive(Clone, Debug, Serialize)]
pub struct SharedRow {
    pub address: String,
    pub name: String,
    /// Messages in its Inbox on the server when last checked (None: not found then).
    pub inbox: Option<u64>,
    /// In Eleonora (an account, not being removed).
    pub added: bool,
    /// Downloaded in the background (`shared-active`).
    pub active: bool,
    /// Found by the last check and never offered before.
    pub new: bool,
    /// In Eleonora but not open to the user any more.
    pub no_access: bool,
    /// Being removed by the download.
    pub removing: bool,
}

/// The whole section: when the list was last checked, and every mailbox.
#[derive(Clone, Debug, Serialize)]
pub struct SharedList {
    /// Unix seconds (0: never checked).
    pub checked: i64,
    pub mailboxes: Vec<SharedRow>,
}

/// What a check found.
#[derive(Clone, Debug, Default, Serialize)]
pub struct Checked {
    /// Open to the user now and never offered before.
    pub new: Vec<Found>,
    /// In Eleonora, but no longer open to the user.
    pub lost: Vec<String>,
    /// Open again after being marked "no access".
    pub back: Vec<String>,
    pub found: usize,
}

fn lower(s: &str) -> String {
    s.trim().to_lowercase()
}

impl Library {
    fn address_list(&self, key: &str) -> Result<Vec<String>> {
        Ok(self.setting(key)?.and_then(|j| serde_json::from_str::<Vec<String>>(&j).ok()).unwrap_or_default())
    }

    fn set_address_list(&self, key: &str, list: &[String]) -> Result<()> {
        let mut seen = HashSet::new();
        let list: Vec<&String> = list.iter().filter(|a| seen.insert(lower(a))).collect();
        self.set_setting(key, &serde_json::to_string(&list)?)
    }

    /// The shared mailboxes being removed (lowercase).
    pub fn shared_removing(&self) -> Result<HashSet<String>> {
        Ok(self.address_list(REMOVING)?.iter().map(|a| lower(a)).collect())
    }

    /// The shared mailboxes the download leaves alone: being removed, or no longer open to the
    /// user (lowercase).
    pub fn shared_skipped(&self) -> Result<HashSet<String>> {
        let mut skip = self.shared_removing()?;
        skip.extend(self.address_list(NO_ACCESS)?.iter().map(|a| lower(a)));
        Ok(skip)
    }

    /// When the list of mailboxes was last checked (0: never).
    pub fn shared_checked_at(&self) -> Result<i64> {
        Ok(self.setting(FOUND)?.and_then(|j| serde_json::from_str::<FoundList>(&j).ok()).map_or(0, |f| f.at))
    }

    /// Settings ▸ Accounts ▸ Shared mailboxes: every mailbox found, and every shared mailbox in
    /// Eleonora, by address.
    pub fn shared_list(&self) -> Result<SharedList> {
        let found: FoundList = self.setting(FOUND)?.and_then(|j| serde_json::from_str(&j).ok()).unwrap_or_default();
        let offered: HashSet<String> = self.address_list(OFFERED)?.iter().map(|a| lower(a)).collect();
        let no_access: HashSet<String> = self.address_list(NO_ACCESS)?.iter().map(|a| lower(a)).collect();
        let removing = self.shared_removing()?;
        let active: Option<HashSet<String>> = crate::graph_sync::shared_active(self).map(|l| l.iter().map(|a| lower(a)).collect());
        let mut have: Vec<(String, String)> = crate::db::shared_mailboxes(&self.conn)?;
        have.retain(|(a, _)| !a.trim().is_empty());
        let mut rows: Vec<SharedRow> = Vec::new();
        for f in &found.mailboxes {
            let key = lower(&f.address);
            let added = have.iter().any(|(a, _)| lower(a) == key) && !removing.contains(&key);
            rows.push(SharedRow {
                address: f.address.clone(),
                name: f.name.clone(),
                inbox: Some(f.inbox),
                added,
                active: added && active.as_ref().is_none_or(|s| s.contains(&key)),
                new: !added && !offered.contains(&key),
                no_access: false,
                removing: removing.contains(&key),
            });
        }
        // in Eleonora but not found by the last check (no access now, or never checked)
        for (address, name) in &have {
            let key = lower(address);
            if rows.iter().any(|r| lower(&r.address) == key) {
                continue;
            }
            let added = !removing.contains(&key);
            rows.push(SharedRow {
                address: address.clone(),
                name: name.clone(),
                inbox: None,
                added,
                active: added && active.as_ref().is_none_or(|s| s.contains(&key)),
                new: false,
                no_access: no_access.contains(&key),
                removing: removing.contains(&key),
            });
        }
        rows.sort_by(|a, b| (!a.added, lower(&a.address)).cmp(&(!b.added, lower(&b.address))));
        Ok(SharedList { checked: found.at, mailboxes: rows })
    }

    /// Records what a check found (`graph_sync::find_mailboxes`): the list kept, mailboxes no
    /// longer open marked "no access" (and unmarked when open again), new ones returned to offer.
    /// The first check ever is the starting point: what it finds is the list, not news (the
    /// mailboxes were open to the user before Eleonora looked), so nothing is offered then.
    pub fn record_shared_found(&self, found: &[Found]) -> Result<Checked> {
        let first = self.setting(FOUND)?.and_then(|j| serde_json::from_str::<FoundList>(&j).ok()).is_none();
        if first {
            self.mark_shared_offered(&found.iter().map(|f| f.address.clone()).collect::<Vec<_>>())?;
        }
        let open: HashSet<String> = found.iter().map(|f| lower(&f.address)).collect();
        let removing = self.shared_removing()?;
        let have: Vec<String> = crate::db::shared_mailboxes(&self.conn)?.into_iter().map(|(a, _)| a).filter(|a| !removing.contains(&lower(a))).collect();
        let have_keys: HashSet<String> = have.iter().map(|a| lower(a)).collect();
        let offered: HashSet<String> = self.address_list(OFFERED)?.iter().map(|a| lower(a)).collect();
        let before: Vec<String> = self.address_list(NO_ACCESS)?;
        let before_keys: HashSet<String> = before.iter().map(|a| lower(a)).collect();
        let mut out = Checked { found: found.len(), ..Default::default() };
        out.new = found.iter().filter(|f| !have_keys.contains(&lower(&f.address)) && !offered.contains(&lower(&f.address))).cloned().collect();
        let no_access: Vec<String> = have.iter().filter(|a| !open.contains(&lower(a))).cloned().collect();
        out.lost = no_access.iter().filter(|a| !before_keys.contains(&lower(a))).cloned().collect();
        out.back = before.iter().filter(|a| open.contains(&lower(a))).cloned().collect();
        self.set_address_list(NO_ACCESS, &no_access)?;
        let list = FoundList { at: now(), mailboxes: found.to_vec() };
        self.set_setting(FOUND, &serde_json::to_string(&list)?)?;
        Ok(out)
    }

    /// Asks Microsoft again which mailboxes the user can open (a minute or so) and records it.
    pub fn check_shared_mailboxes(&self) -> Result<Checked> {
        let mut client = crate::graph::GraphClient::resume(None, crate::graph::ALL_SCOPES)?;
        let found: Vec<Found> = crate::graph_sync::find_mailboxes(&mut client, &crate::Silent)?
            .into_iter()
            .map(|m| Found { address: m.address, name: m.name, inbox: m.inbox })
            .collect();
        self.record_shared_found(&found)
    }

    /// The user has been told about these (offered once, whatever they answered).
    pub fn mark_shared_offered(&self, addresses: &[String]) -> Result<()> {
        let mut list = self.address_list(OFFERED)?;
        list.extend(addresses.iter().cloned());
        self.set_address_list(OFFERED, &list)
    }

    /// Puts a shared mailbox in Eleonora (or calls off its removal), as an inactive one unless the
    /// user had chosen otherwise: opening it brings it up to date.
    pub fn show_shared_mailbox(&self, address: &str) -> Result<i64> {
        let key = lower(address);
        let removing: Vec<String> = self.address_list(REMOVING)?.into_iter().filter(|a| lower(a) != key).collect();
        self.set_address_list(REMOVING, &removing)?;
        self.mark_shared_offered(&[address.to_string()])?;
        self.add_shared_mailbox(address.trim())
    }

    /// Takes a shared mailbox out of Eleonora: out of the sidebar and the download at once, its
    /// copies removed by the download in the background (`remove_shared_step`). Nothing on the
    /// server changes. Returns how many messages it holds here.
    pub fn remove_shared_mailbox(&self, address: &str) -> Result<u64> {
        let key = lower(address);
        let account: Option<i64> = self
            .conn
            .query_row("SELECT id FROM accounts WHERE kind = 'graph-shared' AND lower(address) = ?1", params![key], |r| r.get(0))
            .optional()?;
        let Some(account) = account else { return Ok(0) };
        let messages: i64 = self.conn.query_row(
            "SELECT COUNT(DISTINCT l.message) FROM locations l JOIN folders f ON f.id = l.folder WHERE f.account = ?1",
            params![account],
            |r| r.get(0),
        )?;
        let mut removing = self.address_list(REMOVING)?;
        removing.push(address.trim().to_string());
        self.set_address_list(REMOVING, &removing)?;
        if let Some(active) = crate::graph_sync::shared_active(self) {
            let left: Vec<String> = active.into_iter().filter(|a| lower(a) != key).collect();
            self.set_setting(crate::graph_sync::SHARED_ACTIVE, &serde_json::to_string(&left)?)?;
        }
        Ok(messages as u64)
    }

    /// The download's part of removing shared mailboxes: up to `limit` messages of the first
    /// one being removed, then (when none are left) its folders, address books, calendars, and
    /// the account. Returns (address, messages done this round, messages left), or None when
    /// nothing is being removed.
    pub fn remove_shared_step(&self, limit: usize) -> Result<Option<(String, u64, u64)>> {
        let removing = self.address_list(REMOVING)?;
        let Some(address) = removing.first().cloned() else { return Ok(None) };
        let key = lower(&address);
        let account: Option<i64> = self
            .conn
            .query_row("SELECT id FROM accounts WHERE kind = 'graph-shared' AND lower(address) = ?1", params![key], |r| r.get(0))
            .optional()?;
        let Some(account) = account else {
            // (already gone)
            let left: Vec<String> = removing.into_iter().filter(|a| lower(a) != key).collect();
            self.set_address_list(REMOVING, &left)?;
            return Ok(Some((address, 0, 0)));
        };
        let folders: Vec<i64> = {
            let mut stmt = self.conn.prepare("SELECT id FROM folders WHERE account = ?1")?;
            stmt.query_map(params![account], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?
        };
        let list = folders.iter().map(|f| f.to_string()).collect::<Vec<_>>().join(",");
        let list = if list.is_empty() { "-1".to_string() } else { list };
        let batch: Vec<i64> = {
            let mut stmt = self.conn.prepare(&format!("SELECT DISTINCT message FROM locations WHERE folder IN ({list}) LIMIT ?1"))?;
            stmt.query_map(params![limit as i64], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?
        };
        let done = batch.len() as u64;
        self.in_transaction(|| {
            for &message in &batch {
                let elsewhere: bool = self.conn.query_row(
                    &format!("SELECT EXISTS (SELECT 1 FROM locations WHERE message = ?1 AND folder NOT IN ({list}))"),
                    params![message],
                    |r| r.get(0),
                )?;
                if elsewhere {
                    // (also in another mailbox: it stays, without its places here)
                    self.conn.execute(&format!("DELETE FROM locations WHERE message = ?1 AND folder IN ({list})"), params![message])?;
                    self.conn.execute(&format!("DELETE FROM server_items WHERE message = ?1 AND folder IN ({list})"), params![message])?;
                    self.conn.execute(&format!("UPDATE copies SET folder = NULL WHERE message = ?1 AND folder IN ({list})"), params![message])?;
                } else {
                    self.purge_message(message)?;
                }
            }
            Ok(())
        })?;
        let left: i64 = self.conn.query_row(&format!("SELECT COUNT(DISTINCT message) FROM locations WHERE folder IN ({list})"), [], |r| r.get(0))?;
        if left > 0 {
            return Ok(Some((address, done, left as u64)));
        }
        // nothing left in it: everything else that names its folders or the account, then the account
        self.in_transaction(|| {
            let tables_with = |column: &str| -> Result<Vec<String>> {
                let mut stmt = self.conn.prepare(
                    "SELECT m.name FROM sqlite_master m JOIN pragma_table_info(m.name) p WHERE m.type = 'table' AND p.name = ?1",
                )?;
                Ok(stmt.query_map(params![column], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?)
            };
            for table in tables_with("folder")? {
                match table.as_str() {
                    "copies" => self.conn.execute(&format!("UPDATE copies SET folder = NULL WHERE folder IN ({list})"), [])?,
                    _ => self.conn.execute(&format!("DELETE FROM \"{table}\" WHERE folder IN ({list})"), [])?,
                };
            }
            // (events belong to calendars, which belong to the account)
            self.conn.execute("DELETE FROM events WHERE calendar IN (SELECT id FROM calendars WHERE account = ?1)", params![account])?;
            for table in tables_with("account")? {
                if table != "folders" && table != "accounts" {
                    self.conn.execute(&format!("DELETE FROM \"{table}\" WHERE account = ?1"), params![account])?;
                }
            }
            // (folders inside others first, so a parent is never left pointing nowhere)
            self.conn.execute("UPDATE folders SET parent = NULL WHERE account = ?1", params![account])?;
            self.conn.execute("DELETE FROM folders WHERE account = ?1", params![account])?;
            self.conn.execute("DELETE FROM accounts WHERE id = ?1", params![account])?;
            Ok(())
        })?;
        let rest: Vec<String> = self.address_list(REMOVING)?.into_iter().filter(|a| lower(a) != key).collect();
        self.set_address_list(REMOVING, &rest)?;
        let no_access: Vec<String> = self.address_list(NO_ACCESS)?.into_iter().filter(|a| lower(a) != key).collect();
        self.set_address_list(NO_ACCESS, &no_access)?;
        Ok(Some((address, done, 0)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Access;
    use crate::progress::Silent;
    use crate::{ImportOptions, import};

    fn found(address: &str) -> Found {
        Found { address: address.into(), name: address.split('@').next().unwrap().into(), inbox: 3 }
    }

    #[test]
    fn new_mailboxes_are_offered_once_and_lost_ones_marked() {
        let dir = tempfile::tempdir().unwrap();
        let library = Library::open(&dir.path().join("lib"), Access::Write, &Silent).unwrap();
        library.add_shared_mailbox("noc@x.com").unwrap();
        library.add_shared_mailbox("old@x.com").unwrap();
        // the first check is the starting point: nothing offered
        let start = library.record_shared_found(&[found("noc@x.com")]).unwrap();
        assert!(start.new.is_empty());
        assert_eq!(start.lost, ["old@x.com"]);
        let first = library.record_shared_found(&[found("noc@x.com"), found("sales@x.com")]).unwrap();
        assert_eq!(first.new.iter().map(|f| f.address.as_str()).collect::<Vec<_>>(), ["sales@x.com"]);
        assert!(first.lost.is_empty());
        let list = library.shared_list().unwrap();
        let row = |a: &str| list.mailboxes.iter().find(|r| r.address == a).unwrap().clone();
        assert!(row("noc@x.com").added && !row("noc@x.com").no_access);
        assert!(row("sales@x.com").new && !row("sales@x.com").added);
        assert!(row("old@x.com").no_access && row("old@x.com").added);
        assert!(library.shared_skipped().unwrap().contains("old@x.com"));
        // offered once: not new again; open again: not marked any more
        library.mark_shared_offered(&["sales@x.com".into()]).unwrap();
        let again = library.record_shared_found(&[found("noc@x.com"), found("sales@x.com"), found("old@x.com")]).unwrap();
        assert!(again.new.is_empty());
        assert_eq!(again.back, ["old@x.com"]);
        assert!(library.shared_skipped().unwrap().is_empty());
    }

    #[test]
    fn removing_a_shared_mailbox_keeps_mail_that_is_also_elsewhere() {
        let dir = tempfile::tempdir().unwrap();
        let mut library = Library::open(&dir.path().join("lib"), Access::Write, &Silent).unwrap();
        let mut files = Vec::new();
        for n in 1..=3 {
            let file = dir.path().join(format!("{n}.eml"));
            std::fs::write(&file, format!("From: ann@a.com\r\nTo: noc@x.com\r\nSubject: Hi {n}\r\nMessage-ID: <{n}@a>\r\n\r\nHello\r\n")).unwrap();
            files.push(file);
        }
        import(&mut library, &files, &ImportOptions { destination: Some("Inbox".into()), ..Default::default() }, &Silent).unwrap();
        let conn = &library.conn;
        let mine: i64 = conn.query_row("SELECT f.account FROM locations l JOIN folders f ON f.id = l.folder LIMIT 1", [], |r| r.get(0)).unwrap();
        let shared = library.show_shared_mailbox("noc@x.com").unwrap();
        assert_ne!(mine, shared);
        let inbox = crate::db::ensure_folder(conn, shared, "Inbox").unwrap();
        let sub = crate::db::ensure_folder(conn, shared, "Inbox/Alerts").unwrap();
        let ids: Vec<i64> = conn.prepare("SELECT id FROM messages ORDER BY id").unwrap().query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect();
        // message 1 is also in the user's own mailbox; 2 and 3 only in the shared one
        conn.execute("INSERT INTO locations (message, folder, date) SELECT id, ?2, date FROM messages WHERE id = ?1", params![ids[0], inbox]).unwrap();
        conn.execute("DELETE FROM locations WHERE message IN (?1, ?2)", params![ids[1], ids[2]]).unwrap();
        conn.execute("INSERT INTO locations (message, folder, date) SELECT id, ?2, date FROM messages WHERE id = ?1", params![ids[1], inbox]).unwrap();
        conn.execute("INSERT INTO locations (message, folder, date) SELECT id, ?2, date FROM messages WHERE id = ?1", params![ids[2], sub]).unwrap();
        assert_eq!(library.remove_shared_mailbox("NOC@x.com").unwrap(), 3);
        // gone from the list at once, and the download leaves it alone
        assert!(library.shared_skipped().unwrap().contains("noc@x.com"));
        assert!(!library.shared_list().unwrap().mailboxes.iter().any(|r| r.added));
        // two rounds of two: then the account goes
        let (_, done, left) = library.remove_shared_step(2).unwrap().unwrap();
        assert_eq!((done, left), (2, 1));
        let (_, done, left) = library.remove_shared_step(2).unwrap().unwrap();
        assert_eq!((done, left), (1, 0));
        assert!(library.remove_shared_step(2).unwrap().is_none());
        let conn = &library.conn;
        let messages: Vec<i64> = conn.prepare("SELECT id FROM messages").unwrap().query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect();
        assert_eq!(messages, [ids[0]]);
        let places: i64 = conn.query_row("SELECT COUNT(*) FROM locations WHERE message = ?1", params![ids[0]], |r| r.get(0)).unwrap();
        assert_eq!(places, 1);
        let accounts: i64 = conn.query_row("SELECT COUNT(*) FROM accounts WHERE id = ?1", params![shared], |r| r.get(0)).unwrap();
        let folders: i64 = conn.query_row("SELECT COUNT(*) FROM folders WHERE account = ?1", params![shared], |r| r.get(0)).unwrap();
        assert_eq!((accounts, folders), (0, 0));
        assert!(library.shared_removing().unwrap().is_empty());
        // ticked again: back, empty, ready for the download
        library.show_shared_mailbox("noc@x.com").unwrap();
        assert!(library.shared_list().unwrap().mailboxes.iter().any(|r| r.added && r.address == "noc@x.com"));
    }
}

// A contact file (.vcf) opened with Eleonora: each contact in it, matched against the address book
// by email address or phone number. One already there: Update it (the file's values where they
// differ, everything it had kept), or add it as a new contact anyway; one that isn't: Add to
// contacts, into the account chosen.
"use strict";

const TAURI = window.__TAURI__;
const invoke = TAURI.core.invoke;
const $ = (id) => document.getElementById(id);
const fileNumber = Number(new URLSearchParams(location.search).get("file"));

function el(tag, className, text) {
  const e = document.createElement(tag);
  if (className) e.className = className;
  if (text !== undefined) e.textContent = text;
  return e;
}

// the look chosen in the main window (same storage)
function applySkin(key) {
  let skin = "eudora";
  try { skin = key || JSON.parse(localStorage.getItem("eudora.skin") || '"eudora"'); } catch { skin = "eudora"; }
  document.body.className = skin === "eudora-classic" ? "skin-eudora classic ics-file" : `skin-${skin} ics-file`;
}
applySkin();
window.addEventListener("storage", (e) => { if (e.key === "eudora.skin") applySkin(); });
TAURI.event.listen("skin", (e) => applySkin(e.payload));

const KINDS = { work: "Work", home: "Home", mobile: "Mobile", fax: "Fax", other: "Other" };

function row(box, label, text) {
  if (!text) return;
  const r = el("div", "ics-row");
  r.append(el("b", null, label), el("span", null, text));
  box.append(r);
}

/** A contact's address as lines. */
function addressText(a) {
  return [a.street, [a.city, a.region, a.postal_code].filter(Boolean).join(" "), a.country].filter(Boolean).join("\n");
}

let file = null;
// each contact's state: "added" / "updated" once done
const done = new Map();

async function save(index, how, button, box) {
  button.disabled = true;
  const pick = $("v-account");
  try {
    if (how.update != null) {
      await invoke("vcf_save", { file: fileNumber, contact: index, account: null, update: how.update });
      done.set(index, "updated");
      finish(box, `Updated ${how.name}.`);
    } else {
      await invoke("vcf_save", { file: fileNumber, contact: index, account: Number(pick.value), update: null });
      done.set(index, "added");
      finish(box, `Added to ${pick.options[pick.selectedIndex]?.textContent || "your contacts"}.`);
    }
    showAll();
  } catch (err) {
    button.disabled = false;
    tell("Saving the contact", String(err));
  }
}

function finish(box, text) {
  const actions = box.querySelector(".ics-actions");
  actions.replaceChildren(el("span", "ics-done", text));
}

/** For a file of several contacts: one click for every one still waiting, asked first. */
function showAll() {
  const bar = $("v-all");
  if (!file || file.contacts.length < 2) { bar.hidden = true; return; }
  const waiting = file.contacts.map((c, i) => [c, i]).filter(([, i]) => !done.has(i));
  const fresh = waiting.filter(([c]) => !c.matches.length);
  const known = waiting.filter(([c]) => c.matches.length === 1);
  bar.replaceChildren();
  if (fresh.length) {
    const b = el("button", "primary", `Add all ${fresh.length.toLocaleString()} new`);
    b.addEventListener("click", async () => {
      const where = $("v-account").options[$("v-account").selectedIndex]?.textContent || "your contacts";
      if (!(await askYesNo(`Add ${fresh.length.toLocaleString()} contacts?`, `The contacts in this file that aren't in your address book yet go to ${where}.`, "Add them"))) return;
      await runAll(fresh, (i) => ({ account: Number($("v-account").value), update: null }), "added");
    });
    bar.append(b);
  }
  if (known.length) {
    const b = el("button", "", `Update all ${known.length.toLocaleString()} already there`);
    b.addEventListener("click", async () => {
      if (!(await askYesNo(`Update ${known.length.toLocaleString()} contacts?`, "Each contact already in your address book takes this file's values where they differ, and keeps every email address, phone number, and address it had.", "Update them"))) return;
      await runAll(known, (i) => ({ account: null, update: file.contacts[i].matches[0].id }), "updated");
    });
    bar.append(b);
  }
  bar.hidden = !bar.children.length;
}

async function runAll(items, how, state) {
  let ok = 0, failed = 0;
  for (const [, i] of items) {
    try {
      await invoke("vcf_save", { file: fileNumber, contact: i, ...how(i) });
      done.set(i, state);
      ok++;
      const box = $("v-contacts").children[i];
      if (box) finish(box, state === "added" ? "Added." : "Updated.");
    } catch { failed++; }
    $("v-about").textContent = `${state === "added" ? "Adding" : "Updating"} contacts: ${ok + failed} of ${items.length}…`;
  }
  $("v-about").textContent = `${ok.toLocaleString()} ${state}${failed ? `; ${failed.toLocaleString()} couldn't be` : ""}.`;
  showAll();
}

async function show() {
  try {
    file = await invoke("vcf_file", { file: fileNumber });
  } catch (err) {
    $("v-about").textContent = String(err);
    return;
  }
  $("v-name").textContent = file.name;
  document.title = `${file.name} – Eleonora`;
  const n = file.contacts.length;
  const known = file.contacts.filter((c) => c.matches.length).length;
  $("v-about").textContent = `${n === 1 ? "One contact" : `${n.toLocaleString()} contacts`} in it` +
    (known ? `; ${known === n ? (n === 1 ? "it's" : "all are") : `${known.toLocaleString()} ${known === 1 ? "is" : "are"}`} already in your address book.` : ".");

  // the address books a new contact can go to (the one used last first)
  const pick = $("v-account");
  for (const t of file.targets) {
    const o = el("option", null, `${t.address} (${t.service})`);
    o.value = t.account;
    pick.append(o);
  }
  if (file.new_in != null) pick.value = String(file.new_in);
  if (!file.targets.length) {
    pick.disabled = true;
    pick.append(el("option", null, "No address book to add to: add a Microsoft 365, Google, or CardDAV account first"));
  }

  const list = $("v-contacts");
  file.contacts.forEach((c, i) => {
    const card = c.card;
    const box = el("div", "ics-event");
    box.setAttribute("role", "listitem");
    box.append(el("h2", null, c.shown || "(no name)"));
    const what = [card.title, card.department, card.company].filter(Boolean).join(", ");
    if (what) box.append(el("p", "vcf-what", what));
    for (const e of card.emails || []) row(box, KINDS[e.kind] ? `${KINDS[e.kind]} email` : "Email", e.value);
    for (const p of card.phones || []) row(box, KINDS[p.kind] || "Phone", p.value);
    for (const a of card.addresses || []) row(box, KINDS[a.kind] ? `${KINDS[a.kind]} address` : "Address", addressText(a));
    for (const w of card.websites || []) row(box, "Website", w);
    row(box, "Birthday", card.birthday);
    row(box, "Notes", card.notes);

    const actions = el("div", "ics-actions");
    if (c.matches.length) {
      const m = el("div", "vcf-match");
      m.textContent = c.matches.length === 1
        ? `Already in your contacts as ${c.matches[0].shown || "a contact"} (${c.matches[0].account_address}).`
        : `Already in your contacts ${c.matches.length} times (the same email address or phone number).`;
      box.append(m);
      for (const match of c.matches) {
        const name = match.shown || "the contact";
        const b = el("button", "primary", c.matches.length === 1 ? `Update ${name}` : `Update ${name} (${match.account_address})`);
        b.addEventListener("click", () => save(i, { update: match.id, name }, b, box));
        actions.append(b);
      }
      const add = el("button", "", "Add as a new contact");
      add.disabled = !file.targets.length;
      add.addEventListener("click", () => save(i, {}, add, box));
      actions.append(add);
    } else {
      box.append(el("div", "vcf-match new", "Not in your contacts yet."));
      const add = el("button", "primary", "Add to contacts");
      add.disabled = !file.targets.length;
      add.addEventListener("click", () => save(i, {}, add, box));
      actions.append(add);
    }
    box.append(actions);
    list.append(box);
  });
  showAll();
  // (one contact: its main choice has the keyboard at once)
  list.querySelector(".ics-actions .primary")?.focus();
}

show();

#!/bin/bash
# The Mac's install-dev.ps1: puts the Eleonora just built into ~/Applications/Eleonora.app (a real
# app bundle, signed with the Developer ID by scripts/mac_app.sh: its own Dock icon, Spotlight and
# Launchpad, and .eml / .ics files open with it), then starts it again. The build's own
# target/release/eleonora is never the copy that runs, so rebuilding never touches a running
# program (2026-10-27, first Mac build).
#
#   bash scripts/install-dev.sh                 # install, restart Eleonora on the usual library
#   bash scripts/install-dev.sh --no-start      # install only
#
# The library is Eleonora's usual one (~/Library/Application Support/Eleonora/Library) or the one
# last opened by name; never put it inside Dropbox. Eudora 1.x's development copy
# (~/Applications/Eudora.app) is removed.
set -euo pipefail
start=1
[ "${1:-}" = "--no-start" ] && start=0

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$HOME/Applications/Eleonora.app"
old_app="$HOME/Applications/Eudora.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# made in full beside the old one, then put in place by renaming
bash "$root/scripts/mac_app.sh" "$app.new"

if [ $start = 1 ]; then
    # the window (eleonora; eudora in 1.x) and its background download too (it runs from
    # <library>/bin and would stay on the old program): the window starts the new one within 30 s,
    # and it resumes where it was
    pkill -x eleonora 2>/dev/null || true
    pkill -x eudora 2>/dev/null || true
    pkill -f "/bin/eleonora-cli -l .* graph download" 2>/dev/null || true
    pkill -f "/bin/eudora-cli -l .* graph download" 2>/dev/null || true
    sleep 2
fi
rm -rf "$app.old"
[ -e "$app" ] && mv "$app" "$app.old"
mv "$app.new" "$app"
rm -rf "$app.old"
if [ -d "$old_app" ]; then
    "$lsregister" -u "$old_app" >/dev/null 2>&1 || true
    rm -rf "$old_app" && echo "Removed $old_app"
fi
# tells Finder and Launch Services about the bundle (icon, Open With for .eml / .ics)
"$lsregister" -f "$app" >/dev/null 2>&1 || true
echo "Installed $app"

if [ $start = 1 ]; then
    open "$app"
    sleep 6
    if pgrep -x eleonora >/dev/null; then echo "Eleonora is running from $app (process $(pgrep -x eleonora | tr '\n' ' '))."; else echo "Eleonora did not start." >&2; exit 1; fi
fi

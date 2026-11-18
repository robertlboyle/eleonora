#!/bin/bash
# The Mac's build-installer.ps1: dist/Eleonora-<version>.dmg, signed with the Developer ID and
# notarized by Apple, as PlanetPDF's build_mac.py does. One app for Apple silicon and Intel Macs
# (universal).
#
# Also dist/Eleonora-<version>-for-Eudora.dmg, the bridge for Eudora 1.x (docs/RENAME-ELEONORA.md):
# the same signed app, named Eudora.app in the disk image, which is what 1.x's updater looks for;
# Eleonora renames itself to Eleonora.app when it first starts (core update.rs, rename_mac_bundle).
# Publish it with `eleonora-release publish --bridge --platform macos --file …-for-Eudora.dmg`.
#
#   bash scripts/build-mac.sh                       # build, app, notarize, disk image
#   bash scripts/build-mac.sh --no-build            # use what target/release has
#   bash scripts/build-mac.sh --notary-profile NAME # default "PlanetPDF" (the same Apple team)
#
# Notarizing needs a notarytool keychain profile, made once on this Mac by the user (it asks for
# an app-specific password from account.apple.com, typed by the user, never in chat):
#   xcrun notarytool store-credentials PlanetPDF --apple-id <Apple ID> --team-id TEAMID1234
# Without it the .dmg is signed but not notarized, and says so.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build=1
profile="PlanetPDF"
while [ $# -gt 0 ]; do
    case "$1" in
        --no-build) build=0 ;;
        --notary-profile) profile="$2"; shift ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
version="$(sed -n 's/^ *"version": *"\(.*\)",*$/\1/p' "$root/crates/eleonora-app/tauri.conf.json" | head -1)"
dist="$root/dist"
work="$dist/mac-work"
app="$work/Eleonora.app"
dmg="$dist/Eleonora-$version.dmg"
bridge="$dist/Eleonora-$version-for-Eudora.dmg"
steps=5
step() { echo; echo "Step $1 of $steps: $2"; }

step 1 "Building (release)"
if [ $build = 1 ]; then
    # one app for both kinds of Mac: Apple silicon (native) and Intel, joined by lipo
    (cd "$root" && cargo build --release -p eleonora-app -p eleonora-cli)
    (cd "$root" && cargo build --release --target x86_64-apple-darwin -p eleonora-app -p eleonora-cli)
else
    echo "Skipped (--no-build)"
fi

universal="$root/target/universal"
mkdir -p "$universal"
for name in eleonora eleonora-cli; do
    lipo -create "$root/target/release/$name" "$root/target/x86_64-apple-darwin/release/$name" -output "$universal/$name"
done
export ELEONORA_MAC_BUILD="$universal"

step 2 "Making and signing Eleonora.app (Apple silicon and Intel)"
rm -rf "$work"
mkdir -p "$work"
bash "$root/scripts/mac_app.sh" "$app" --release
identity="$(security find-identity -v -p codesigning | sed -n 's/.*\([0-9A-F]\{40\}\) "Developer ID Application: .*/\1/p' | head -1)"

notarize() {  # file: sent to Apple, waited for, the ticket stapled on
    local target="$1" send="$1"
    if [ "${target##*.}" = "app" ]; then
        send="$work/Eleonora.zip"
        ditto -c -k --keepParent "$target" "$send"
    fi
    xcrun notarytool submit "$send" --keychain-profile "$profile" --wait
    xcrun stapler staple "$target"
}

step 3 "Notarizing the app"
notarized=0
if [ -z "$identity" ]; then
    echo "Skipped: no Developer ID certificate in the keychain"
elif ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "Skipped: no notarytool profile \"$profile\" on this Mac (see the top of this script)"
else
    notarize "$app"
    notarized=1
fi

step 4 "The disk images"
# (make_dmg FILE NAME-OF-THE-APP-IN-IT)
make_dmg() {
    local out="$1" name="$2" stage="$work/dmg" rw="$work/rw.dmg" mount="$work/mount"
    rm -rf "$stage"
    mkdir -p "$stage"
    ditto "$app" "$stage/$name"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname Eleonora -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$rw" >/dev/null
    mkdir -p "$mount"
    hdiutil attach "$rw" -nobrowse -noautoopen -mountpoint "$mount" >/dev/null
    # the mounted disk shows Eleonora's icon (Finder's custom-icon flag on the disk)
    cp "$app/Contents/Resources/Eleonora.icns" "$mount/.VolumeIcon.icns"
    xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "$mount"
    hdiutil detach "$mount" -quiet
    rm -f "$out"
    hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$out" >/dev/null
    rm -f "$rw"
    [ -n "$identity" ] && codesign --force --sign "$identity" --timestamp "$out"
    return 0
}
make_dmg "$dmg" Eleonora.app
# the bridge for Eudora 1.x's updater (see the top)
make_dmg "$bridge" Eudora.app

step 5 "Notarizing the disk images"
if [ $notarized = 1 ]; then
    for image in "$dmg" "$bridge"; do
        notarize "$image"
        spctl --assess --type open --context context:primary-signature -v "$image"
    done
else
    echo "Skipped (the app wasn't notarized): other Macs will refuse to open it until it is"
fi
rm -rf "$work"
echo
echo "$dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '))"
echo "$bridge ($(du -h "$bridge" | cut -f1 | tr -d ' '); the bridge for Eudora 1.x)"

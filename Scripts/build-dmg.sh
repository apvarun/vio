#!/usr/bin/env bash
# Adapted from Dmgly's Swift / macOS create-dmg export.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-preview}"
fail() { echo "Error: $*" >&2; exit 1; }
[[ "$MODE" == preview || "$MODE" == release || "$MODE" == check-release ]] || fail "Usage: $0 [preview|release|check-release]"
if [[ "$MODE" != preview ]]; then
    [[ -n "${SIGNING_IDENTITY:-}" ]] || fail 'Set SIGNING_IDENTITY to your Developer ID Application identity.'
    [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || fail 'SIGNING_IDENTITY must be a Developer ID Application certificate name.'
    [[ -n "${NOTARY_PROFILE:-}" ]] || fail 'Set NOTARY_PROFILE to your notarytool Keychain profile.'
fi
command -v create-dmg >/dev/null || fail 'Install create-dmg with: brew install create-dmg'
[[ "$MODE" != check-release ]] || exit 0
[[ "$(uname -m)" == arm64 ]] || fail 'Vio requires an Apple Silicon Mac.'
APP="$ROOT/build/Vio.app"
[[ -d "$APP" ]] || fail 'Build the app first with make app.'
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]] || fail 'Invalid release version in Info.plist.'
DEST="$ROOT/build/releases"
mkdir -p "$DEST"
OUTPUT="$DEST/Vio-$VERSION-arm64.dmg"
[[ ! -e "$OUTPUT" && ! -e "$OUTPUT.sha256" ]] || fail "Output exists: $OUTPUT. Move the previous artifact before rebuilding."
WORK="$(mktemp -d "$ROOT/build/dmg.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/payload"
ditto "$APP" "$WORK/payload/Vio.app"
STAGED_APP="$WORK/payload/Vio.app"
notarize() {
    local artifact="$1" label="$2"
    if ! xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$WORK/$label.json"; then
        cat "$WORK/$label.json" >&2
        fail "Notarization submission failed for $label."
    fi
    local status submission
    status="$(plutil -extract status raw "$WORK/$label.json")"
    submission="$(plutil -extract id raw "$WORK/$label.json")"
    xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" "$DEST/Vio-$VERSION-$label-notary.json"
    [[ "$status" == Accepted ]] || fail "Notarization rejected $label. See $DEST/Vio-$VERSION-$label-notary.json"
}
if [[ "$MODE" == release ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements "$ROOT/Resources/DMG/release.entitlements" "$STAGED_APP"
    codesign --verify --strict --verbose=2 "$STAGED_APP"
    ditto -c -k --keepParent "$STAGED_APP" "$WORK/Vio.zip"
    notarize "$WORK/Vio.zip" app
    xcrun stapler staple "$STAGED_APP"
    xcrun stapler validate "$STAGED_APP"
    spctl --assess --type execute --verbose=2 "$STAGED_APP"
fi
create-dmg --volname Vio --volicon "$ROOT/build/Vio.icns" \
    --window-size 720 460 --icon-size 100 --text-size 13 \
    --icon Vio.app 195 230 --app-drop-link 525 230 --hide-extension Vio.app \
    --background "$ROOT/Resources/DMG/background.tiff" \
    "$WORK/Vio.dmg" "$WORK/payload"
hdiutil verify "$WORK/Vio.dmg"
if [[ "$MODE" == release ]]; then
    codesign --sign "$SIGNING_IDENTITY" --timestamp "$WORK/Vio.dmg"
    codesign --verify --strict --verbose=2 "$WORK/Vio.dmg"
    notarize "$WORK/Vio.dmg" dmg
    xcrun stapler staple "$WORK/Vio.dmg"
    xcrun stapler validate "$WORK/Vio.dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$WORK/Vio.dmg"
fi
mv "$WORK/Vio.dmg" "$OUTPUT"
(cd "$DEST" && shasum -a 256 "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256")
echo "Built $MODE installer: $OUTPUT"
[[ "$MODE" != preview ]] || echo 'Preview only: ad-hoc signed app, no notarization. Do not publish as an official release.'

# Building Vio installers

Vio's source is MIT licensed. Official downloads are signed by the maintainer and
notarized by Apple. Contributors can build locally without an Apple account.
The bundled model and engine retain their Apache-2.0 notices inside the app.

## Preview the installer

Install Xcode's command line tools and the packaging dependency:

```sh
brew install create-dmg
make dmg
```

The output is `build/releases/Vio-0.1.0-arm64.dmg` and a matching `.sha256` file.
The version comes from `Info.plist`. This preview contains an ad-hoc signed app
and is not notarized. Move the preview out of the output directory before making
an official release of the same version. Existing artifacts are never overwritten.

The layout adapts [Dmgly's Swift / macOS export](https://dmgly.com/) using
[create-dmg](https://github.com/create-dmg/create-dmg). The committed
`Resources/DMG/design.json` records the layout. Edit the vector drawing in
`Scripts/render-dmg.swift` and run `make dmg-artwork` to regenerate the committed
1440 × 920 PNG preview and a TIFF with 1× and 2× representations for Finder.
Both use the same 720 × 460 point layout. The artwork is redrawn from vectors at
each resolution, so text and strokes stay sharp on Retina displays.

`Resources/vio.icon` is the Icon Composer source for the app icon. `make app-icon`
uses Xcode's asset compiler to generate the layered `Assets.car` and an ICNS image.
The app bundles both. The DMG uses the same icon for its volume, its draggable app,
and the background header. Installer builds regenerate the background from the
current icon automatically.

## Set up signing once

With a paid Apple Developer Program membership, create a **Developer ID
Application** certificate in Xcode's Accounts settings or Apple's developer
portal. Import it into your login Keychain with the associated private key.
A Developer ID Installer certificate is for PKG installers and is not needed here.
An Apple Development certificate is not suitable for this release workflow.

List available signing identities:

```sh
security find-identity -v -p codesigning
```

Create an app-specific password for your Apple Account, then store notarization
credentials interactively in Keychain:

```sh
xcrun notarytool store-credentials "vio-notary"
```

Enter your Apple Account, Team ID, and app-specific password when prompted.
Do not paste credentials into chat or commit them to the repository.
See [Apple's Developer ID guide](https://developer.apple.com/developer-id/) and
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Build an official release

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`, then:

```sh
export SIGNING_IDENTITY='Developer ID Application: Your Name (YOURTEAMID)'
export NOTARY_PROFILE='vio-notary'
make test
make selftest
make release
```

The script signs a clean copy of the app with hardened runtime, a secure timestamp,
and audio-input permission. It notarizes and staples the app before packaging,
then signs, notarizes, and staples the DMG. Apple must return `Accepted` for both
submissions. Signature, ticket, and Gatekeeper checks must pass before the final
DMG and checksum appear. Notarization logs are retained in `build/releases/`.
If a step fails, fix the reported problem and retry. No unsigned fallback exists.
The normal `build/Vio.app` stays available for contributor development.

Your Team ID and certificate name are public identifiers. The signature exposes
your publisher identity. Pass them as configuration rather than hardcoding them.
Keep private keys, certificate exports, passwords, and API keys in Keychain.
The repo ignores `.p12`, `.p8`, `.key`, and `.env` files as a precaution.
Fork maintainers use their own signing identities and notarization accounts.

## Verify and publish

Mount the final DMG and check the background, labels, arrow, and Applications link.
Drag Vio to Applications and launch that installed copy on an Apple Silicon Mac
running macOS 26 or newer. On a fresh account, verify the microphone prompt,
recording and transcription, Accessibility prompt and paste, and launch at login.
Check that launch at login points to the installed copy. Test a browser-downloaded
copy on another Mac to exercise quarantine and Gatekeeper.

```sh
cd build/releases
shasum -a 256 -c Vio-0.1.0-arm64.dmg.sha256
```

Create a GitHub Release for the matching `v<version>` source tag and upload the
verified `.dmg` and `.dmg.sha256`. Include Apple Silicon and macOS 26 requirements
in the release notes. Publish only the official release output after the manual
checks pass. Notarization logs are local diagnostics and need not be uploaded.

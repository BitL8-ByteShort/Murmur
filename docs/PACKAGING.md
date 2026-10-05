# Packaging Murmur

The installer is a compressed `.dmg` containing `Murmur.app`, an
Applications shortcut, short install instructions, and full license documents. The app inside is signed
with **Developer ID Application: Salty Panda LLC** and notarized by Apple.
The current public preview is version 0.2.2 (build 4), available from
[GitHub Releases](https://github.com/BitL8-ByteShort/Murmur/releases/tag/v0.2.2-public-preview.1).
The Mac App Store is not a distribution channel for this release.

## Install the app

Open the DMG, drag Murmur into Applications, eject the image, and open the
installed app. It requires macOS 26 or later and Apple Silicon. Xcode isn't required to run it.

Speech models aren't bundled into the DMG. Apple Speech is the default, and the
other three models can be downloaded inside the app. Updating the app preserves
preferences and models in `~/Library/Application Support/Murmur/`.

## Build a signed installer

Run from the repository root:

```sh
./script/package_dmg.sh
```

The script archives the Release configuration, exports using Developer ID,
submits the app for notarization, attaches Apple's ticket, and verifies the
signature and Gatekeeper assessment before making the disk image. It also writes
a SHA-256 checksum next to the DMG.

This uses the Apple account signed into Xcode and the Salty Panda team in
`script/ExportOptions.plist`. Xcode can use the team's cloud-managed Developer ID
certificate even when it doesn't appear in the local keychain's identity list.
No private key or Apple password is stored in the repository.

Outputs:

- `dist/Murmur-<version>-arm64.dmg`
- `dist/Murmur-<version>-arm64.dmg.sha256`
- Build, export, and notarization logs under `build/packaging/`

The filename and install instructions follow the exported bundle's version
and build, set in `Resources/Info.plist`.
The current source and installer are 0.2.2 (build 4). Each new installer must
pass its own signing, notarization, and validation checks before upload.
Generated installers, archives, models, and build logs are ignored by Git. Installers can be attached
to this repository's GitHub releases. Keep preview releases marked as prereleases
and include a link to the [bug-report form](https://github.com/BitL8-ByteShort/Murmur/issues/new?template=bug_report.yml).

To package an app that is already signed, notarized, and stapled:

```sh
./script/package_dmg.sh --app build/packaging/export/Murmur.app
```

The same validation gates run before packaging. A development-signed app or one
without a valid notarization ticket won't pass.

## License documents

`Sources/Murmur/Licenses/` contains the full third-party texts and a manifest with source
URLs, dependency revisions, and checksums. The app includes that folder, the
project's `LICENSE`, and `THIRD_PARTY_NOTICES.md` as signed resources. The same
documents are copied beside the app on the disk image.

Packaging checks dependency pins against the inventory and verifies every
document in the exported app before creating the installer:

```sh
python3 script/verify_licenses.py
python3 script/verify_licenses.py --bundle build/packaging/export/Murmur.app
```

Update the inventory and license documents when changing dependency versions.
Optional model downloads receive their own terms before downloading weights;
models installed by earlier releases receive those documents when first used.

## If notarization hasn't finished

Upload success alone doesn't mean approval. The script waits for the ticket and
stops if it isn't available. Check the archive's status in Xcode Organizer, then
attach and validate the ticket before trying the packaging-only command:

```sh
xcrun stapler staple build/packaging/export/Murmur.app
xcrun stapler validate build/packaging/export/Murmur.app
spctl --assess --type execute -vv build/packaging/export/Murmur.app
```

The Gatekeeper result should be `accepted` with `source=Notarized Developer ID`.
See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
for signing requirements and failed-submission diagnostics.

The DMG wraps the notarized app; this process doesn't claim a separate signature
or notarization ticket for the disk-image container itself.

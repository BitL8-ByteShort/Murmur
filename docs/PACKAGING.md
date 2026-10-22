# Packaging Murmur

The installer is a compressed `.dmg` containing `Murmur.app`, an
Applications shortcut, short install instructions, and full license documents. The app inside is signed
with **Developer ID Application: Salty Panda LLC** and notarized by Apple.
The open-source release is version 0.2.4 (build 6), available from
[GitHub Releases](https://github.com/BitL8-ByteShort/Murmur/releases/tag/v0.2.4).
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
- Matching source archive and checksum prepared from the release tag (below)
- Build, export, and notarization logs under `build/packaging/`

The filename and install instructions follow the exported bundle's version
and build, set in `Resources/Info.plist`.
The current version is 0.2.4 (build 6). Each new installer must
pass its own signing, notarization, and validation checks before upload.
Generated installers, archives, models, and build logs are ignored by Git. Installers can be attached
to this repository's GitHub releases. Include source access and a link to the
[bug-report form](https://github.com/BitL8-ByteShort/Murmur/issues/new?template=bug_report.yml).
Open-source licensing does not imply completion of the remaining hardware checks.

To package an app that is already signed, notarized, and stapled:

```sh
./script/package_dmg.sh --app build/packaging/export/Murmur.app
```

The same validation gates run before packaging. A development-signed app or one
without a valid notarization ticket won't pass.

## License documents

`Sources/Murmur/Licenses/` contains the full third-party texts and a manifest with source
URLs, dependency revisions, and checksums. The app includes that folder, the
project's `LICENSE`, `NOTICE`, `SOURCE.md`, `TRADEMARKS.md` and
`THIRD_PARTY_NOTICES.md` as signed resources. The same
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

## Source access with each installer

Version 0.2.4 is GPL-3.0-only. After committing and tagging the exact release
source, create its source archive and checksum:

```sh
git archive --format=tar.gz --prefix=Murmur-0.2.4/ \
  -o dist/Murmur-0.2.4-source.tar.gz v0.2.4
(cd dist && shasum -a 256 Murmur-0.2.4-source.tar.gz > Murmur-0.2.4-source.tar.gz.sha256)
```

Attach both source files beside the DMG/checksum on the same release. Link the
archive and [SOURCE.md](../SOURCE.md) directly in the release notes. That document
identifies pinned Swift/native sources, their build scripts and dependency
records. Confirm that source and binary downloads are accessible without login.
Maintain equivalent access if an upstream source location becomes unavailable.

Historical 0.2.3 and earlier installers contain their original preview terms;
the GPL release replaces the current download rather than changing those files.

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

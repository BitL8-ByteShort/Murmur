# Source for Murmur 0.2.4 (build 6)

Murmur's first-party code and documentation are GNU GPL version 3 only.
See LICENSE and NOTICE. Source access is free and does not require an account.

## This release

- [Release, installer and matching source archive](https://github.com/BitL8-ByteShort/Murmur/releases/tag/v0.2.4)
- [Browse the release source](https://github.com/BitL8-ByteShort/Murmur/tree/v0.2.4)
- [Download the release source](https://github.com/BitL8-ByteShort/Murmur/archive/refs/tags/v0.2.4.tar.gz)

The release also attaches `Murmur-0.2.4-source.tar.gz` and its SHA-256 checksum.
That archive contains the application, tests, project generator, build/packaging
scripts, license documents and dependency lockfiles from the release tag.
The dependencies below are provided separately at the pinned source locations.
Keep these source links beside the installer when mirroring this release.

## Build and install a modified version

Use Apple Silicon, macOS 26+, Xcode 26 with its command-line tools and Swift 6.
Extract the source archive and run these commands from its root:

```sh
swift test
MURMUR_SIGN_IDENTITY=- ./scripts/build-app.sh
open build/Murmur.app
```

This makes an ad-hoc-signed development build. macOS may require renewed
microphone/Accessibility approval for a different signing identity. A paid Apple
account or the publisher's signing key is not needed to modify or run the code.
Use your own development identity with `MURMUR_SIGN_IDENTITY` if desired.

The checked-in Xcode project can also be opened directly. Regenerate it with
`python3 script/generate_project.py` after adding Swift files. Public Developer
ID signing and notarization are described in docs/PACKAGING.md; use your own
team and export settings when distributing a separately signed build.

SwiftPM fetches the pinned packages and their native binary artifacts during
the normal build. These third-party components retain their original licenses;
their source, build scripts and further dependency records are linked below.
No native binary is modified by Murmur. This is not a claim of byte-identical
reproduction of upstream binaries or Apple's signed installer.

## Swift package sources

Package.resolved and Sources/Murmur/Licenses/manifest.json identify these pins.
Each linked commit offers GitHub's Code → Download ZIP and clone access.

| Package | Version | Exact source |
| --- | --- | --- |
| FluidAudio | 0.17.4 | [21493f8dac5a97e65742e6ff26f42f164c2fda0f](https://github.com/FluidInference/FluidAudio/tree/21493f8dac5a97e65742e6ff26f42f164c2fda0f) |
| MoonshineVoice | 0.1.5 | [45a14f9edf1f2a6913d3aff38c1fd4e72d5b7daa](https://github.com/moonshine-ai/moonshine-swift/tree/45a14f9edf1f2a6913d3aff38c1fd4e72d5b7daa) |
| WhisperKit / Argmax OSS | 1.1.0 | [1e2a163736dfa5a198e637ae44c114e1c6d5cc2d](https://github.com/argmaxinc/argmax-oss-swift/tree/1e2a163736dfa5a198e637ae44c114e1c6d5cc2d) |
| Swift Argument Parser | 1.8.2 | [6a52f3251125d74daf04fcbd5e6f08a75d074382](https://github.com/apple/swift-argument-parser/tree/6a52f3251125d74daf04fcbd5e6f08a75d074382) |

## Native libraries and their sources

**Moonshine.xcframework, from moonshine-swift 0.1.5:**
[native source and vendored dependencies at 234f60faa0eb388b01cdf7e60aca232af37aefda](https://github.com/moonshine-ai/moonshine/tree/234f60faa0eb388b01cdf7e60aca232af37aefda).
The same tree includes the build configuration in `core/CMakeLists.txt` and
`scripts/build-swift.sh`, and the Eigen 3.4 MPL-2.0 subset, kaldi-native-fbank,
KISS FFT, JSON, UTF-8 and other vendored source under `core/third-party`.
Its ONNX Runtime is 1.23.0:
[ONNX Runtime source and build tools at be835efc56aca19b8e810538ec93c8e150e0fc61](https://github.com/microsoft/onnxruntime/tree/be835efc56aca19b8e810538ec93c8e150e0fc61).
Moonshine supplies `scripts/build-ort-ios.sh`, `scripts/ort-build-common.sh` and
the required operator configuration under `core/third-party/onnxruntime`.
Follow the native repository's build instructions for the Xcode/CMake toolchain.

**NemoTextProcessing.xcframework 0.3.1, from FluidAudio:**
[native Rust source, grammars, Cargo.lock and build-xcframework.sh at 46ebddcea5e1ff673c2cb5256a1b6b0e6c4ff527](https://github.com/FluidInference/text-processing-rs/tree/46ebddcea5e1ff673c2cb5256a1b6b0e6c4ff527).
Cargo.lock pins each registry dependency and its source checksum. Their complete
source archives are publicly downloadable at
`https://static.crates.io/crates/<name>/<name>-<version>.crate` using those pins.
Install Rust and the Apple targets documented in `build-xcframework.sh`; that
script builds the `ffi,fst-engine` feature set and packages the framework.

To use modified native libraries, build their XCFrameworks and use local
`.binaryTarget(name:..., path:...)` entries in local copies of the Swift wrapper
packages. Point Murmur's Package.swift to those packages with `.package(path:)`.
When using Xcode, regenerate/update its package references to the same local
copies. The bundled notice inventory records the unmodified release artifacts'
checksums; update it when distributing a different dependency build.

## Scope and availability

All upstream source links above are supplied as part of the source access for
this release. Full third-party copyright/license texts and per-document source
URLs are in Sources/Murmur/Licenses and THIRD_PARTY_NOTICES.md. If a link stops
working, report it at https://github.com/BitL8-ByteShort/Murmur/issues so the
publisher can restore equivalent source access.

Apple frameworks, SDKs and system speech services are supplied by macOS/Xcode.
Optional downloadable model weights are not included in the installer or source
archive, and keep their separately presented licenses. Your dictated text does
not become GPL-covered merely because you use Murmur.

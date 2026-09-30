# Murmur

A little space for your voice.

Murmur is a native Mac dictation app. Put your cursor in an app, use a shortcut,
and talk. A small bar appears at the bottom of the screen, responds to your voice,
then gets out of the way.

**Current state: a working local dictation development preview.** Apple Speech,
Parakeet Realtime, Moonshine Small and Whisper Turbo are integrated. Text insertion
is implemented but requires macOS Accessibility permission; its hands-on checks
are tracked in [STATUS.md](docs/STATUS.md). This is not a public release.

- **Quick Talk:** say something, pause, and finish. Default shortcut: Control–Option–Space.
- **Keep Talking:** stay listening between thoughts. Default: Control–Option–D.
- **Show or close the bar:** Control–Option–B. Pin it without keeping the mic on.
- **Four looks:** Waveform, Aura, Aura Ring and a teal Particle Wave.
- **Adjustable visuals:** response strength, reduced motion, still mode, display and bottom spacing.
- **Local speech:** explicit language/model downloads. Downloading never selects a model or opens the microphone.
- **Editable shortcuts:** click a binding in Shortcuts to record it. Escape cancels recording or active dictation.
- **Recoverable text:** completed and partial words remain available for copying if insertion stops.

## Use the Mac app

Murmur is installed locally at `/Applications/Murmur.app`. Requires macOS 26+
and Apple Silicon. The microphone starts off at launch.

In **Speech models**, install the selected Apple language or download an optional
model, then choose **Use model**. Preparation happens when you start dictation;
Cancel remains available while it loads. Only the selected model stays loaded.

Allow Murmur in **System Settings → Privacy & Security → Accessibility** to type
into other apps. Put the cursor in a text field before using the shortcut.
Murmur checks that the same app and field are still focused. It refuses password
fields and multiline terminal insertion. It never presses Enter or sends a message.
Without this permission, or with **Copy only** enabled, use the transcript's Copy button.

**Appearance → Try live microphone** tests the visuals without transcribing.
Stop, Close, Cancel or Quit ends capture. The appearance sample with the mic off
is static and labeled. Raw audio isn't saved, and no transcript history is written
to disk. Recognized words remain in memory until cleared or the app quits. Starting again
archives the previous transcript for recovery; closing the bar keeps the words.

## Build, run and install

Requires Xcode with Swift 6. Dependencies are pinned in `Package.resolved`.

```sh
./script/build_and_run.sh --verify
./scripts/install-local.sh
swift test
```

The Codex Run action builds and opens `build/Murmur.app`. Local installation uses
Chris's existing Apple Development certificate for a stable identity across updates.
This is development signing, without Developer ID notarization or a public installer.
Override `MURMUR_SIGN_IDENTITY` to use a different local certificate.

The default test suite doesn't open a microphone or download models. Optional
integration checks use an explicitly supplied audio file and already installed assets;
see [Development](docs/DEVELOPMENT.md). Fixture recognition isn't human microphone evidence.

## Project guide

- [Product design](docs/superpowers/specs/2026-09-30-murmur-design.md)
- [Implementation plan](docs/superpowers/plans/2026-09-30-murmur.md)
- [Current status and validation](docs/STATUS.md)
- [Architecture and Teleprompter reuse](docs/ARCHITECTURE.md)
- [Development guide](docs/DEVELOPMENT.md)

The [GitHub repo](https://github.com/BitL8-ByteShort/Murmur) is **private** and must
stay that way until Chris explicitly approves making it public. Naming availability,
distribution licensing and pricing haven't been selected. Bundled SDK and model
notices are in `Sources/Murmur/Licenses`; model terms are also kept beside downloaded weights.

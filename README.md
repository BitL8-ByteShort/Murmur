# Murmur

A little space for your voice.

Murmur is a new native Mac dictation project. The goal is simple: put your cursor
in an app, use a shortcut, and talk. A small bar appears at the bottom of the
screen, responds to your voice, then gets out of the way.

**Current state: a buildable design scaffold.** It has a settings window, three
visualizer styles, a floating bar, and an optional live microphone preview.
It doesn't transcribe or insert text yet. Global shortcuts and model downloads
are planned, and they're labeled that way in the app.

## What we're aiming for

- **Quick Talk:** say something, pause, and finish.
- **Keep Talking:** stay listening between sentences until you stop it.
- **A bar you can pin:** keep it visible without keeping the microphone on.
- **Three looks:** a waveform, a soft aura, or colorful responding rings.
- **Local speech:** Apple Speech first, with optional downloadable local models.
- **Shortcuts you can change:** separate controls for talking and showing the bar.
- **Reliable insertion:** keep text recoverable when the target app changes or a paste fails.

Chris chose the name Murmur. Product naming availability hasn't been checked.

## Run the scaffold

Requires macOS 26+, Apple Silicon, and Xcode with Swift 6.

```sh
./script/build_and_run.sh
```

The Run action in Codex uses the same script. It quits the previous local Murmur
instance, builds `build/Murmur.app` with a local development signature, then opens it. It isn't
a signed and notarized installer for distribution. Use the app bundle for previewing
microphone permissions instead of launching the bare executable.

Choose a visualizer under **Appearance**. **Show voice bar** opens the small bar
with the mic off. **Try live microphone** asks macOS for access and drives the
visualizer with real input. That preview doesn't transcribe, save, or transmit audio.
**Stop**, **Close bar**, or **Quit** ends capture. Closing the bar also clears its
pin setting. Closing just the settings window leaves an explicitly started preview
running; its status remains in the voice bar and menu bar.

Appearance, pinning, and reduced-motion preferences are stored locally. Capture
always starts off after a fresh launch. The appearance sample shown with the mic
off is static and labeled as a preview.

## Build and test

```sh
swift build
swift test
```

There are no third-party package dependencies yet. The core library tests cover
session transitions, stale callbacks, pinned visibility, preference round trips,
and microphone meter bounds. They don't establish speech or insertion readiness.

## Project guide

- [Product design](docs/superpowers/specs/2026-09-30-murmur-design.md)
- [Implementation plan](docs/superpowers/plans/2026-09-30-murmur.md)
- [Current status and validation](docs/STATUS.md)
- [Architecture and Teleprompter reuse](docs/ARCHITECTURE.md)
- [Development guide](docs/DEVELOPMENT.md)

The GitHub repo must stay **private** until Chris explicitly approves making it public.
Distribution licensing and pricing haven't been selected.

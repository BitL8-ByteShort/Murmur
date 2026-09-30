# Murmur status

Updated September 30, 2026.

## Checkpoint

Native scaffold and implementation plan. This is not a finished voice transcriber.

| Area | Current state |
| --- | --- |
| Repository | [BitL8-ByteShort/Murmur](https://github.com/BitL8-ByteShort/Murmur), verified PRIVATE; main tracks origin/main |
| Native app | SwiftUI settings, menu bar entry, buildable .app bundle |
| Visuals | Waveform, soft Aura, layered Aura Ring; static labeled appearance sample |
| Floating bar | Nonactivating bottom-center panel; show/close and persistent pin setting |
| Microphone | Optional AVAudioEngine monitor implemented, driven by real samples; no recognition/audio persistence/network path |
| Preferences | Appearance, pinned bar and reduced motion stored locally; capture isn't persisted |
| Speech recognition | Planned; no backend integrated |
| Model downloads | Planned; no assets or external speech SDKs installed |
| Dictation shortcuts | Proposed defaults displayed; global registration/recorder planned |
| Target insertion | Planned; no Accessibility prompt or automatic paste |
| Distribution | Local ad-hoc development signature only; no release signing/notarization |

## Verified on the development Mac

Toolchain: Swift 6.4, Xcode 27.0, arm64 macOS environment.

- `./scripts/build-app.sh`: succeeds; builds `build/Murmur.app`.
- `swift test`: **7 tests passed**, covering Quick Talk/Keep Talking lifecycle,
  stale-session cancellation, duplicate/out-of-order transitions, pinned visibility
  without capture, silence/input meter differences, malformed-input bounds, preferences.
- `./script/build_and_run.sh --verify`: succeeds; one exact project app bundle running.
- Native UI inspection: settings opens with Mic off and no microphone prompt;
  Waveform initial preview, Aura and Aura Ring selectable; ring's layered colored
  shape and empty center visually checked. Planned features remain labeled.
- Codex Run action points to the project-local build/quit/relaunch script.
- GitHub repository created and pushed; API reports `isPrivate: true`, `visibility: PRIVATE`, default branch `main`.
- Initial scaffold commit: `47d8ed0`. Documentation checkpoint follows that commit.

Live microphone authorization/capture, stop/disconnect behavior, floating panel
placement across screens and actual focus preservation remain hands-on checks.
No simulated sample is being counted as live speech evidence. The app is left open
for Chris to review, with microphone off.

## Next increment

Implement plan Tasks 1–4: Apple Speech → Quick Talk/Keep Talking → editable hotkeys →
safe target insertion with recoverable text. Then add optional Parakeet downloads.
The [plan](superpowers/plans/2026-09-30-murmur.md) contains exact interfaces, checks,
failure behavior and release gates.

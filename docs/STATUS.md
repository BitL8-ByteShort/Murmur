# Murmur status

Updated September 30, 2026.

## Checkpoint

Local dictation development app installed at `/Applications/Murmur.app`. Public
release qualification remains separate from this working local app.

| Area | Current state |
| --- | --- |
| Repository | BitL8-ByteShort/Murmur, verified PRIVATE; development branch jorvek/murmur-app |
| Native app | SwiftUI settings, menu bar, custom icon, signed local .app installed in Applications |
| Visuals | Aura with no blur, faster Waveform/Aura/Ring; input requests 512-frame tap, meter capped at 60 Hz, 16 ms interpolation |
| Appearance | Response strength, still/reduced motion, display selection, bottom offset, independent pin/show/close |
| Crash repair | Original microphone callback moved outside MainActor; preview and dictation callback worker regressions pass |
| Capture | Real microphone start verified in packaged app; silence timeout returned it to Mic off without a crash |
| Recognition | Apple Speech, Parakeet, Moonshine and Whisper Turbo integrated; local fixture checks described below |
| Pauses | Recognizer-confirmed speech plus input energy; Quick Talk pause and Keep Talking utterance flush |
| Downloads | Explicit progress/cancel, selection separate, model receipts, recoverable deletion to Trash |
| Shortcuts | Three global defaults, editable recorder, repeat suppression, transactional rollback; native end-to-end checks pending |
| Insertion | Pinned target app/field, secure-field refusal, AX insertion or clipboard-preserving paste, no Enter; live app checks pending Accessibility permission |
| Privacy | No saved raw audio, no disk transcript history, no analytics/cloud fallback; latest transcript in memory |
| Distribution | Apple Development signature verified locally; no Developer ID/notarization/public installer |

## Accepted evidence

- Build and launch scripts succeed; exact installed app bundle has one running instance.
- `/Applications/Murmur.app` passes `codesign --verify --deep --strict`.
- 21 core tests and 3 app checks pass with the explicitly enabled Apple fixture.
  Core checks cover stale identity/revisions, text preservation, bounded queues,
  endpoints, shortcut conflicts/repeat/rollback, clipboard ownership, safe destination
  rules, insertion spacing, rolling audio windows, preferences and meter response.
- Both real audio callback factories are invoked on a worker with synthetic PCM buffers.
  The dictation tap converts 48 kHz audio into queued 16 kHz packets off the UI actor.
- Apple recognizes the generated sentence containing “local dictation” and
  “quick brown fox,” with partials, finals and a detected pause.
- Parakeet's actual Download button completed in the packaged app. It became
  available for Use model while Apple remained selected.
- Parakeet, Moonshine and Whisper each recognize the generated sentence twice across an
  utterance flush, with no duplicate phrase, and prepare a fresh warm session.
- Moonshine/Whisper model files were cloned into Murmur's separate storage from
  the existing Teleprompter downloads for integration checks. This did not select
  an engine or alter Teleprompter's assets. Whisper passed after its first model load.
- Packaged Apple capture was started through the native settings controls and
  returned to Mic off after the no-speech timeout. The initial live preview also
  showed nonzero levels without the original crash.
- GitHub API confirms `isPrivate: true`, `visibility: PRIVATE`.

The fixture is generated speech, not a human recording. Pure safety tests do not
establish insertion in TextEdit, a browser, an editor, a terminal or a chat app.
Apple's SpeechDetector result stream currently supports error reporting only;
the app therefore times pauses using input energy after recognition confirms words.
See [Apple's module documentation](https://developer.apple.com/documentation/speech/speechdetector).

## Remaining qualification

- Enable Accessibility for the installed app; verify global hotkeys, focus and
  actual text insertion with clipboard restoration in real destination apps.
- Hands-on human dictation, interruption/reconnect, sleep/wake, multi-display,
  full-screen Spaces and very long Keep Talking sessions.
- Optional download cancellation and deletion/re-download.
- Optional vocabulary/cleanup and opt-in disk history from the longer product plan.
- Developer ID signing, notarization, clean install/DMG, model licensing review and
  the release acceptance matrix before public distribution. Repo stays private.

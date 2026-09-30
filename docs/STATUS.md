# Murmur status

Updated September 30, 2026.

## Checkpoint

Local dictation development app installed at `/Applications/Murmur.app`. Public
release qualification remains separate from this working local app.

| Area | Current state |
| --- | --- |
| Repository | BitL8-ByteShort/Murmur, verified PRIVATE; development branch jorvek/murmur-app |
| Native app | SwiftUI settings, menu bar, custom icon, signed local .app installed in Applications |
| Visuals | Four styles: Waveform, Aura, Aura Ring and teal Particle Wave; no Aura blur; input requests 512-frame tap, meter capped at 60 Hz, 16 ms interpolation |
| Appearance | Response strength, still/reduced motion, display selection, bottom offset, independent pin/show/close |
| Crash repair | Original microphone callback moved outside MainActor; preview and dictation callback worker regressions pass |
| Capture | Packaged app recognizes generated speech played through the physical speakers into the built-in microphone; Quick Talk returns to Mic off without a crash |
| Recognition | Apple Speech, Parakeet, Moonshine and Whisper Turbo integrated; local fixture checks described below |
| Pauses | Recognizer-confirmed speech plus input energy; Quick Talk pause and Keep Talking utterance flush |
| Downloads | Explicit progress/cancel, selection separate, model receipts, recoverable deletion to Trash |
| Shortcuts | Three global defaults, editable recorder, repeat suppression, transactional rollback; native end-to-end checks pending |
| Insertion | Earlier native TextEdit insertion established; web editors now receive ordinary keyboard paste, output requires text readback for an Inserted status; updated Codex composer confirmation pending |
| Privacy | No saved raw audio, no disk transcript history, no analytics/cloud fallback; current and previous attempts recoverable in memory |
| Distribution | Apple Development signature verified locally; no Developer ID/notarization/public installer |

## Accepted evidence

- Build and launch scripts succeed. Switching from the installed app to Codex Run,
  then back to installation, leaves exactly one instance across both known bundles.
  Both paths use the same stable development signing identity.
- `/Applications/Murmur.app` passes `codesign --verify --deep --strict`.
- Replaced the stale ad-hoc Accessibility entry with the installed, development-signed
  app through System Settings. Murmur recognizes access and the saved requirement
  matches the current app after rebuilding. An older microphone permission also
  failed its code requirement; it was reset and the current app's consent completed.
  First-use microphone handling brings the app forward and labels the permission wait.
- 26 core tests and 11 app checks pass, plus the previously accepted Apple single-phrase and continuous
  integration checks. The previously accepted three optional engine checks remain valid;
  those engines were unchanged.
  Core checks cover stale identity/revisions, text preservation, bounded queues,
  endpoints, particle bounds/response/reduced motion, recovery across attempts,
  cancellation while previous preparation cleans up, shortcut conflicts/repeat/rollback,
  clipboard ownership, safe destination
  rules, insertion spacing, rolling audio windows, preferences and meter response.
- Native appearance picker shows all four choices; Particle Wave selected and
  visually compared with Chris's reference. It uses a deterministic teal particle
  field driven by input, with no timer running for idle redraw.
- Both real audio callback factories are invoked on a worker with synthetic PCM buffers.
  The dictation tap converts 48 kHz audio into queued 16 kHz packets off the UI actor.
- Apple recognizes the generated sentence containing “local dictation” and
  “quick brown fox,” with partials, finals and a detected pause.
- Native microphone dictation recognized the same sentence and inserted its words
  into the scratch TextEdit document, without pressing Enter. Quick Talk stopped
  capture automatically. The live check exposed sentence spacing and moving
  provisional timestamp issues; both now have regression coverage.
- Apple's optional VAD module rejected quiet live audio between phrases. A regression
  with 160-sample packets, a ten-second quiet background gap and repeated finalization
  reproduced `RecogRejected`. Removing that gate makes the regression pass, preserving
  both utterances and supporting a fresh session. Pause timing still uses input energy
  after recognition confirms speech.
- The final packaged app captures two spoken passages across a ten-second quiet
  gap in Keep Talking. Both remain in the completed transcript after Finish returns
  capture to Mic off. The physical speaker/microphone check exposed repeated Apple
  punctuation after pause finalization; the tracker now removes only a repeated
  sentence-ending mark, preserving words, distinct punctuation and ellipses.
  The regression fails before the change and passes afterward.
- Correct sentence spacing and the punctuation correction are visible in the final
  native transcript. A repeated automated start-from-bar typing attempt activates
  Murmur instead of preserving the TextEdit destination, so it correctly keeps the
  transcript available for copying. Earlier actual TextEdit insertion remains the
  direct-typing evidence; the tool's per-app input is not a physical shortcut check.
- Restored the original speaker mute setting after acoustic validation, retaining
  MacBook Pro Speakers and the original 31.25% output volume.
- Chris reported that dictation into the Codex composer displayed Inserted but left
  the field empty. The old output path trusted AX write acceptance and a posted paste
  event without observing their effect. Regression checks reproduce both false successes.
  Output now confirms the expected field text, uses normal keyboard paste for web
  editors, keeps the clipboard available through readback, and refuses a duplicate
  retry when the field changes unexpectedly. Unreadable destinations report Paste sent,
  and recognized words without a delivery receipt report Transcript ready.
- Eight insertion checks cover accepted no-op writes, verified native insertion without
  double paste, web-editor selection with Unicode, no-op paste, unexpected edits,
  focus changes, unreadable fields and recognition without any delivery. No microphone
  or external app is used by these regression checks.
- Selecting the built-in microphone no longer resets an already-default audio graph.
  The original System default microphone preference was restored after validation.
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

The fixture and live speaker test use generated speech, not human dictation.
TextEdit insertion is established; browser, editor, terminal and chat-app insertion
still need native checks. Apple's optional VAD gate can discard audio and its result
stream currently supports error handling only. Murmur uses the transcriber without
that gate. See [Apple's module documentation](https://developer.apple.com/documentation/speech/speechdetector).

## Remaining qualification

- Confirm the updated paste path in the Codex composer. The computer-use tool
  explicitly refuses the Codex app for safety reasons; this field cannot be
  directly exercised by the agent. No successful post-fix Codex insertion is claimed.
- Verify physical global shortcut presses and clipboard-paste fallback in other
  destination apps. The automation's per-app key delivery doesn't establish global
  Carbon dispatch. Registration, recorder, conflict and rollback checks are established.
- Hands-on human dictation, interruption/reconnect, sleep/wake, multi-display,
  full-screen Spaces and very long Keep Talking sessions.
- Optional download cancellation and deletion/re-download.
- Optional vocabulary/cleanup and opt-in disk history from the longer product plan.
- Developer ID signing, notarization, clean install/DMG, model licensing review and
  the release acceptance matrix before public distribution. Repo stays private.

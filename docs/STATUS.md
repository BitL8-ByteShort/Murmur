# Murmur status

Updated October 4, 2026.

## Checkpoint

Local dictation development app installed at `/Applications/Murmur.app`. Public
release qualification remains separate from this working local app.

| Area | Current state |
| --- | --- |
| Repository | BitL8-ByteShort/Murmur, verified PRIVATE; microphone fix on jorvek/input-only-microphones, based on jorvek/murmur-app |
| Native app | SwiftUI settings, menu bar, custom icon, signed local .app installed in Applications |
| Visuals | Four styles in a compact 200 × 56-point floating bar: Waveform, Aura, Aura Ring and teal Particle Wave; no Aura blur; native input callback, meter capped at 60 Hz, 16 ms interpolation |
| Appearance | Automatic hiding after completion/failure; Always on or manual show retains a 100 × 28-point idle pill with the mic off; response strength, still/reduced motion, display selection, bottom offset |
| Crash repair | Original microphone callback moved outside MainActor; preview and dictation callback worker regressions pass |
| Capture | Input-only AUHAL shared by dictation and preview; selected mic is independent of system defaults/output. Installed 0.2.1 (3): built-in and USB live input work with AirPods connected |
| Recognition | Apple Speech, Parakeet, Moonshine and Whisper Turbo integrated; local fixture checks described below |
| Pauses | Quick Talk shortcut is hold-to-talk: release starts finishing, captures a 120 ms ending buffer, then drains audio before recognition finalization; button/menu starts retain pause completion; Keep Talking retains utterance flush |
| Downloads | Explicit progress/cancel, selection separate, model receipts, recoverable deletion to Trash |
| Shortcuts | Three global defaults, editable recorder, repeat suppression, transactional rollback; native end-to-end checks pending |
| Insertion | Native TextEdit insertion established; Chris confirms updated paste reaches the Codex composer, although Murmur's exact readback did not confirm it and retained the words for recovery |
| TigerVNC | Remote Control–V default, Control–Shift–V or Command–V selectable; focus refresh triggers Mac clipboard announcement, clipboard-read acknowledgement replaces fixed waits; destination shown in transcript; actual remote dictation retry pending |
| Privacy | No saved raw audio, no disk transcript history, no analytics/cloud fallback; current and previous attempts recoverable in memory |
| Distribution | Apple Development signature verified locally; no Developer ID/notarization/public installer |

## Accepted evidence

- Microphone isolation regression reproduced before the fix: capture only bound
  the device without disabling output, and preview ignored the selected mic.
  Both paths now enable input bus 1, disable output bus 0, then bind the selected
  device before initialization. No system defaults or hardware formats are set.
  Only the selected input's alive/rate/channel state can interrupt capture.
- The full `swift test` suite passes; three optional model/file checks remain
  skipped by default. New hardware-free checks cover output-disable ordering and
  failure, explicit selection over an AirPods default, missing-device refusal,
  selected-input dictation/preview, EOF drain, stale callbacks and cancellation
  during a pending permission request. These tests never open a microphone.
- Installed 0.2.1 (3), signed with the existing development identity and verified
  with exactly one running app. Native live preview received nonzero input from
  both MacBook Pro Microphone and Brio 100 USB. Before, during and after capture,
  AirPods remained alive as default input (24 kHz) and output (48 kHz); all observed
  device rates and defaults were unchanged. This establishes coexistence and live
  capture, not an audible playback-continuity test or human dictation accuracy.
- Parakeet remained selected. A native Keep Talking session with the built-in
  mic reached listening and finished cleanly with No speech detected. Copy only
  was temporarily enabled to prevent insertion into another app, then restored
  off. Final settings show MacBook Pro Microphone and Mic off; shortcut, model,
  pause, inactivity, visual and TigerVNC preferences were preserved.
- Build and launch scripts succeed. Switching from the installed app to Codex Run,
  then back to installation, leaves exactly one instance across both known bundles.
  Both paths use the same stable development signing identity.
- The updated installed settings show hold/release instructions and Mic off.
  Control–Option–Space remains the Quick Talk binding, with the user's 0.8-second
  button pause, one-minute Keep Talking timeout and Control–V remote selection
  preserved. The application is left on Dictation for the next human retry.
- `/Applications/Murmur.app` passes `codesign --verify --deep --strict`.
- Settings sidebar buttons accept clicks across the whole padded row, including
  blank space beside the labels. The same blank-space click failed before the fix
  and selected Appearance afterward. All five tabs were checked in the installed app.
- Replaced the stale ad-hoc Accessibility entry with the installed, development-signed
  app through System Settings. Murmur recognizes access and the saved requirement
  matches the current app after rebuilding. An older microphone permission also
  failed its code requirement; it was reset and the current app's consent completed.
  First-use microphone handling brings the app forward and labels the permission wait.
- 31 core tests and 23 ordinary app checks pass, plus the previously accepted Apple single-phrase and continuous
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
- All four compact floating styles were inspected in the installed app with live
  microphone input. Waveform spacing and ring motion scale to the smaller bounds.
  Stopping an unpinned preview hides it; Always on collapses it to the idle pill.
  Manual show/close also works with the microphone off. Particle Wave and Always on
  disabled were restored afterward. The terminal-state visibility regression fails
  for success/failure before the policy fix and passes afterward.
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
- TigerVNC inspection exposed a connected desktop window without an editable AX
  field. Remote capture now applies only to TigerVNC's actual desktop window,
  preserving the app, window identity and title through delivery. Local viewer
  dialogs and other applications do not receive the remote shortcut. The original
  750 ms clipboard delay and further two-second delivery window did not fix Chris's
  remote paste. Inspection of the installed TigerVNC binary and FLTK source shows
  that the Mac viewer checks external clipboard changes on application activation.
  The new handoff briefly returns focus through Murmur to the same viewer window,
  revalidates it, sends paste once and waits only for a clipboard data request.
  Focus changes stop delivery; a missing request reports a clipboard-sharing error.
  Clipboard consumption does not confirm remote insertion. Remote readback is unavailable,
  so output reports Paste sent rather than Inserted. Remote fields/passwords cannot
  be inspected and multiline text remains for copying.
- Three remote-event checks reproduce the old Command–V-only behavior and verify
  Control/Shift/Command press/release sequences, TigerVNC's macOS left-device flags,
  absence of Enter and unchanged ordinary local paste. Three core checks cover
  viewer-window recognition and remote preference migration/round-trip. The installed
  Dictation picker exposes all three choices with Control–V selected and Mic off.
- A held Quick Talk shortcut ignores speech pauses and buffers finalized words
  until release. Release keeps a 120 ms capture tail; recording and conversion
  then drain before backend finalization and output, with one
  insertion containing every finalized utterance. Keep Talking still inserts
  each finalized utterance while listening. Coordinator checks use a simulated
  capture source and backend, without opening the microphone or another app.
  Releasing during preparation cancels startup; repeat and unmatched-release
  suppression remain in the shortcut gate. Physical shortcut dispatch still needs
  a human check. Recognition computation can still take time after release.
- Chris's human release immediately after “Smooth operator” produced “smooth oper”;
  the installed transcript confirmed that truncation with Parakeet selected.
  The previous release removed the tap without allowing its last buffered callback.
  A simulated final callback reproduces the truncated ending before the fix and
  preserves the full ending after graceful capture finish. Cancellation during
  the tail stops capture and prevents output. Cancel/Close/Quit have no tail delay.
  The real 48 kHz → 16 kHz converter also retained 240 samples (15 ms) at shutdown;
  EOF draining now returns all 1600 samples from a 4800-frame input and rejects late
  callbacks. Conversion/drain stays on workers, with the stream closed only afterward.
  An opt-in generated “Smooth operator” check passes through the actual capture
  converter and installed Parakeet model, trimming long trailing silence to the
  120 ms ending buffer. This qualifies the PCM/model path; a human shortcut retry
  still establishes physical microphone timing.
- Clipboard regression checks cover refresh-before-paste ordering, focus changes,
  bounded timeout without another paste, lazy UTF-8/Unicode clipboard consumption,
  and immediate completion for unreadable editors. Local unreadable editors keep
  their clipboard lease briefly in the background without delaying completion;
  ownership checks preserve any newer user copy. The captured destination appears
  beneath Transcript to distinguish local insertion from the TigerVNC route.
- Chris's next human dictation reached the Codex composer. Murmur still could not
  confirm the exact resulting text and reported Dictation stopped. That terminal
  state had incorrectly kept the overlay expanded; it now hides automatically,
  or collapses to the idle pill when Always on is enabled. Readback compatibility
  with this composer remains a separate limitation.
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
TextEdit insertion is established and Chris confirms typing into the Codex composer;
other browser, editor, terminal and chat-app insertion still needs native checks.
Apple's optional VAD gate can discard audio and its result
stream currently supports error handling only. Murmur uses the transcriber without
that gate. See [Apple's module documentation](https://developer.apple.com/documentation/speech/speechdetector).

## Remaining qualification

- Retry human dictation into the connected TigerVNC Linux desktop. Code/event and
  settings checks do not establish remote clipboard synchronization or actual paste.
  The native control tool exposes the viewer window but its input actions do not
  reliably drive the remote desktop. No remote helper was installed. Keep
  clipboard sharing enabled in TigerVNC; the new destination label identifies
  whether Murmur captured the viewer or a local app.
- Improve exact insertion readback compatibility with the Codex composer. Chris
  confirms that the updated paste reaches the field. The computer-use tool
  explicitly refuses the Codex app for safety reasons; this field cannot be
  directly exercised by the agent.
- Verify physical global shortcut presses and clipboard-paste fallback in other
  destination apps. The automation's per-app key delivery doesn't establish global
  Carbon dispatch. Registration, recorder, conflict and rollback checks are established.
- Hands-on human dictation, interruption/reconnect, sleep/wake, multi-display,
  full-screen Spaces and very long Keep Talking sessions.
- Optional download cancellation and deletion/re-download.
- Optional vocabulary/cleanup and opt-in disk history from the longer product plan.
- Developer ID signing, notarization, clean install/DMG, model licensing review and
  the release acceptance matrix before public distribution. Repo stays private.

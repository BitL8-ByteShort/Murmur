# Murmur product and technical design

Date: September 30, 2026. Status: initial design for Chris's new project.

## What we're building

Murmur is a native Mac dictation app. Put the cursor in another app, use a shortcut,
speak, and get text there. The app stays out of the way, with a small rounded bar
at the bottom center of the active screen. Chris selected direct dictation as the
first-version focus and chose the name Murmur.

The visualizer must respond to actual microphone input. Here, “voice synth” means
a voice visualization, not generated speech. There are four appearances: Waveform,
Aura, Aura Ring, and Particle Wave. The ring is a donut with multiple colorful
responding rings. Particle Wave follows Chris's teal flowing particle reference.
Each appearance shares the same controls and microphone status.

This request covers a repository scaffold and a solid implementation plan. The
initial scaffold offers native appearance previews and optional real microphone
monitoring. It does not pretend to transcribe, paste, download models, or register
dictation shortcuts. Those are implementation milestones below.

## Platform and approach

- macOS 26 or later; Apple Silicon for the first release.
- Swift 6, SwiftUI for settings and drawing; AppKit for a nonactivating NSPanel.
- Local recognition; no cloud speech or cloud rewriting in version one.
- Apple Speech is the initial default; optional speech models are explicit downloads.
- No account, background recording at launch, raw audio retention, or telemetry by default.
- Model files live outside the repository under Application Support/Murmur/Models.
- Direct distribution first. Signing, notarization, entitlements, and updater work
  are release tasks, not properties implied by a successful local build.

Approaches considered: (1) native Swift with Apple Speech and optional local engines,
(2) a web desktop shell around a recognition worker, (3) a fork of an existing app.
Use (1): it matches Teleprompter, avoids extra rendering/runtime overhead, and gives
us precise control over focus and the floating panel. A fork imports unrelated
features and licensing decisions. A web shell makes focus and permissions harder.

## Everyday interaction

| Action | Behavior | Suggested default |
| --- | --- | --- |
| Quick Talk | Press to start. Stop after 1.2 seconds of detected silence following speech, or press again to finish. | Control + Option + Space |
| Keep Talking | Press to start an ongoing session. Finalize and insert sentences after pauses; remain listening until pressed again or Stop is clicked. | Control + Option + D |
| Show / hide bar | Open or close the bar manually. Closing while listening stops capture and cancels uncommitted audio. | Control + Option + B |
| Cancel | Escape cancels current uncommitted utterance while capture is active. | Escape, scoped to capture |

All three primary shortcuts are changeable with a shortcut recorder. Detect
duplicate assignments, system conflicts, and registration failures before saving.
Bare letter keys are rejected. Modifier-only and Fn bindings are later work.
An optional hold-to-talk behavior for Quick Talk comes after the initial toggle
path and must handle key-up, repeat suppression, and focus changes.

Quick Talk does not end before the user has spoken. Show “No speech detected” and
stop after 15 seconds without speech. Silence end detection uses VAD/backend EOU,
not the animation's RMS threshold. Keep Talking stays armed across pauses, but an
optional inactivity limit can stop it; the default is 5 minutes, with Off available.

Pinned visibility and microphone capture are independent. “Keep bar visible” leaves
an idle capsule after a session. It never leaves the mic on. Manually opening a bar
shows idle controls without recording. After an unpinned session completes, hold
the success state for 650 ms, then hide. Errors remain visible until dismissed.
Escape/Close discard only uncommitted audio; text already inserted is not undone.

## Appearance

Dark graphite floating surface, subtle material, thin border, restrained shadows,
rounded corners, and mint/blue/lilac/peach accents. Use system typography and a calm
settings window with a sidebar. Avoid a large dashboard in the everyday flow.

| Style | Idle | Listening |
| --- | --- | --- |
| Waveform | 112 × 32 pt capsule | 360 × 80 pt capsule with live bars, status, stop, and close |
| Aura | Same idle capsule | 320 × 168 pt area with crisp responding color fields above the controls |
| Aura Ring | Same idle capsule | 228 × 244 pt area with three colorful responding rings and controls |
| Particle Wave | Same idle capsule | 480 × 180 pt area with a crisp teal particle cloud and controls |

Dimensions are starting values and clamp to the visible screen. Expansion keeps
the panel bottom center fixed, 18 pt above the Dock-safe visible-frame edge.
Default screen is the screen containing the pointer when activated. Add explicit
display selection and offset settings. Follow screen changes without jumping into
the user's text focus. Full-screen and Spaces behavior needs real-app verification.
Transparent outer areas pass clicks through; only visible controls accept clicks.

All forms use bounded microphone energy data. Waveform uses time-domain amplitude
bins; ring motion may use smoothed energy and frequency bands when available.
Do not fabricate motion in a live session. Design preview uses a labeled static
sample. Chris requested sharper Aura edges and faster response after trying the
scaffold. Use a 512-frame tap, up to 60 Hz publication, 16 ms visual interpolation,
and no Aura blur. Particle Wave uses deterministic particles with input-driven
folding and no idle animation timer. Honor Reduce Motion and
Reduce Transparency, and add a still visualizer option. Color alone must not convey
listening, preparing, paused, insertion failure, or permission denial.

## Settings worth shipping

- Input: system default or a specific microphone, meter, test input, language.
- Speech: engine, installed models, disk use, download progress, cancel/retry/delete,
  loading progress or honest indeterminate state, warm-model memory policy.
- Dictation: Quick Talk silence interval (0.7–3 seconds), Keep Talking inactivity,
  raw or basic cleanup, automatic punctuation where supported, custom vocabulary.
- Shortcuts: record/reset bindings and explain conflicts in place.
- Appearance: Waveform/Aura/Aura Ring/Particle Wave, pinned bar, display, offset, reduced motion,
  intensity, light/dark/system theme, optional start/stop sounds.
- Output: normal insertion, copy-only mode, clipboard restoration, manual retry.
- Privacy: history off by default; optional 1/7/30-day local text retention,
  clear/export history, microphone/accessibility/system speech asset status.
- General: launch at login off by default, menu bar presence, version/license info.

The scaffold exposes appearance/pinning/reduced motion persistence, live mic
monitoring on explicit user action, and truthful previews of planned settings.
Controls must not look operational when the feature is still planned.

## Speech pipeline and Teleprompter lessons

Capture → bounded serial audio queue → resampling → VAD → speech backend →
partial/final segment assembler → optional deterministic cleanup → insertion.
Visualizer frames branch off capture; drawing never blocks recognition.

Teleprompter's current source is the reuse reference, not an implicit dependency.
Review `App/SpeechService.swift`, `Speech/VoiceBackend.swift`,
`Speech/VoiceModelStore.swift`, engine adapters, `Core/VoiceAudioWindow.swift`,
`App/HotkeyManager.swift`, and `App/OverlayController.swift`.

- Downloading does not switch selection. “Downloaded” is separate from “Prepared”.
- Prepare with visible status/cancellation; begin capture only when the backend is ready.
- Keep the selected engine warm between sessions, release on engine change or explicit
  unload, and expose a memory-saving idle unload policy. Never keep the mic warm.
- Partials replace earlier text for the same segment. Finals are ordered and inserted
  at most once. Whisper overlap must not duplicate earlier committed text.
- Cancel/switch gives a new session ID; ignore late callbacks from previous sessions.
- Bound audio to 30 seconds (480,000 mono samples at 16 kHz) of pending worker input;
  overflow stops with a recoverable error instead of silently dropping speech.
- RMS is useful for visual feedback, but not sufficient to decide that speech ended.
- Teleprompter's observed Whisper preparation took about 51 seconds on one M5 Pro.
  This is historical evidence, not a startup prediction for Murmur or other Macs.
- Remove script matching/re-anchoring assumptions. Dictation must preserve everything
  said, not only words near a prepared script.

### Engines and assets

| Engine | Role | Validation required |
| --- | --- | --- |
| Apple Speech | Default, local SpeechAnalyzer/SpeechTranscriber on macOS 26 | Check supported locale, asset install state, availability, local-only behavior |
| Parakeet Realtime EOU | Optional English streaming candidate via FluidAudio | Compare realtime and TDT quality/latency on dictation fixtures; no inferred language coverage |
| Moonshine Small Streaming | Optional lightweight English candidate | Memory, cold/warm start, continuous utterance boundaries |
| Whisper via WhisperKit | Optional broad-language candidate | Actual supported locales, startup, overlap deduplication, silence hallucinations |

Start Apple end-to-end, then add Parakeet, then evaluate Moonshine and Whisper.
Do not ship all engines just because Teleprompter has them. Pin versions only after
API and license review. Teleprompter's exact versions are a starting reference,
not a claim that they are the latest. Model downloads require source revision,
file manifest, integrity checks where available, free-space check, staging,
atomic readiness receipt, cancellation, and separate explicit selection. Never
call an SDK convenience API that silently downloads or selects assets.

## Text insertion is a first-class subsystem

Capture the target process and focused editable element before showing the panel.
Do not activate the settings app to dictate. At finalization, confirm the process
and element are still the intended target. If focus changed, keep the transcript
in a temporary recovery card and ask the user to choose where to paste it.

Use a tested Accessibility insertion path when an editable element supports it.
Preserve caret and selection; reject password/secure fields. Unsupported controls
use a paste fallback only after verifying the target and permissions. Preserve
all clipboard item types, then restore only if the clipboard still belongs to
Murmur's operation (change count + operation token). Never overwrite clipboard
content the user copied meanwhile. A universal paste-consumption acknowledgement
doesn't exist: validate conservative timing per host app and retain recoverable
text. No automatic retry, Return key, form submit, send, or shell execution.

In Keep Talking, pin the initial target for the session. If it changes, pause
insertion and display “Target changed”; do not scatter later words into other apps.
Independent utterance IDs prevent double insertion. Recoverable text is in memory
unless the user explicitly enables history. Copy-only mode works without
Accessibility permission.

## Lifecycle and persistence

Lifecycle: idle → preparing → listening → finalizing → inserting → success → idle.
Keep Talking returns to listening after an inserted utterance. Failures preserve
text if any, stop the mic, and show error. Cancel aborts work and never inserts.
Sleep, quit, microphone disconnect, or model switch stops capture and invalidates
callbacks. Screen changes only change panel placement.

Preferences use a versioned Codable schema with migration and safe defaults.
Persist appearance, engine ID, microphone UID, locale, bindings and explicit privacy
choices. Capture state is transient and always starts idle after launch.

## Milestones and acceptance

1. **Scaffold, this request:** buildable app bundle, appearance preview, optional real
   mic visualizer, tests for lifecycle/pinning/level bounds, docs and local Git repo.
2. **Apple vertical slice:** real transcription, Quick Talk and Keep Talking, editable
   global shortcuts, permission onboarding and recovery, insertion into TextEdit and
   a browser field without focus theft or clipboard loss.
3. **Local model manager:** Parakeet download/load/select/unload, download integrity and
   failure tests; offline transcription proof with network disconnected.
4. **Polish and optional engines:** full appearance/display settings, vocabulary/basic
   cleanup, history opt-in, Whisper/Moonshine only after quality comparison.
5. **Release:** signed/notarized build, clean-Mac install, real-app matrix, privacy and
   dependency/model notices, performance checks on a 16 GB Mac and lower-memory Mac.

Latency targets, to measure rather than advertise: warm activation under 300 ms,
visual feedback under 100 ms, first partial under 800 ms, final insertion under
1.5 seconds after endpoint. Measure p50/p95 and memory on named hardware; long cold
loads must show status and remain cancellable. Acceptance includes silence, noise,
mixed punctuation, names, repeated words, long dictation, hotkey repeats, permissions
revoked, app switching, sleep/wake, and microphone unplug. No device/provider/release
readiness is established by core tests alone.

## Decisions still open

Murmur is Chris's selected name; domain/trademark/store availability isn't checked.
Whether to broaden the OS floor or support Intel is a later scope decision. No
public license, pricing, or cloud-provider choice is assumed. Chris requested a
private GitHub repo; keep it private until he explicitly approves making it public.

## Research checked September 30, 2026

- [MacParakeet source and product overview](https://github.com/moona3k/macparakeet):
  reference for shortcut-driven dictation and deterministic vocabulary cleanup.
- [Wispr Flow](https://wisprflow.ai/): reference for direct dictation and dictionary UX.
- [FluidAudio](https://github.com/FluidInference/FluidAudio): reference for native
  streaming recognition and local voice activity detection. Review model licenses
  separately from the SDK license.
- [Apple SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber).

Use product references for behavior inspiration. We haven't copied their code,
benchmarks, branding, or claims into Murmur.

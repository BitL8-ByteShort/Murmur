# Architecture

## Current app

```text
MurmurApp
  ├── SettingsView → AppModel → persisted Preferences
  ├── DictationCoordinator → CaptureService → InputOnlyCapture → CaptureBridge
  │                          ↓
  │                     AudioInbox → SerializedSpeechBackend → TranscriptAssembler
  │                                                               ↓
  │                                               TextInsertionService / recovery
  ├── MicrophoneMonitor → InputOnlyCapture → AudioMeter → VoiceVisualizer
  └── OverlayController → nonactivating VoicePanel → OverlayView
```

Speech adapters implement Apple, Parakeet, Moonshine and Whisper locally. A session
UUID rejects old callbacks, and utterance identity prevents duplicate insertion.
Keep Talking retains the initial target. Input or target failures keep recoverable
text rather than redirecting it. Settings can activate normally; the floating bar
must never become the text destination. Model downloads are explicit and do not
select an engine or open a microphone.

## Selected microphone capture

`CaptureService` and `MicrophoneMonitor` resolve the saved microphone UID before
creating a shared `InputOnlyCapture` implementation. An explicit unavailable UID
fails rather than using the default microphone. System default is resolved once
at session start.

The AUHAL unit enables input bus 1 and disables output bus 0 before binding the
selected device. It negotiates client-side float PCM at the hardware's existing
sample rate; it never sets the system default, hardware format/rate or an output
device. The HAL callback renders into a preallocated buffer outside MainActor.
CaptureBridge retains its bounded conversion/queue and end-of-stream drain.
Stopping joins callbacks before releasing their context and audio unit.

Device listeners observe only the selected input's alive, sample-rate and channel
state. Playback changes cannot terminate an otherwise healthy built-in/USB input.
Changing the saved input stops current capture and retains recoverable text; the
next session opens the newly selected device. A Bluetooth mic's own profile
behavior remains controlled by macOS.

## Reuse from Teleprompter

The local reference is `/Users/chris/Projects/Teleprompter`.

| Existing source | Keep the lesson | Change for Murmur |
| --- | --- | --- |
| `App/SpeechService.swift` | Capture, conversion, cancellation | Emit free dictation, remove script matching |
| `Speech/VoiceBackend.swift` | Actor-owned prepare/accept/finish/stop | Add session and utterance identity and explicit capability metadata |
| `Speech/VoiceModelStore.swift` | Opt-in download, receipt, separate selection | Add staging, integrity manifest, cancellation and disk-space behavior |
| `Speech/ParakeetBackend.swift` | Local streaming callbacks | Verify cumulative/final semantics for inserting once |
| `Core/VoiceAudioWindow.swift` | Bounded windows, overlap management | Use VAD/EOU; prove no duplicated final text |
| `App/HotkeyManager.swift` | Global registration and duplicate detection | Add Quick Talk/Keep Talking and transactional rebinding |
| `App/OverlayController.swift` | Nonactivating panel | Bottom-center active display, style expansion, click-through verification |

No source files were copied from Teleprompter into this app. Its current
first-party license is proprietary; check ownership and distribution intent before
porting code or importing third-party notices. Speech-model licenses are separate
from framework licenses. No open-source license has been assigned to Murmur.

## Version and compatibility decisions

The first release floor is macOS 26 with Apple Silicon so we can reuse the native
SpeechAnalyzer approach. An older-macOS fallback would be a separate engine and
compatibility task. SDK packages are pinned in Package.resolved. Model weights are separate explicit
downloads and are never bundled into the installer.

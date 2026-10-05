# Development

Read README.md and STATUS.md before the design and implementation plan.

## Build and install

Run `./script/build_and_run.sh --verify` (the Codex Run action uses the same script)
to build and open `build/Murmur.app`. Both launch paths quit the previous app at
either known bundle path and verify a single instance across those paths.
Run `./scripts/install-local.sh` to update `/Applications/Murmur.app` with Chris's
existing Apple Development certificate. The installer quits both exact Murmur
bundle paths before updating. Microphone capture starts off after relaunch.

Development bundle ID: `com.saltypanda.murmur.dev`. Build-only defaults to an
ad-hoc signature; set `MURMUR_SIGN_IDENTITY` for stable certificate signing.
The installed development app isn't Developer ID signed or notarized.

The pinned packages are FluidAudio 0.17.4, Moonshine 0.1.5 and Argmax 1.1.0.
The app build copies SwiftPM resource bundles and bundled license documents.
Model weights stay outside Git under Application Support/Murmur/Models.

## Checks

`swift test` runs pure core tests and worker-callback checks. It doesn't ask for
permissions, open a microphone or download models. Optional checks are explicit:

```sh
say -o build/dictation-fixture.wav --data-format=LEF32@16000 \
  'Hello Chris. This is a local dictation test. The quick brown fox jumps over the lazy dog.'
MURMUR_FIXTURE_PATH="$PWD/build/dictation-fixture.wav" swift test
MURMUR_FIXTURE_PATH="$PWD/build/dictation-fixture.wav" MURMUR_MODEL_ENGINE=parakeet \
  swift test --filter downloadedBackendSupportsTwoContinuousUtterancesAndWarmRestart
```

`MURMUR_MODEL_ENGINE` also accepts `moonshine` or `whisper`. Models must already be
installed. These checks feed real PCM through the actual engine, finalize two
utterances, and prepare a fresh warm session. Generated speech proves the backend
path, not recognition of a human through the physical microphone.

To check word endings through capture conversion and the installed Parakeet model:

```sh
say -o build/release-ending-fixture.wav --data-format=LEF32@48000 'Smooth operator.'
MURMUR_ENDING_FIXTURE="$PWD/build/release-ending-fixture.wav" \
  swift test --filter parakeetRecognizesCompleteEndingAfterCaptureDrain
```

This check trims the file's long trailing silence to 120 ms after the last sound.
It exercises real conversion and recognition without opening a microphone.

## Hands-on qualification

1. Fresh launch: microphone off, with pin independent of capture.
2. Appearance: compare all four styles with live input and response strength.
3. Install Apple language assets or select an explicitly downloaded local model.
4. Quick Talk: hold the shortcut, speak through a pause, release at the last word and verify the short 120 ms ending buffer preserves it, all finalized words are inserted once and the bar hides. Cancel/Close must stop immediately. Separately check button-started pause completion.
5. Keep Talking: several thoughts, no duplicates or missing speech, finish manually.
6. Enable Accessibility yourself. Focus a text field in another app, use the
   shortcut, verify focus and insertion at the caret. No Enter/send action.
7. Check TextEdit, browser, editor and chat drafts. Check rich clipboard restoration,
   a new user copy during paste, secure-field refusal, target changes, and terminal
   multiline refusal. Text remains recoverable when insertion stops.
8. Record a conflicting shortcut: retain the previous working binding. Escape cancels.
9. Input removal/change and sleep stop capture with retained text; reconnect requires a new start.
10. Pin/show/close, multiple displays, full-screen Spaces, long sessions and model
    download cancellation/delete/re-download remain real environment checks.

Use the status document as the evidence authority. Do not count a static visual
sample, fixture, pure test or local signature as proof of a public release.

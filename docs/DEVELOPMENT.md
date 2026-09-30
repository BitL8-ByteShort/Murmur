# Development

Start with README.md, STATUS.md, then the design and implementation plan.

## Local build

Run `./script/build_and_run.sh` (also wired to Codex's Run action). The app is built under `build/Murmur.app`.
The build script uses an ad-hoc development signature and a development bundle ID,
`com.saltypanda.murmur.dev`. Rebuilding while the app is open doesn't update the
running process. The run script quits only this project's app bundle before rebuilding.
For build-only checks, use `./scripts/build-app.sh`.

Run `swift test` for the core checks. Keep speech integration tests separate from
pure core tests so they don't silently download assets or request permissions.

## Preview checklist

1. Launch: settings opens, microphone is off, no permission prompt.
2. Appearance: switch Waveform, Aura, Aura Ring. Check the ring has an empty center.
3. Show voice bar: idle capsule appears above the Dock without changing the front app.
4. Try live microphone: macOS asks once; the selected appearance reacts to actual input.
5. Stop: input ends and the bar contracts. Close: input ends and the bar disappears.
6. Pin: leave the idle bar open; relaunch and confirm the microphone stays off.
7. Deny permission: see a useful message and keep the design preview usable.
8. Disconnect microphone while monitoring: stop with a clear interruption message.
9. Menu bar: reopen settings, show/close bar, stop monitoring, quit.

Use a real microphone only after choosing the live preview. Don't accept a static
design sample or a fixture as evidence of live capture. Keep permission decisions
with the person using the Mac.

## Work sequence

Implement the plan one milestone at a time. First establish speech and insertion
with Apple; next add model downloads. Leave public release work until the full
acceptance matrix passes. Keep docs/STATUS.md honest about what was checked in a
real app and what was only checked with a test double.

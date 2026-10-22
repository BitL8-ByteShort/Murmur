# Contributing to Murmur

Bug reports, fixes, documentation, artwork and focused feature contributions
are welcome. Murmur is open source under [GPL-3.0-only](LICENSE). You can fork
the repository and submit a pull request without write access to the main repo.

## Report a bug

Check [existing issues](https://github.com/BitL8-ByteShort/Murmur/issues), then use
the [bug-report form](https://github.com/BitL8-ByteShort/Murmur/issues/new?template=bug_report.yml).
Include the app version/build, Mac model, macOS version, selected microphone and
speech engine, reproduction steps, expected behavior and what happened. Remove
private dictated text and credentials from reports and screenshots.

## Submit a change

1. For a substantial change, open an issue to discuss the problem and intended
   behavior. Small fixes and documentation improvements can go straight to a PR.
2. Fork the repo and create a focused branch from `main`.
3. Keep Quick Talk, Keep Talking and bar visibility separate. Preserve local
   recognition, explicit model downloads, target-field safety and no automatic
   Enter/send. Keep audio work off the main actor and queues bounded.
4. Add a regression check when it proves a meaningful behavior. Run checks
   appropriate to the change and explain what was tested and any remaining limits.
5. Open a pull request describing the problem, resulting behavior and any new
   dependencies or third-party material. The owner reviews changes before merge.

New contributions are submitted under GPL-3.0-only unless separately identified
material is explicitly disclosed and accepted under compatible terms. You retain
your copyright. Submit only work you have the right to contribute; obtain any
required employer authorization. No separate CLA, copyright assignment or legal
name acceptance comment is required. See [CLA.md](CLA.md) for historical context.
Do not submit signing keys, credentials, private transcripts or model weights.

## Development checks

See [Development](docs/DEVELOPMENT.md) for setup and optional speech fixtures.

```sh
swift test
MURMUR_SIGN_IDENTITY=- ./script/build_and_run.sh --verify
```

Documentation-only edits do not need an app rebuild. New Swift files require
regenerating the Xcode project with `python3 script/generate_project.py`.

## Maintainer checks

Review scope, implementation and relevant validation. Confirm contribution
rights and compatibility of new third-party material; preserve its notices.
Keep source and build instructions available with binary releases as described
in [SOURCE.md](SOURCE.md). Signing, notarization and installation checks are
required for each new public installer; test results alone do not prove live
microphone or insertion behavior.

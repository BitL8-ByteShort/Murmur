# Murmur

Read README.md and docs/STATUS.md before changing code. The product design and
implementation plan are linked from the README. This is a native dictation development app. Keep local proof and public-release
qualification distinct in the app and docs.

- Preserve Quick Talk, Keep Talking, and pinned visibility as separate behaviors.
- No microphone capture at launch. A pinned bar does not mean an active mic.
- Keep focus in the user's target app; use a nonactivating floating panel.
- Local speech by default. Model downloads and model selection are separate actions.
- Do not add silent network fallbacks, raw audio retention, automatic Enter/send,
  or cloud rewriting without a specific product decision.
- Keep audio work off the main actor and bound pending samples.
- Never copy Teleprompter's script matching into dictation.
- Build with scripts/build-app.sh and run focused core tests with swift test.
- Build/test proof does not establish live insertion, model, signing, or release readiness.
- Use one agent by default. Do not delegate unless Chris asks.
- Keep the GitHub repository private until Chris explicitly approves making it public.
- For writing on Chris's behalf, use chris-voice and read its voice profile first.
  Ordinary technical answers and code changes don't require that workflow.

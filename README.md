# Subtext

A native SwiftUI interview recorder and review workspace for iPhone. Start recording without naming an interview or identifying speakers. The original audio stays local; titles, transcripts, speaker names, and editorial notes can be added afterward.

## Run

1. Open `Subtext.xcodeproj` in Xcode. The shared scheme is **Subtext**.
2. Select an iPhone simulator, or connect an iPhone and select your development team under **Signing & Capabilities**.
3. Run and choose **Allow AI analysis** or **Use Apple transcription only** in Subtext’s first-launch permission screen. Tap **Record** and grant microphone access. **Finish** saves audio and starts Apple on-device transcription by default. With AI permission enabled, new recordings then receive cloud audio analysis for transcript, speakers, insights, and Q&A, including when Apple transcription fails. For visual examples first, tap **Explore sample interviews**.

The current app is **1.0 (4)**, visible in **Settings & privacy → Version**. The user’s Terminal successfully installed build 3 with Firebase; build 4 adds the persistent AI permission flow. Use Xcode **Product → Run** (⌘R), or run `Run-Subtext.command` in Mac Terminal with an iPhone simulator booted, to update the installed app and preserve recordings.

Tested with Xcode 27.2. Deployment target: iOS 17.0. The app targets the iPhone device family (`1`), with Mac Catalyst, Designed for iPhone on Mac, and visionOS compatibility disabled. It has no native iPad target. Apple's iPhone-app compatibility behavior on iPad is separate from native device-family targeting.

The iOS app requires the official Firebase Apple SDK **13.1.1** (`FirebaseCore`, `FirebaseAILogic`, and `FirebaseAppCheck`), pinned in the Xcode workspace. Missing SDK imports fail compilation, and a build phase rejects missing/mismatched packaged Firebase configuration. Configuration errors are distinguished from attestation and model-access errors. The Xcode project uses a native static `SubtextCore` target; `Package.swift` provides the same core and offline AI validation tests for macOS execution without downloading Firebase.

## Implemented

- Immediate local AAC recording, live microphone metering, elapsed time, pause/resume, timestamped bookmarks, interruption handling, and a file-preserving exit after audio errors.
- Original-audio playback, sampled waveforms, seek/skip, playback speed, and audio export. Active-recording audio and bookmarks have recovery metadata; playable orphan files are recovered on launch. A damaged interrupted file is retained even when it cannot be decoded.
- Library search across titles, speakers, transcript text, notes, and follow-ups; sorting, review filters, import, and confirmed deletion.
- Transcript editing, timestamp correction, speaker reassignment, stable speaker IDs, later speaker naming/roles/colors, saved quotes, and review flags.
- AI Q&A with cited question/answer turns and follow-ups, plus a local heuristic option. AI perspective cards cover key points, open questions, follow-ups, and context needs with source passages. Human review decisions and written follow-ups survive transcript reanalysis.
- Session and library Insights for saved quotes, review flags, notes, and bookmarks. Text export includes current names and timestamps.
- Automatic post-recording local transcription (opt-out), language selection, 45-second PCM chunking, progress/cancellation, durable diagnostics, and explicit partial-result warnings. Apple Speech does not identify speakers; full-audio cloud review provides suggested speaker grouping. Explicit Apple-service transcription can permit online recognition when a local model is unavailable, with separate per-request consent.
- Persistent, optional cloud AI permission disclosed on first launch and controlled in Settings. Missing/corrupt consent stays private, permission is checked before each interview request, and revocation cancels pending AI work. Granting access never uploads older interviews or older queued recordings.
- Firebase AI Logic audio review adapter with neutral speaker suggestions, summary, insights, and Q&A. The SDK is linked and the supplied app configuration is bundled locally. **Cloud access also requires Firebase App Check approval. The running build’s current error is App Check rejection; enabling the app’s sharing permission does not register a simulator debug token.** See [Firebase setup](docs/FIREBASE_SETUP.md).
- Dynamic system type, light/dark system surfaces, labeled controls, safe-area layouts, and portrait/landscape support. Accessibility and screen-size behavior still require runtime review.

Sample interviews are fictional text without audio and are labeled in the library, workspace, and exports. They never simulate playing a recording. AI text, speaker grouping, timestamps, and Q&A pairings remain drafts; the app does not perform external fact verification.

## Try the AI workflow

Finish saves the original and queues Apple transcription. Settings can disable automatic transcription or change the language. If AI permission was enabled when Finish was tapped and remains enabled afterward, cloud audio analysis follows Apple’s attempt. It can supply speaker suggestions and insights, or transcribe when local recognition fails. Disabling automatic transcription saves audio without starting either provider. Mixed or overlapping speech can still be difficult; no accuracy guarantee is made.

First-launch AI permission identifies Google as the recipient and explains audio/text analysis. **Use Apple transcription only** keeps cloud AI off. **Settings & privacy → Allow cloud AI analysis** can enable it after the same disclosure or revoke it immediately. This is Subtext’s own sharing consent, separate from microphone, Speech Recognition, and advertising-tracking permissions. Switching it on never processes existing recordings automatically; manual actions remain available for older interviews.

In Debug Settings, **Copy Firebase debug token** copies the running build’s private token locally for two minutes. Register it in Firebase App Check, then use **Check AI connection** (fixed text prompt, no interview attached). **Add AI test recording** imports a real 19-second fictional interview with two synthetic voices. The reference text is not inserted into model output.

Transcript-only AI review creates cited insights/Q&A and preserves text, speaker corrections, quotes/flags, notes and bookmarks. Manual full-audio review confirms transcript replacement and speaker detection. Both require current AI permission. Partial transcript warnings remain after text-only review. Processing failures are saved per interview with retry choices, and a failed cloud review keeps the available Apple draft.

Gemini Nano 4 is Android/AICore-only in this setup. Subtext uses Apple Speech locally and cloud Gemini through Firebase. It does not present a local Nano model as running in the iPhone simulator.

## Verification

Run the reproducible check:

```sh
scripts/verify.sh
```

Inside Codex's restricted nested-sandbox environment:

```sh
SUBTEXT_NESTED_SANDBOX=1 scripts/verify.sh
```

This executes 128 portable/core/AI/Speech/media tests and 45 actual AppModel state tests in an isolated native host (173 passed; one hosted-only case skipped), then builds the iPhone Simulator app/test bundles and unsigned iPhone Release app and checks deployment metadata. The state host uses an explicitly unavailable microphone adapter and cloud/Speech test doubles; it does not establish hardware capture or UI behavior. Build products and logs are in the ignored `.build-results/` folder. The iOS test bundles are compiled rather than executed.

The opt-in hosted `LiveAIIntegrationTests` uses the actual Firebase provider and the fictional audio to require transcript turns, two speaker groups, cited insights/Q&A, preserved edits, and persistence. It does not run or count as passing in the portable suites. Enable `SUBTEXT_RUN_LIVE_AI_TESTS=1` in the Xcode Test scheme environment only after configuring App Check.

To run the UI tests, choose an available iPhone simulator in Xcode and use **Product → Test**. Six UI cases use a separate test library to verify title/speaker/transcript persistence and the first-launch allow/decline, Settings disclosure, and revocation flows. They do not touch the normal app library.

See [test results and remaining device checks](docs/TESTING.md) and [implementation review](docs/IMPLEMENTATION_REVIEW.md). Builds are unsigned for verification; an Apple development team and signing are needed for installation and distribution. No App Store upload has been performed.

## Source map

| Location | Responsibility |
| --- | --- |
| `Subtext/AppModel.swift` | Library persistence, recording/recovery orchestration, imports, processing, export |
| `Subtext/Views/` | SwiftUI library, recorder, workspace, editors, and design components |
| `Subtext/Services/` | AVFoundation recording/playback, waveform sampling, Speech, Firebase AI Logic |
| `Sources/SubtextCore/` | Codable models, atomic repository, Q&A grouping, timestamps, fictional sample data |
| `Tests/SubtextCoreTests/` | Model, storage, search/review, ordering, and Q&A regression tests |
| `SubtextTests/` | AI-response validation and unavailable-service tests, also executable through SwiftPM |
| `SubtextUITests/` | iPhone UI persistence flows |
| `design-reference/`, `DESIGN_HANDOFF.md` | Original visual references and product decisions |

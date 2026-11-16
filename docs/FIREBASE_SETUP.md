# Firebase AI Logic setup

The iOS app links the official Firebase Apple SDK **13.1.1** with FirebaseCore,
FirebaseAILogic, and FirebaseAppCheck. The supplied `GoogleService-Info.plist` is
bundled locally, matches `com.jaskirtkaler.Subtext`, and is excluded from Git.
Recording, local storage, and playback work offline. Cloud review becomes available
when the SDK and a valid app configuration are bundled. Interview requests also
require Subtext’s persisted AI-sharing permission. First launch explains Google’s
audio/text processing and offers **Allow AI analysis** or **Use Apple transcription
only**. Settings can revoke that permission. With permission enabled at Finish,
automatic processing tries Apple first and then cloud audio analysis. Enabling
permission never uploads existing interviews or older queued recordings.

## Update the installed app first

The user’s Terminal successfully installed build 3 with Firebase configuration;
the current live failure is Firebase App Check rejection. Build **1.0 (4)** adds
the first-launch AI permission and Settings control. In Xcode select the Subtext
scheme and iPhone destination, then **Product → Run** (⌘R), or run
`Run-Subtext.command` from Mac Terminal. Install over the existing app to preserve recordings.
Building without running or merely reopening the simulator leaves the old app
installed. Do not uninstall the app as a setup step.

iPhone builds now require the Firebase modules at compile time, and the final
build phase checks that the packaged configuration exists and matches the app.
The app reports distinct missing-SDK, missing-configuration, and mismatched-app
errors. None of those statuses imply a successful server connection.

## Connect an Apple app

1. In the [Firebase console](https://console.firebase.google.com/), create/select a
   project, open **AI Services → AI Logic**, and complete **Get started** for the
   **Gemini Developer API** provider. Enable the APIs requested by the console.
2. Register an iOS app with the exact bundle identifier selected for Subtext in
   Xcode. Download its `GoogleService-Info.plist`; add it to the **Subtext** app
   target and confirm it appears in **Build Phases → Copy Bundle Resources**.
   Keep environment-specific configuration out of the public repository.
3. Open `Subtext.xcodeproj` and allow Xcode to resolve the pinned Firebase
   package dependencies. **FirebaseAILogic**, **FirebaseCore**, and
   **FirebaseAppCheck** are already linked to the app target; do not add them a
   second time. Firebase 13 removed the previous `FirebaseAI` product name.
4. Set up App Check as described below. Build and run on a simulator or iPhone,
   record a short non-sensitive test, open the session, and explicitly request
   cloud review. Verify transcript timestamps and speaker attribution by listening.

The app’s interview workflow gates `CloudReviewService` behind AI consent. Connection
checks are separate explicit actions using synthetic text only. Do not add a second
`FirebaseApp.configure()` to app startup. `isAvailable` only checks the SDK and
bundled configuration; it does not prove network access, quota, App Check, or model
availability. A failed request preserves the original audio and existing review.

## Model and request limits

The adapter uses `gemini-3.8-flash`, the currently documented general-use Flash
model for audio input and structured JSON (checked November 12, 2026). Set the
optional String key **FirebaseAIModel** in the app's `Info.plist` to select another
supported model. Recheck model availability before release. Firebase now marks
general-use Gemini 2.5 models deprecated; `gemini-2.5-flash` is not the default.

The service sends one inline audio part and a prompt requesting a transcript and
summary. It rejects files above 20 MB and applies a smaller **14 MB raw audio**
limit so base64 encoding, the prompt, and schema fit within Firebase's 20 MB total
request limit. Larger-recording uploads, server jobs, Cloud Storage, automatic
chunking, retries, and background processing are not implemented. Results are
bounded and validated before use; malformed, empty, or truncated results fail
without replacing local data. Speaker labels and timestamps remain suggestions.

## App Check and release configuration

The required `FirebaseAppCheck` integration installs the debug provider in
`DEBUG` builds and App Attest in release builds before configuring Firebase.

For simulator setup before sending any audio, create a debug token in Firebase
console → **Security → App Check → Apps → your app's menu → Manage debug tokens**.
In Xcode, use a private, unshared Run scheme: **Product → Scheme → Edit Scheme →
Run → Arguments → Environment Variables**. Add **AppCheckDebugToken** with that
token as its value. Keep the scheme/token local; do not commit the value, include
it in a shared scheme, or ship it in a release. Firebase reads it when the user
eventually consents to a cloud review. Creating this local configuration does not
require calling `analyzeAudio`, fetching an App Check token, or uploading audio.

An alternative is to register the debug token Firebase prints in the Xcode
console (enable `-FIRDebugEnabled` in the Run scheme if needed). In Subtext,
Firebase initializes only on the first explicitly requested cloud review, so
ordinary app launch does not produce this token log. That first review may fail
until its token is registered; use a short, non-sensitive recording if choosing
this path. Do not request a cloud review merely to obtain a setup token. Never
publish debug tokens; revoke any exposed token in Firebase console.

For release, register the iOS app with App Attest in Firebase, add **App Attest** under Xcode's
**Signing & Capabilities**, and set the entitlement
`com.apple.developer.devicecheck.appattest-environment` to `production`. These
project-specific signing changes are intentionally left for the app owner.
Keep AI Logic App Check enforcement enabled; current Firebase documentation
requires enforcement from November 2, 2026. Test a signed release on a device.

Review provider data-use/retention terms and deployment location for the intended
journalism workflow before enabling sensitive interviews. Update the privacy
policy, disclosure, App Store privacy answers, and dependency privacy manifests
for the final configuration. Do not embed a Gemini API key or service-account
credential in the app. Set project quotas, billing alerts, and appropriate API-key
restrictions; App Check does not replace cost controls or user consent. The app
does not perform external fact verification or guarantee transcription accuracy.

## Validation status and references

The configuration is validated in both iPhone builds. The real Firebase 13.1.1
structured-audio and transcript-analysis branches compile. Automated suites now
execute 173 cases (one hosted-only case skipped); workflow cases use explicit provider/recorder doubles and do
not establish actual Gemini output or recognition accuracy.

A real SDK probe failed DNS lookup under this task environment’s proxy setup.
The separate official App Check REST diagnostic reached Firebase through the
normal provided proxy and returned HTTP403 PERMISSION_DENIED for its private
host debug attestation. No security enforcement was disabled; no Gemini request,
transcript upload, or audio upload followed. Actual iPhone-build attestation and
model access still require verification.

In the running Debug app, use **Settings & privacy → Copy Firebase debug token**
and register the copied value under the Subtext iOS app in **Firebase App Check →
Manage debug tokens**. The clipboard value is local and expires after two minutes;
the app does not display it. Then retry **Check AI connection**, which sends a
fixed synthetic text prompt and no interview. Resolve any subsequent API, quota,
model, or permission error shown.

Finish automatically attempts local transcription unless disabled in Settings.
If AI sharing was allowed at Finish and remains allowed afterward, cloud audio
analysis follows the Apple attempt for speakers, transcript, insights, Q&A and
follow-ups. It also runs as a fallback when Apple recognition fails. Requests for
older recordings remain explicit manual actions. A text-only review excludes audio,
personal names/roles, notes, title and bookmarks; partiality is a generic boolean,
not the diagnostic message. It preserves existing transcript corrections. For
speaker detection or failed local recognition, separately choose **Cloud
transcript, speakers & AI review** and confirm uploading original audio. Both
paths require current AI permission, need human review, and preserve original recordings/personal notes.

Use **Add AI test recording** in Debug settings to test the real two-voice WAV
without recording anyone. Compare generated results with the audio and reference
transcript; expected answers are not prefilled into API output.

- [Apple setup and current SDK product](https://firebase.google.com/docs/ai-logic/get-started?platform=ios)
- [Audio input and size limits](https://firebase.google.com/docs/ai-logic/analyze-audio)
- [Structured JSON output](https://firebase.google.com/docs/ai-logic/generate-structured-output)
- [Supported models and lifecycle](https://firebase.google.com/docs/ai-logic/models)
- [AI Logic App Check requirements](https://firebase.google.com/docs/ai-logic/app-check)
- [App Check debug-provider setup](https://firebase.google.com/docs/app-check/ios/debug-provider)
- [App Attest setup](https://firebase.google.com/docs/app-check/ios/app-attest-provider)

## Real-provider verification

The current synthetic gateway probe reached Firebase and returned HTTP 401
UNAUTHENTICATED requiring App Check. This confirms the backend requirement;
removing the app's preflight does not provide working model access. No owner
credentials or Firebase management connection are available in this session.
Debug-token registration needs an authenticated Firebase Console session.

`SubtextTests/LiveAIIntegrationTests.swift` is a hosted, real-provider check. In
Xcode, use Edit Scheme → Test → Arguments → Environment Variables to enable
`SUBTEXT_RUN_LIVE_AI_TESTS=1` locally. The test uploads only the bundled fictional
recording and requires actual transcript turns, two speaker groups, cited
insights/Q&A, and a second transcript-review response preserving human edits
and saved data. It does not prefill expected text. It deliberately skips without
that flag and is not counted as passing until actual execution succeeds.

Apple service transcription is a separate per-request option when local Speech
models are absent. It can send audio to Apple after consent, requires no Firebase
setup, and does not identify speakers. It remains subject to Apple's recognition
availability, language support, permission, and network conditions.

## Consent and Firebase approval are separate

Subtext's first-launch choice and Settings toggle authorize sharing recording
audio/transcript text with Google for AI review. Pending or denied permission
blocks interview requests before reading audio or contacting the provider.
Automatic cloud eligibility is captured at Finish and rechecked after Apple
transcription; enabling permission cannot upload older queued interviews.
Revocation cancels cloud work and rejects late results, even after regrant.

This client permission does not register Firebase App Check tokens. The running
simulator's full private debug token must still be registered by a project owner
in Firebase Console → App Check → Apps → Subtext iOS → three-dot menu → Manage
debug tokens. No authenticated Firebase management connection is available in
this session. Development tokens are not embedded in code or consent records.

The AI-sharing screen is Subtext UI. Microphone and Speech Recognition remain
separate iOS permissions. App Tracking Transparency concerns advertising-related
tracking and is not used for this AI sharing choice. This implementation supports
explicit data-sharing consent and withdrawal; it does not establish an App
Review approval or replace the final privacy policy and App Store disclosures.

- [Apple App Review privacy requirements](https://developer.apple.com/app-store/review/guidelines/#privacy)
- [Apple tracking permission scope](https://developer.apple.com/app-store/user-privacy-and-data-use/)

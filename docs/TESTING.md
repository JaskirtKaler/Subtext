# Processing and AI validation — November 12, 2026

## Current result

**173 automated cases passed, zero failures**, with one hosted-only case skipped, followed by successful iPhone Simulator app/unit/UI bundle compilation and unsigned iPhone Release builds. Both apps are **1.0 (4)**, iOS 17+, device family `[1]`, with Mac/Catalyst/visionOS compatibility disabled. FirebaseAILogic and FirebaseCore linkage was independently verified in both binaries. The final build phase validates the packaged Firebase configuration without printing its values.

## Reported missing-SDK failure

Earlier read-only inspection found build 1 without Firebase configuration. The user then successfully installed build 3 through Mac Terminal; its Firebase configuration is present and its current error is App Check rejection. The original Speech error is unavailable because old sessions had no diagnostic field and the latest cloud attempt replaced the current processing error. No recording or transcript was read for this diagnosis.

The current app requires Firebase imports on iOS; a missing SDK now fails compilation. Missing or mismatched configuration produces a distinct error, including through AppModel and the workspace action. Language matching now ignores unrelated locale formatting extensions. An audible chunk returning no text is treated as incomplete when other chunks return text.

A standard install of the verified updated app was attempted and blocked before installation by CoreSimulator XPC error 61. Run **Product → Run** in Xcode, or run `Run-Subtext.command` from the user's Mac Terminal, to install it over the existing app and preserve recordings. Then verify **Settings & privacy → Version → 1.0 (4)**. Reopening the simulator alone does not update the installed app.

| Executed suite | Cases | Actual coverage |
| --- | ---: | --- |
| Core data and review mapping | 36 | Evidence-linked insights, semantic AI Q&A, preservation of human review, transcript-only review, warning/error migration, persistence/search/export, original-audio metadata |
| Cloud parsing and preflight | 38 | Structured schema, citation bounds, transcript payload privacy/completeness flag, source preservation, precise configuration/error categories, cancellation/timeout, debug-helper default safety; one additional hosted-only configuration case skipped |
| Local Speech support | 45 | 45-second PCM chunking with precise offsets/durations, locale normalization, punctuation/question marks, recognizer result conversion, skipped-range warnings, empty/silent/unsupported/pre-cancelled paths without requesting live authorization |
| Waveform sampling | 9 | Real AVFoundation PCM tone/silence, bounded sample count, malformed input, cancellation |
| AppModel workflows | 45 | Finish→automatic local transcription→AI offer, opt-out/language preferences, queued recordings, partials with no hidden upload, full/text-only processing, stale-reference rejection, precise configuration errors, failures/cancellation, saved corrections, exports and relaunch |

Reproduce the executed suites and both iPhone builds with:

```sh
SUBTEXT_NESTED_SANDBOX=1 scripts/verify.sh
```

Outside the restricted nested environment, use `scripts/verify.sh`. `scripts/test-workflows.sh` runs the native state host separately. It uses byte-identical AppModel, Cloud, and Speech sources plus real Core/file/AVFoundation helpers. Cloud/Speech outputs in these workflow cases are explicit test doubles; the default microphone adapter is unavailable, and Finish cases inject a declared fake recorder. The tests do **not** establish microphone or real recognition accuracy.

## Product workflow now implemented

- First launch offers explicit Google AI-sharing permission or Apple-only processing. Missing/corrupt/unwritable consent stays private. Settings can grant or revoke access.
- Finish durably saves original audio/bookmarks, then queues Apple local transcription by default. With permission granted at Finish and still valid afterward, cloud audio analysis follows for speakers/transcript/insights/Q&A, including fallback after local failure. Settings can disable automatic processing or select the Speech language.
- Local processing works through sequential approximately 45-second mono PCM copies; originals are retained. Progress and cancellation belong to the correct interview.
- Recognizer no-speech failures in some chunks produce a **partial transcript warning** with time ranges; affected output is flagged for review. All-no-speech still fails. Digital silence does not create a false warning.
- Manual **transcript-only** and **full-audio speaker** review choices require current AI permission. Existing interviews are never uploaded merely by granting permission. Transcript-only review sends indexed text/timestamps/neutral speaker hints, not audio, names, roles, notes, or bookmarks. The payload includes only a generic incomplete flag when applicable.
- Explicit **Transcribe with Apple service** permits online Apple recognition only after per-request consent; the default remains on-device. Apple output has no automatic speaker attribution.
- A direct **Detect speakers from audio** action invokes the full-audio Google consent. Setup and connection checks are reachable from failed/empty/partial workspaces; configuration errors persist per interview.
- Local failures/partials retain diagnostics and manual review actions. Automatic fallback occurs only for new recordings explicitly covered by the enabled AI-sharing choice at Finish; revocation/regrant cannot resurrect older queued uploads.
- Cloud schema requests summary, source-linked key points/open questions/follow-ups/context needs, and semantic question/answer references. Invalid citations reject the result atomically.
- Transcript review preserves original turns, speaker IDs/corrections, quotes/flags, notes, bookmarks and existing human Q&A decisions. It refuses results when source text/timing/assignment changed in flight.
- Insights cite saved source turns, and evidence taps seek audio/reveal the transcript. Q&A has suggested answer passages and follow-ups, with human review status. A reviewed recording with no suggested Q&A is labeled clearly rather than presented as a failed feature.
- Processing errors and partial warnings survive relaunch. Refreshing AI review never makes a partial local transcript appear complete.

## Real Firebase access result

The actual Firebase 13.1.1 service and new schema compiled. A native SDK probe accepted the bundled configuration, then URLSession failed hostname lookup during App Check (`-1003`). The task environment supplies HTTP(S) proxy variables which ordinary `curl` honors, while the SDK has no public session-proxy hook.

A separate declared diagnostic sent the official App Check `exchangeDebugToken` request through the existing normal proxy using ordinary `curl`. Transport succeeded; Firebase returned **HTTP 403 `PERMISSION_DENIED`**, classified as rejected debug attestation. App Check enforcement and OS security settings were not changed. The temporary debug secret was kept private and deleted; only redacted outcome/stage data remains under `.build-results/cloud-smoke/`.

The latest separate fixed synthetic request to the normal Firebase AI gateway returned HTTP 401 UNAUTHENTICATED requiring App Check, confirming that removing the client preflight would not grant access. No successful Gemini response, transcript-review request, or audio upload followed. **Actual Gemini output, live model eligibility, transcription/diarization quality, and the running iPhone build’s attestation remain unverified.** The rejected diagnostic token belongs to the test host; register the token copied by the actual running simulator app before retrying that build.

## Finish Firebase setup in the running Debug app

1. Run the current Subtext scheme in Xcode and open library actions → **Settings & privacy**.
2. Select **Copy Firebase debug token**. It copies the actual build’s SDK token locally for two minutes without showing the value.
3. In Firebase Console → **App Check**, select the registered Subtext iOS app → **Manage debug tokens**, and register that copied value. This is a private development token, not a Gemini API key.
4. Select **Check AI connection** in Subtext. It sends a short fixed synthetic text prompt only. Follow any specific API/permission/quota/model error shown after attestation succeeds.
5. Select **Add AI test recording** for the bundled real 19-second two-voice fictional WAV. Play it, transcribe locally, then consent to transcript AI review or full-audio review to test speaker detection too. Expected content is in `Subtext/PreviewContent/IntegrationSample.txt`; it is not prefilled into results.

## Runtime/device checks still required

The user confirmed basic microphone recording and normal permission prompts work. The app library was previously observed on an iPhone 18 Pro simulator. Automated iPhone test execution remains blocked by CoreSimulator XPC; a temporary Mac Catalyst test host compiled/linked but Apple testmanager execution was denied (`159`). The six UI tests (three editing/persistence and three consent cases) are compiled rather than executed.

Player/recorder-specific platform cases are compiled/typechecked; live Speech recognition and overlapping YouTube speech were not reproduced through a real recognizer here. Test on an iPhone: the failed recording’s diagnostic code/language, mixed/overlapping voices, long recordings, unsupported language/model downloads, locked/background capture, calls/input changes, low storage, recovery, playback output, accessibility and keyboard/sheet layouts. Cloud audio retains the 14 MB inline limit; longer recordings can use local transcription followed by transcript-only AI review. These checks do not certify release readiness or recognition accuracy.

## Live test status

The opt-in `LiveAIIntegrationTests` was compiled into the latest iPhone unit-test
bundle. It was not executed in this session. With a registered debug token,
set `SUBTEXT_RUN_LIVE_AI_TESTS=1` in the local Xcode Test scheme environment
and run that suite. It uses actual Firebase responses for the fictional WAV,
requires two speaker groups, transcript turns, cited insights/Q&A, a subsequent
text review, preserved human edits, persistence, and unchanged original bytes.
It skips by default and is not included in the 173 passing portable/state cases.

The updated installer logs to `.build-results/user-simulator-install.log`, checks
the actual installed bundle's build and configuration after installation, and
launches with `--terminate-running-process` to avoid reusing an old process.
Normal install routes remain blocked from the assistant session; the user's
Mac Terminal can run `Run-Subtext.command` with Simulator open. No app reset or
uninstall is part of the installer.

## Consent verification — build 4

The full verification passed 128 portable/media cases and 45 AppModel state
cases, excluding one host-only skip. New state cases cover pending/denied
permission, corruption and readonly storage, persisted grants without historical
uploads, Apple-first cloud fallback, preserved local drafts on cloud failure,
revocation/regrant during queued and active work, and ignored-cancellation late
provider callbacks. The privacy review found no blocking source findings.

Three new UI cases cover first-launch decline/default Apple behavior,
allow/revoke/relaunch, and the Settings enable disclosure. All six UI methods
and the real-provider integration test compiled; none were executed here.
The final first-launch sheet is evaluated before recovery and defers during
recording; both choices are pinned below its scrollable disclosure.

Evidence: `.build-results/build4-verification.log`. App Check remains owner-side
setup; no token was embedded, no enforcement was changed, and actual successful
cloud analysis remains unverified.

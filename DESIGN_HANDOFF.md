# Subtext: design handoff

## Product direction

Subtext is an iOS interview recording and review app for journalists. The priority is to start capturing audio quickly: tap Record without having to name the interview or identify the speakers first. A default date-and-time title is fine, and names can be added later. The original audio is the source of truth; transcripts, speaker labels, Q&A pairings, and insights are assistive and may be wrong.

The intended implementation is SwiftUI, with Firebase AI Logic planned for AI features. The exact transcription, speaker diarization, processing, storage, and privacy architecture has not been established by these mockups. Do not infer that Firebase AI Logic alone performs every task or that the UI demonstrates working functionality.

## Reference files

The original Stitch HTML, screenshots, and design tokens are preserved in `design-reference/`. These are visual references, not SwiftUI code or a functional application. The transcript screenshot shows the rename-speaker sheet over the underlying transcript, not an unobstructed transcript screen. The design system is in `design-reference/editorial_precision/DESIGN.md`.

## Main flow and screens

1. **Interview library** (`interview_library`): recent session cards with title, date, duration, speaker count, waveform preview, status, and optional Q&A/insight indicators. Filters and sorting help find sessions. The prominent central Record action should begin a new session quickly. Mockups also show search, an account button, and Library / Record / Insights navigation.
2. **Active recording** (`active_recording`): elapsed time, recording state, selected microphone, live waveform and input level, and large Pause, Finish, and Bookmark controls. A bookmark captures a moment without interrupting the interview; the mockup shows annotated bookmarks. Local autosave and later processing are presented as concepts, not verified technical guarantees.
3. **Interview workspace** (`workspace_transcript_tab` and `workspace_q_a_tab`): persistent playback controls and a seekable waveform accompany Q&A, Transcript, and Insights tabs. Timestamps should link review content to the relevant audio. The transcript has speaker turns, speaker filtering, search, auto-scroll, and actions for quotes and fact-check flags. Q&A pairs detected questions and possible answers with expandable analysis and suggested follow-ups. Insights is named in navigation, but no dedicated Insights screen was supplied.
4. **Rename speaker sheet** (visible in the transcript screenshot and HTML): speakers initially have neutral identifiers such as Speaker A and Speaker B. Users may later set a name, role, and color. A rename should update references across the session by speaker ID; it should not imply that automatic speaker attribution is always correct. The sheet's wording and example counts are mock data.

## Visual direction

Native, clean iOS presentation with a light warm-gray background, white rounded cards, dark readable text, blue navigation and playback controls, and red recording controls. Use speaker labels and colors consistently throughout the waveform, transcript, and Q&A; avoid relying on color alone. The reference uses Inter for interface text and JetBrains Mono for timestamps, while its prose also invokes native iOS conventions; font choice can be decided during implementation. Preserve readable typography, 44-point touch targets, safe areas, and adaptability to different screen sizes and accessibility text sizes.

The design token file and rendered screens are not entirely consistent about exact colors and speaker palettes. Treat the screenshots as visual direction rather than hardcoding every contradictory token. The recording screenshot shows its timer partly obscured by the navigation header; make the timer fully visible in the SwiftUI layout.

## Important distinctions for implementation

- The designs are static prototypes with example text and simulated statuses; they do not establish working audio, playback, transcription, speaker detection, AI analysis, or sync.
- The flow needs microphone-permission, denied-permission, interruption, background recording, low-storage, save failure, processing, and retry states. Preserve recordings if transcription or AI processing fails. These states are not fully designed yet.
- A user should be able to review and correct a transcript or speaker assignment; renaming a person alone does not correct a wrongly assigned turn. The exact correction UX remains to be designed.
- Labels such as “98.4% Acc.”, “Verified”, “Semantic Verification”, and “Evaded” imply certainty the mockup cannot substantiate. Treat AI findings as suggestions, cite the relevant audio/transcript, and allow human review. External fact verification must not be implied without an actual source and verification process.
- Claims such as “Encrypted Local Safety Net”, “On-Device Guard”, “lossless”, and specific microphone formats are proposed interface copy, not confirmed implementation properties. Only show them when the actual capture, storage, processing, and security behavior supports them. Clarify what leaves the device before cloud AI processing.
- The live recording page says processing begins when finished; live transcription or live speaker detection is not established. Timing and offline behavior remain open product and technical decisions.
- Additional mockup features such as procurement-record matching, automated classifications, claims analysis, external mic format, syncing, and global Insights should not be assumed implemented or required for the first SwiftUI build.

## Suggested next chat

Ask the next chat to read this file and the `design-reference/` assets first, then build the SwiftUI interface in stages using representative local sample data. Keep the record-first flow and later speaker naming. Clearly distinguish visual prototypes from working audio/AI features; integrate real services only as those choices are defined.

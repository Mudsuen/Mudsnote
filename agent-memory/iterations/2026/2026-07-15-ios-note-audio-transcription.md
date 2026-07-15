# 2026-07-15 iOS opened-note audio transcription

## Request

Continue evolving the iPhone app toward Apple Notes while retaining Mudsnote's quick-note and Markdown strengths. This iteration closes the gap between Quick Capture audio transcription and recording from an already-opened note. iPad and accessibility work remain out of scope.

## Baseline

- Branch: `main`
- HEAD: `92245ce`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- An audio recording made in the full note editor is now attached atomically before transcription starts, so speech recognition failure never loses the recording.
- Local on-device speech recognition runs immediately after attachment and uses the user's current locale instead of a hard-coded Simplified Chinese locale.
- Non-empty speech is appended as an `Audio transcription` Markdown section and saved through the existing conflict-aware document path.
- The transcript remains normal editable Markdown, renders in the reader, participates in Find in Note, and is included by library-wide search.
- Empty speech keeps the audio and reports that no speech was detected; transcription errors keep the audio and expose a localized recovery status.
- Retry is serialized with the existing audio transition guard, and the editor reports a distinct transcribing state.
- Added deterministic unit and UI fixtures for attachment durability, Markdown persistence, rendering, Find in Note, and global search.

Apple's iPhone Notes guide documents recording audio in a note, viewing its transcript, searching it, copying it, and adding transcript text to the note. This implementation follows that user outcome while preserving Mudsnote's local-first Markdown storage: <https://support.apple.com/guide/iphone/record-and-transcribe-audio-iphbe11247b5/ios>.

## Verification

- `git diff --check`: passed.
- `jq empty iOS/Localizable.xcstrings`: passed.
- Focused persistence and opened-note transcription UI tests: passed.
- Runtime screenshot inspected at `/tmp/mudsnote-audio-transcript-ui/6ABDD57B-359E-4C87-93D7-FF46418456B4.png`; the half-sheet reader showed the audio control, rendered transcript, highlighted Find in Note result, and single-row find toolbar without clipping.
- Full single-device regression:
  - Command: `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,id=BA9A4203-C694-492A-9CD0-6B80E3BC6ED5' -parallel-testing-enabled NO test`
  - Result: 137 tests, 0 failures.
  - Result bundle: `/Users/Donald/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Logs/Test/Test-MudsnoteCompanion-2026.07.15_10-36-45-+0800.xcresult`
- Shut down all simulators after verification.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice reported the phone as `unavailable` and rejected installation with error 1011. The app was therefore not installed in this iteration.

## Decisions

- Persist the audio first, transcribe second, and save ordinary Markdown third. This keeps the irreplaceable recording durable across permission, recognition, cancellation, and conflict failures.
- Reuse the document editor's conflict-aware save path rather than introducing a transcription-only write path.
- Keep recognition local and locale-aware; no server account or remote note transmission is introduced.
- Simulator automation proves storage orchestration, rendering, and retrieval. Real microphone permission and speech-recognition quality remain physical-device smoke work.

## Next

- Retry direct installation and real microphone/speech smoke verification when MudsPhone becomes available to CoreDevice.
- Continue the iPhone Notes-parity audit with the next high-value everyday workflow gap.

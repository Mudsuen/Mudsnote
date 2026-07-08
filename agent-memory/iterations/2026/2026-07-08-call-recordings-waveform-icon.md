# 2026-07-08 Call Recordings waveform icon

## Request

Continue the active Apple Notes parity goal, prioritizing lightweight UI alignment and keeping performance constraints intact.

## Baseline

- Branch: `main`
- HEAD before work: `c86754d Tighten Notes toolbar capsule`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-current-baseline/apple-notes-vs-mudsnote.png`
- The source list already had a `Call Recordings` smart source, but its icon still used a plain `phone.fill` glyph while the Apple Notes reference shows a phone-with-waveform treatment.

## Changes

- Added `LibraryNotesLayout.callRecordingsSourceSymbolName`.
- Changed the `Call Recordings` smart source icon to `phone.and.waveform.fill`, which is available on the current macOS toolchain.
- Added regression coverage proving the source button uses the configured phone-waveform symbol sizing.
- Updated the Apple Notes parity roadmap to record the phone-waveform source-list rule.

## Verification

- Commands run:
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-current-baseline`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryCallRecordingsSourceFiltersExistingSnapshot'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-call-recordings-waveform-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the final visual QA harness.
- Result:
  - Focused library-window tests passed.
  - Full `swift test` passed with 100 tests in 2 suites.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-call-recordings-waveform-final/apple-notes-vs-mudsnote.png`.
  - Final metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`, `selected_fixture=content`, and `frontmost_before_capture=Mudsnote`.
  - Visual inspection confirmed the `Call Recordings` row now uses a phone-with-waveform icon closer to the Apple Notes reference.

## Decisions

- Keep this as a pure source-list visual alignment change; do not touch search, note indexing, or note storage.
- Use the existing SF Symbol instead of custom drawing so the change stays native and lightweight.

## Next

- Continue source-list hierarchy and note-list row state tuning against the side-by-side visual QA.

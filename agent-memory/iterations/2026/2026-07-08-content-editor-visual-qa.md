# 2026-07-08 Content editor visual QA

## Request

Continue the active Mudsnote Apple Notes parity goal, especially making UI iteration evidence stronger while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `8e258c8 Tighten Notes editor rhythm`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-compact-editor-final/apple-notes-vs-mudsnote.png` kept the shell stable, but the fixture selected an empty note, so editor typography/body rhythm changes were not visible in the side-by-side capture.

## Changes

- Added a visual QA launch argument:
  - `--visual-qa-select-note <path>`
- Added `LibraryWindowController.selectNoteForVisualQA(at:)` so the app can select and load a deterministic fixture note without coordinate-based scripting.
- Extended `scripts/visual_notes_qa.sh` with `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE`:
  - `empty` selects `New Note.md`
  - `content` selects `lz合集.md`
- Expanded the `lz合集.md` fixture body so the right editor pane has meaningful text for content-state visual review.
- Recorded selected fixture metadata in `visual-qa-metadata.txt`.
- Added regression tests for argument parsing and content-note selection/loading.
- Updated the Apple Notes parity roadmap to mention empty-note and content-note visual QA modes.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/appControllerVisualQAModeUsesIsolatedNoteStore|MarkdownRichEditorTests/libraryWindowVisualQASelectionLoadsRequestedContentNote|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'`
  - `swift test --filter 'MarkdownRichEditorTests/appControllerVisualQAModeUsesIsolatedNoteStore|MarkdownRichEditorTests/libraryWindowVisualQASelectionLoadsRequestedContentNote'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-select-empty-final`
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-select-content-final`
  - `./scripts/package_app.sh && MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-select-content-fixed`
  - `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-select-empty-fixed`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via both visual QA fixture modes.
- Result:
  - Focused visual-QA argument/selection tests passed.
  - Full `swift test` passed with 99 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Empty fixture visual QA captured `/tmp/mudsnote-visual-qa-select-empty-fixed/apple-notes-vs-mudsnote.png`.
  - Content fixture visual QA captured `/tmp/mudsnote-visual-qa-select-content-fixed/apple-notes-vs-mudsnote.png`.
  - Empty metadata recorded `selected_fixture=empty`, `selected_note_path=.../New Note.md`, `frontmost_before_capture=Mudsnote`, and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
  - Content metadata recorded `selected_fixture=content`, `selected_note_path=.../lz合集.md`, `frontmost_before_capture=Mudsnote`, and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
  - Visual inspection confirmed empty mode still selects `New Note` and content mode selects `lz合集` with visible editor body text.
- Fix during verification:
  - The first content capture still selected `New Note`; adding a QA-only delayed selection retry fixed the race with deferred launch hydration.
- Not verified:
  - A matching Apple Notes content-state reference image is not yet checked into the repo, so content mode currently proves the Mudsnote editor state and layout, not a true content-vs-content reference comparison.
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Prefer deterministic in-app selection over mouse-coordinate automation for visual QA.
- Keep this as verification infrastructure plus fixture data only; no production note-loading or indexing behavior changes.

## Next

- Run focused visual-QA selection tests, full tests, package the app, and capture both empty and content visual QA states.

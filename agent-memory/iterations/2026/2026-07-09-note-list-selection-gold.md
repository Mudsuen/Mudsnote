# 2026-07-09 note list selection gold

## Request

Continue the active Apple Notes parity goal, keeping the compact toolbar baseline and moving the note list closer to the supplied Apple Notes visual reference.

## Baseline

- Branch: `main`
- HEAD before work: `b1af277 Lock compact Notes toolbar baseline`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-compact-toolbar-baseline-lock-final/apple-notes-vs-mudsnote.png`

## Evidence

- Screenshot sampling through `ffmpeg` showed the Apple Notes selected-note card's dominant dark gold near `RGB 140/111/25`.
- The packaged Mudsnote screenshot's selected-note card sampled near `RGB 155/130/49`, which was brighter and more washed out than the reference.

## Changes

- Promoted the note-list selected-row fill to `LibraryNoteRowView.selectionFillColor`.
- Tuned the selected-note card fill toward a darker Notes-like gold.
- Added regression coverage for the selected-row fill color so future UI passes do not drift back to a brighter yellow card.
- Updated the Apple Notes parity roadmap with the sampled selected-row color state.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-selection-gold-final2`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Final screenshot sampling moved the packaged Mudsnote selected-note card from about `RGB 155/130/49` to about `RGB 142/114/35`, closer to the Apple Notes sample near `RGB 143/113/25`.
- Visual inspection confirmed the selected note row now reads as a darker Notes-like gold while toolbar and window sizing remain on the compact baseline.

## Decisions

- Keep this as a focused presentation change; do not alter list row sizing, toolbar scale, note metadata, or stored Markdown.
- Use screenshot sampling as a guide, then verify with the packaged app rather than relying on source constants alone.

## Next

- Continue with source/list typography and editor rhythm tuning after the selected-row color is visually closer.

# 2026-07-03 editor tools disabled treatment

## Context

Continue the active macOS Apple Notes parity goal. The grouped editor toolbar capsule already enabled and disabled its buttons correctly, but the overall capsule did not visually dim as a single unavailable toolbar group. That made empty-library and trash states feel less like native Notes toolbar affordances.

Baseline before this slice: `f0aca55 Add source list hover feedback`.

## Changes

- Added explicit enabled/disabled alpha metrics for the library editor-tools toolbar capsule.
- Dimmed the grouped editor-tools view and weakened its capsule border when editing is unavailable.
- Restored full alpha and stronger border when a note/new note is editable.
- Extended the toolbar disabled-state regression test to cover empty-library, new-note, selected-note, and trash states.

## Validation

- `swift test --filter MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates`
- `swift test`
- `./scripts/package_app.sh`
- `/usr/bin/time -p ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-tools-disabled-treatment`

Packaged visual QA completed in 6.59s and captured:

- `mudsnote_window_bounds=x=36,y=69,width=1440,height=877`
- comparison image: `/tmp/mudsnote-visual-qa-editor-tools-disabled-treatment/apple-notes-vs-mudsnote.png`

## Notes

- The underlying command gating remains unchanged; this is visual state treatment for the existing enabled/disabled behavior.
- The default visual QA state has an editable selected note, so unit coverage verifies the unavailable empty/trash states while visual QA verifies the packaged shell still renders correctly.

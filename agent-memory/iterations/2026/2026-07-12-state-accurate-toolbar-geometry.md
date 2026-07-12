# State-accurate toolbar geometry

## Baseline

- Started from `b900ad2 Match editor rhythm to the content reference`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Forced the checked-in Apple Notes Retina references to use their actual `2x` backing scale even when PNG DPI metadata is missing.
- Added deterministic expanded/collapsed source-list state to the visual QA harness and its metadata.
- Moved New Note after the note/editor tracking separator so the list menu and creation command occupy the same toolbar regions as Apple Notes.
- Added a regression assertion for toolbar item ownership around the tracked divider.

## Verification

- `bash -n scripts/visual_notes_qa.sh` passed.
- Focused library shell testing passed.
- Corrected expanded comparison is stored at `/tmp/mudsnote-toolbar-structure-expanded-149/apple-notes-vs-mudsnote.png`.
- Collapsed comparison against the supplied Notes crop is stored at `/tmp/mudsnote-toolbar-structure-collapsed-149/apple-notes-vs-mudsnote.png`.
- Final full-suite, packaging, signing, and installed-app checks are recorded in the completion commit.

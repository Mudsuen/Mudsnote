# Unoccluded first note row

## Baseline

- Started from `0effb5c Match native toolbar menu tracking`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Disabled `NSTableView` floating group rows in the library note list.
- Anchored the note-list content stack to the pane safe area instead of the full-size titlebar origin.
- Added regression assertions for both layout contracts.

## Verification

- Focused shell and empty-note tests passed.
- External-display empty-note comparison confirmed the toolbar title/count, `Today` header, and complete `New Note / time / No additional text / Notes` row no longer overlap.
- Final full-suite, packaging, signing, and installed-app checks are recorded in the completion commit.

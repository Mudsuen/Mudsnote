# Immediate native toolbar menus

## Baseline

- Started from `dbdc00d Refine Notes sidebar and save feedback`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Added `LibraryToolbarMenuButton` to enter menu tracking on primary mouse-down.
- Kept the trigger highlighted until the menu closes.
- Applied the specialized control only to list options and `Aa`; ordinary toolbar commands remain standard buttons.
- Updated the parity scorecard to reflect the deliberate removal of share/export and more toolbar chrome.

## Verification

- Focused library-shell construction tests passed.
- Final full-suite, external-display installed-menu smoke, packaging, and signing checks are recorded in the completion commit.

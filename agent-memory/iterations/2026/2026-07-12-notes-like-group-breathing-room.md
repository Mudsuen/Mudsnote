# Notes-like group breathing room

## Baseline

- Started from `6d2ee7b Align editor origin with Notes`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Increased note-list group rows from `48pt` to `54pt`.
- Increased group-title bottom inset from `6pt` to `12pt`, keeping `row height - bottom inset` fixed at `42pt` so the title baseline remains unchanged.
- Added a regression assertion for that baseline invariant.

## Verification

- Focused library shell testing and the full Swift test suite passed.
- Packaging, strict signing, and installed-app process launch passed.
- Two visual-QA attempts could not activate Mudsnote because the current frontmost process was `loginwindow`; no screenshot is accepted as evidence for this iteration yet.
- Empty/content visual confirmation remains required after the desktop session is unlocked.

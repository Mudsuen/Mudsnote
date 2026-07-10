# Middle Toolbar Circular Buttons

## Scope

- Baseline: `77b19ce Group Notes file actions`
- Keep normal note-list scrolling unchanged.
- Match Apple Notes' middle-column list-options and New Note controls without changing the editor-tools or file-actions groups.

## Implementation

- Added a focused circular toolbar-button factory for the two middle-column actions.
- Locked both controls to `30x30`, `16pt` native symbols, a restrained dark fill, and a clear zero-width rim.
- Preserved toolbar-item and button target/action wiring, tooltips, and accessibility labels.

## Verification

- Targeted toolbar/layout/action tests passed: 3 tests.
- Full `swift test` passed: 102 tests in 2 suites.
- `git diff --check` passed.
- `./scripts/package_app.sh` installed the packaged build at `/Applications/Mudsnote.app`.
- Installed-app side-by-side QA confirmed both dark circular buttons, no visible rim, and no movement of the note-list title or split-view dividers.
- Final comparison: `/tmp/mudsnote-visual-qa-middle-buttons-final-20260710/apple-notes-vs-mudsnote.png`.

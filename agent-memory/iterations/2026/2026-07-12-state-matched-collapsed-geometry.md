# State-matched collapsed Notes geometry

## Baseline

- Started from `417b682 Keep library navigation off the main thread`.
- Preserved the unrelated iOS UI-test worktree change.

## Evidence

- The supplied collapsed Apple Notes screenshot is a `608x584px`, `2x` crop representing `304x292pt`.
- The old harness compared collapsed Mudsnote against an expanded full-window reference, so it could not establish toolbar or pane geometry.
- Same-region comparison measured the Notes content-list boundary near `200pt`, while Mudsnote still used a `220pt` default.

## Change

- Added `docs/visual-qa/apple-notes-collapsed-reference.png` and automatic state-aware reference routing.
- Cropped collapsed Mudsnote captures to the reference's point dimensions before stitching.
- Tightened the note-list default and minimum width to `200pt`; layout migration version 4 replaces only untouched `220pt` pane defaults.
- Added native `NSBox.separator` titlebar-bottom lines to the note-list and editor panes.
- Replaced the oversized collapsed bordered toolbar item with a fixed `30x30pt` `NSGlassEffectView` and retained a plain `30pt` expanded button.
- Hid collapsed source-only chrome and shifted only the collapsed title content `24pt` into AppKit's reserved toolbar safety area.

## Verification

- Focused shell, migration, and split-layout tests passed during iteration.
- Expanded comparison: `/tmp/mudsnote-expanded-compact-list-155/apple-notes-vs-mudsnote.png`.
- Final collapsed comparison: `/tmp/mudsnote-collapsed-title-155/apple-notes-vs-mudsnote.png`.
- Full tests, packaging, signing, and installed-app checks are recorded by the completion commit.

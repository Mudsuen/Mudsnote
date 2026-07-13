# Reference-Aligned Source Toolbar

## Request

Continue the Apple Notes parity goal while keeping the app lightweight and avoiding regressions in the collapsed library state.

## Baseline

- Branch: `main`
- HEAD: `a88423d`
- Dirty files before work: none

## Changes

- Wrapped Add Folder in a fixed `68pt` toolbar view with its `30pt` button trailing-aligned.
- This moves Add Folder and Sidebar Toggle together without adding a spacer item to the toolbar.
- Reduced the editor-tools glass group from `184pt` to `155pt` and each of its five button tracks from `35pt` to `31pt`.
- Kept the established collapsed title offset and source-control visibility behavior unchanged.

## Verification

- Focused library-window layout test passed.
- Full `swift test` passed.
- `git diff --check` passed.
- Repackaged and launched `/Applications/Mudsnote.app`.
- Strict code-sign verification passed.
- Expanded side-by-side capture: `/tmp/mudsnote-toolbar-final6-174/apple-notes-vs-mudsnote.png`.
- Expanded raw capture placed Add Folder at about `149pt` versus the `148pt` reference and Sidebar Toggle at about `190pt` versus the `191.5pt` reference, with no overflow chevron.
- A later collapsed crop had an invalid horizontal capture origin and was not used as alignment evidence; state and visibility regressions remain covered by the library-window test.

## Decisions

- Do not use invisible standalone toolbar items for visual spacing; they alter AppKit overflow behavior.
- Do not dynamically change custom toolbar-item widths during source collapse; AppKit can reorder or mismeasure the toolbar.

## Next

- Repair the collapsed visual-QA crop origin before using that harness for further collapsed-state pixel tuning.

# Compact Notes pane proportions

## Baseline

- Started from `8d360bb Align toolbar ownership with Notes`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Reduced default source and note-list panes from `250/250pt` to `220/220pt` after corrected point-scale comparison with Apple Notes.
- Reduced source-row and note-table content widths by the same `30pt` so internal geometry remains exact.
- Advanced the layout scale to version 3 and replaced only persisted widths still matching the old `250pt` defaults; manually resized panes remain untouched.
- Added core migration coverage and updated shell geometry assertions.

## Verification

- Focused layout and migration tests passed.
- Expanded comparison is stored at `/tmp/mudsnote-compact-panes-expanded-150/apple-notes-vs-mudsnote.png`.
- Collapsed comparison is stored at `/tmp/mudsnote-compact-panes-collapsed-150/apple-notes-vs-mudsnote.png`.
- Both states showed complete source labels, counts, list metadata, selected cards, toolbar controls, and scrollbars without overlap.
- Installed-app migration advanced the real defaults domain to version 3, preserved the customized `244pt` source pane, and replaced the old note-pane default with `220pt`.
- Final full-suite, packaging, signing, and installed-app checks are recorded in the completion commit.

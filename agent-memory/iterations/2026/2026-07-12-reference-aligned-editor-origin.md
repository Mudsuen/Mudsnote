# Reference-aligned editor origin

## Baseline

- Started from `10eb3b1 Tighten Notes pane proportions`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Increased the editor safe-area top inset from `12pt` to `18pt` so the centered date aligns with Apple Notes.
- Increased date-to-title spacing from `30pt` to `34pt` so the title origin aligns independently without pushing the date lower.
- Updated the shared shell regression assertions.

## Verification

- Focused library shell testing passed.
- Empty-state comparison is stored at `/tmp/mudsnote-editor-top-empty-151/apple-notes-vs-mudsnote.png`.
- Final content-state comparison is stored at `/tmp/mudsnote-editor-rhythm-content-151/apple-notes-vs-mudsnote.png`.
- The date and title origins align with the state-matched Notes reference without clipping or overlap.
- Final full-suite, packaging, signing, and installed-app checks are recorded in the completion commit.

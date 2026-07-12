# State-matched editor visual QA

## Baseline

- Started from `e78337f Keep the first note below its group header`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Made the visual QA fixture choose its matching checked-in Apple Notes reference by default while retaining the explicit reference override.
- Recalibrated content date-to-title spacing to `30pt` using the actual content-state comparison.
- Added a regression assertion for the measured layout contract.

## Verification

- `bash -n scripts/visual_notes_qa.sh` passed.
- Content fixture routing reported `docs/visual-qa/apple-notes-content-reference.png`.
- Focused library layout testing passed.
- External-display content comparison is stored at `/tmp/mudsnote-content-rhythm-148/apple-notes-vs-mudsnote.png`.
- Final full-suite, packaging, signing, and installed-app checks are recorded in the completion commit.

# 2026-07-10 note selection tone

## Request

Continue the Apple Notes parity goal without changing the compact toolbar or window geometry. Keep color work proportional to its product impact rather than pursuing exact pixel parity.

## Baseline

- Branch: `main`
- HEAD before work: `29bcddd Extract library note list projection`
- Dirty files before work: none
- Apple Notes reference: `docs/visual-qa/apple-notes-reference.png`
- Packaged Mudsnote baseline: `/tmp/mudsnote-visual-qa-content-clean-20260710/mudsnote-library.png`

## Changes

- Shifted the selected note card from a brighter pure gold to a quieter, lower-saturation warm gold.
- Kept note selection behavior, row geometry, toolbar sizing, window sizing, and Markdown data unchanged.
- Updated the selected-row semantic-color regression assertions.
- Did not add a selection-race workaround: the earlier `knock` selection in the supplied screenshot was a manual user click, not an application defect.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test` with 107 tests.
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-selection-tone-final-20260710`
- Packaged visual sample moved from roughly `RGB 164/130/0` to `RGB 158/129/38`, close enough in tone to the Apple Notes reference sample near `RGB 158/129/32` without further micro-tuning.

## Decisions

- Treat selection color as visually aligned and move on to larger UI, editing, and responsiveness gaps.
- Preserve the existing visual-QA selection path and normal user selection behavior.

## Next

- Prioritize higher-impact Apple Notes parity work over exact color matching.

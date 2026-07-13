# 2026-07-13 linear post-save snapshot

## Request

Continue Apple Notes parity while improving Mudsnote architecture and large-library performance without changing the accepted UI.

## Baseline

- Branch: `main`
- HEAD: `2372426`
- Dirty files before work: concurrent iOS companion files, left untouched

## Changes

- Added `LibraryNoteListProjection.upsertByModifiedDate` for ordered library-snapshot mutation.
- Replaced post-save `removeAll + append + sort` with path removal, binary insertion, and one limit trim.
- Moved URL normalization out of the `10,000`-entry loop by passing raw and standardized old/new paths from the save boundary.

## Verification

- Focused ordering, replacement, autosave, and date-group tests passed.
- The first prototype measured about `60ms` because it standardized every existing URL.
- After boundary normalization, the `10,000`-entry debug performance test passed its `<50ms` gate three consecutive times.
- Full `swift test` passed.
- `/Applications/Mudsnote.app` was packaged and `scripts/library_smoke.sh` passed.
- `codesign --verify --deep --strict /Applications/Mudsnote.app` passed.
- Collapsed visual QA passed at `/tmp/mudsnote-visual-qa-202-collapsed/apple-notes-vs-mudsnote.png` with no layout regression.

## Decisions

- Keep the immediate visible-row projection synchronous because it is bounded to 240 notes; optimize the larger `10,000`-entry source snapshot mutation instead.
- Preserve the descending modified-date invariant and update it incrementally rather than adding another task or cache.
- Normalize paths at mutation boundaries, not inside large-array loops.

## Next

- Audit synchronous Markdown serialization and file writes in the autosave path, then continue complex editor-content parity.

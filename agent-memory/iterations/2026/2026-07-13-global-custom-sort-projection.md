# 2026-07-13 global custom sort projection

## Request

Continue Mudsnote toward Apple Notes UI and workflow parity while keeping large-library architecture lightweight and performant.

## Baseline

- Branch: `main`
- HEAD: `f935546`
- Dirty files before work: concurrent iOS companion changes only; macOS and documentation files were clean.

## Changes

- Added a chunked top-K projection for title and creation-date sorting across the complete selected scope.
- Kept working memory bounded to at most twice the 240-note visible limit rather than allocating or fully sorting all 10,000 notes.
- Precomputed pinned and date-group keys once per scanned note so sort comparisons remain cheap.
- Reprojected empty-query lists from the loaded snapshot whenever sort or grouping options change.
- Preserved the early-stop modified-date path introduced in the previous iteration.
- Made the installed smoke wait within a bounded window for the autosaved file; the previous immediate check could report failure before the `800ms` debounce completed, even though cleanup later persisted the note.
- Added `AXPress` to native source cells and updated smoke navigation to the current outline-cell semantic instead of the removed custom-button role.
- Explicitly activates the existing installed app with `open` before smoke keyboard events; this is reliable across the current multi-display/Space setup where AppleScript activation alone can leave another app frontmost.

## Verification

- Commands run: focused pure projection tests, focused 241-file controller integration, `swift test`, `bash -n scripts/library_smoke.sh`, `./scripts/package_app.sh`, `codesign --verify --deep --strict /Applications/Mudsnote.app`, and `./scripts/library_smoke.sh /tmp/mudsnote-library-smoke-211-final`.
- App/page/package actually opened: `/Applications/Mudsnote.app` ran against the isolated smoke library and was relaunched for attachment verification.
- Result: all 159 tests passed; the 10,000-note grouped-title debug projection stayed below `100ms`; production packaging and strict signing passed; the installed smoke passed autosave, search, trash, native source `AXPress`, restore, folder move, file attachment paste, portable Markdown storage, and post-relaunch rendering.
- Not verified: no new visual comparison was needed because list geometry, color, typography, and toolbar rendering are unchanged.

## Decisions

- Apply the visible result limit after global ordering for non-default sorts.
- Use bounded chunk compaction rather than a new persistent sort index; this keeps mutation and persistence architecture simple while making source changes immediately visible.
- Keep search relevance projection separate because search must rank its complete indexed candidate set.

## Next

- Continue Apple Notes parity from current same-state visual evidence; keep custom-sort projection behavior covered when list functionality changes.

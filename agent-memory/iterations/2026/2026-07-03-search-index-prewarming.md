# 2026-07-03 - Search Index Prewarming

## Context

The library window already used a lightweight in-memory Markdown index for search, tags, and note list metadata. The remaining performance gap was that the first tag/search path could still build the index on demand.

## Change

- Added `NoteStore.prewarmSearchIndex(roots:)` as an explicit cache warmup API.
- Changed deferred library tag loading to run on a utility queue.
- The deferred path now prewarms the search index, reads the first 12 tags from the warmed snapshot, then publishes tag rows back on the main thread.
- Kept the index in memory and signature-based so Markdown files remain the only source of truth.
- Added regression coverage that prewarming builds a reusable snapshot and preserves search/tag behavior.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation was intentionally excluded from this macOS Notes-parity iteration.

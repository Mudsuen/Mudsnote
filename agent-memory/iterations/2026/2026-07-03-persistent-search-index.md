# 2026-07-03 Persistent Search Index

## Context

The Notes-like library already prewarmed an in-memory Markdown index for search, tags, and All Notes. Relaunching the app still rebuilt that snapshot from source files, which is unnecessary work for large local-first libraries whose Markdown files have not changed.

## Change

- Added `NoteStore.searchIndexCacheURL` under App Support.
- Made search index snapshots, file signatures, and entries codable.
- Added a versioned JSON disk cache for the lightweight search index.
- Load the disk cache only when the root set and all file signatures match exactly.
- Delete corrupt cache files and rebuild from Markdown files without surfacing an error to the user.
- Keep Markdown files as the only source of truth; the cache is disposable acceleration data.

## Verification

- Focused search-index tests passed for in-memory refresh, prewarming, disk persistence, stale-file refresh, and corrupt-cache rebuild.
- `swift test` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app direct launch smoke opened `Mudsnote 笔记` at `1420x860`.
- Visual QA generated `/tmp/mudsnote-visual-qa-persistent-search-index/apple-notes-vs-mudsnote.png`.

## Follow-up

- Add editor-side match highlighting for search navigation.
- Add richer loading/refresh states for very large libraries.

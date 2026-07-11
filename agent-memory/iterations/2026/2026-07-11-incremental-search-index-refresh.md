# 2026-07-11 Incremental search-index refresh

## Baseline

- Started from `c617638` with the macOS thumbnail iteration already installed.
- Search snapshots were versioned and persisted, but any signature-map difference caused every Markdown file to be reparsed.

## Implementation

- Accept a same-root memory or disk snapshot as a reusable baseline even when its complete signature map is stale.
- Match entries by standardized path and modification-date-plus-size signature.
- Reparse only files without an unchanged reusable entry; removed files disappear because the new snapshot is projected from the current filesystem enumeration.
- Preserve corrupt-cache recovery and atomic snapshot persistence.

## Verification

- Added `searchIndexRefreshReadsOnlyChangedMarkdownFiles` covering both in-memory refresh and a new `NoteStore` loading a stale disk snapshot.
- In a three-note fixture, each one-note mutation produced exactly one Markdown content read while unchanged notes remained searchable.
- Focused search-index tests: 3 passed.
- Full Swift suite: 120 tests passed.
- `git diff --check`: passed.
- Production package installed at `/Applications/Mudsnote.app`; strict deep code-sign verification passed before the final dead-code cleanup and was rerun afterward.

## Lesson

- Namespace validation and content parsing are separate costs. Keep cheap file signatures authoritative for freshness, but do not discard reusable parsed content when one record changes.

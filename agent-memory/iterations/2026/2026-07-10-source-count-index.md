# 2026-07-10 source count index

## Request

Continue Apple Notes UI parity while making large-library refresh architecture as efficient as practical.

## Baseline

- Branch: `main`
- HEAD before work: `a29e50a Avoid parsing trash for source counts`
- Dirty files before work: none
- Confirmed hotspot: source counts filtered the full note snapshot independently for Inbox, every visible folder, and every visible tag.

## Changes

- Added `LibrarySourceCountIndex`, built with one pass over the current in-memory note snapshot.
- Aggregated Inbox matches, case-insensitive tag counts, and folder counts by walking each note's directory ancestors.
- Preserved parent-folder rollups for notes stored in nested folders.
- Deduplicated case variants of the same tag within one note before incrementing counts.
- Replaced per-source full-array filters with constant-time index lookups.

## Verification

- Added a focused count-index test covering Inbox, nested folder rollups, and case-insensitive per-note tag deduplication.
- Passed existing deferred tag, nested-folder, and empty-folder count tests.
- Passed full `swift test`: 105 tests.
- Passed `git diff --check`.
- Passed `./scripts/package_app.sh`; installed `/Applications/Mudsnote.app`.
- Packaged-app accessibility smoke confirmed the normal library and its All iCloud, Notes, Recently Deleted, and tag counts remain visible and correct.

## Decisions

- Source-count computation should scale with notes and directory depth, not notes multiplied by the number of visible sources.
- Keep aggregation on the existing in-memory snapshot; do not add file reads or a second persistence layer for counts.

## Next

- Audit whether count-index construction should move onto the existing background snapshot task for very large libraries.
- Continue visual work from canonical side-by-side evidence rather than changing stable geometry speculatively.

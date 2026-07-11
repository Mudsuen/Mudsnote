# 2026-07-11 Stable scoped search index

## Baseline

- Started from `57afcb4` after native main-menu and new-note command routing.
- The search index supported arbitrary roots, but the library's folder search used that flexibility in a way that replaced the full-library memory and disk snapshot.

## Problem

- A folder search changed `searchIndexSnapshot.rootsKey` to one directory and wrote that reduced snapshot over the persistent full-library cache.
- Tag and Inbox searches requested only the global top `limit` results and filtered afterward, so a valid scoped result could be omitted when unrelated notes ranked higher.

## Implementation

- Added core directory, exact-tag, and Inbox search entry points.
- Each entry point obtains the full-library indexed entries, applies its predicate, then ranks and limits the scoped set.
- Updated `librarySearchResults` to use the scoped APIs; trash and recent-note behavior remain separate.
- Empty scoped queries also return the most recently modified matching entries without changing index roots.

## Verification

- Added `scopedSearchFiltersBeforeLimitingAndPreservesFullLibraryIndexRoots`.
- The test places higher-ranked matching notes outside the target scopes, requests `limit: 1`, and still receives the correct directory, tag, and Inbox results.
- The same test confirms `searchIndexSnapshot.rootsKey` remains the original full-library roots and all six notes remain available afterward.
- Focused search tests: 3 passed.
- Full Swift suite: 122 tests passed.
- `git diff --check`: passed.
- Production package installed at `/Applications/Mudsnote.app`; strict deep code-sign verification passed.

## Lesson

- Scope should narrow candidates inside a stable index. Rebuilding index ownership around every visible source causes avoidable disk churn and makes result limiting semantically wrong.

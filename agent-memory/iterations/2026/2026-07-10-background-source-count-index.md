# 2026-07-10 background source count index

## Request

Continue Apple Notes parity while keeping large-library startup and refresh work off the main thread where practical.

## Baseline

- Branch: `main`
- HEAD before work: `5f5d7fb Aggregate library source counts once`
- Dirty files before work: none
- The full note snapshot already loaded on a background queue, but `LibrarySourceCountIndex` was still constructed after returning to the main queue.

## Changes

- Marked the immutable source-count index as `Sendable`.
- Captured the current visible folder-path set before starting full-library hydration.
- Built the count index beside `listNotes` on the existing user-initiated background task.
- Passed the precomputed index through search and normal reload paths.
- Reused the background index only when the current folder-path set still matches the captured set; otherwise the controller rebuilds from current state.

## Verification

- Passed focused deferred-first-note, deferred-plain-Markdown, and deferred-tag-loading tests.
- Passed full `swift test`: 105 tests.
- Passed `git diff --check`.
- Passed `./scripts/package_app.sh`; installed `/Applications/Mudsnote.app`.
- Packaged-app accessibility smoke confirmed the normal library, source counts, note list, and editor still load.
- Re-ran content-state visual QA after the user clarified that the earlier note switch was manual; the requested `lz 合集` fixture remained selected without code changes.

## Decisions

- Pure snapshot-derived indexes should be built on the snapshot worker, not on the main queue.
- Background results that depend on UI-owned folder state require an equality check before reuse.
- Do not change editor geometry without a content reference that supports the specific adjustment.

## Next

- Continue auditing synchronous `reloadNotes` calls that rebuild the all-note snapshot after user actions.
- Keep visual changes grounded in the supplied Apple Notes screenshots and canonical captures.

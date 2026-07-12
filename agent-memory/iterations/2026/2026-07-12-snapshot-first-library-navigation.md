# Snapshot-first library navigation

## Baseline

- Started from `38e0bb9 Remove drag-time library scans`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Removed the empty-snapshot fallback that synchronously called `listNotes(limit: 10_000)` from ordinary library reloads.
- UI navigation now paints from the current snapshot and schedules the existing cancellable, generation-guarded background validation pass.
- Kept the intentionally synchronous non-deferred constructor path explicit for tests and tooling; the installed app uses deferred hydration.
- Added immediate snapshot maintenance for note save, move, trash, restore, folder rename, and folder deletion, including moved thumbnail paths.
- Added stable source-button identifiers and a regression test proving source navigation returns before a newly discovered Markdown file arrives through background refresh.

## Verification

- The focused snapshot-navigation test passed.
- Folder lifecycle and trash/restore focused tests passed after mutation consistency coverage exposed and fixed stale-path cases.
- The full Swift test suite passed.
- Release packaging installed `/Applications/Mudsnote.app`, and strict deep signature verification passed for `local.codex.mudsnote` with Team ID `3JA29GL46S`.
- Content-state visual QA completed at `/tmp/mudsnote-snapshot-navigation-154/apple-notes-vs-mudsnote.png`, also closing the iteration-152 lock-screen verification gap.

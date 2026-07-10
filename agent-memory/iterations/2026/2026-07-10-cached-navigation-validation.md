# 2026-07-10 cached navigation validation

## Request

Continue the lightweight Apple Notes parity goal by prioritizing visible responsiveness and core behavior over exact color matching.

## Baseline

- Branch: `main`
- HEAD before work: `3440216 Soften note selection tone`
- Dirty files before work: none
- Source, folder, tag, recent-note, and empty-search reloads could synchronously call `NoteStore.listNotes(limit:)` on the main actor.
- `listNotes` validates the filesystem-backed index by enumerating Markdown files and reading signatures, so repeated navigation could block the interface on larger libraries.

## Changes

- Added a cache-first navigation reload path using the controller's existing full-library snapshot.
- Source, folder disclosure, deferred folder/tag loading, recent-note navigation, and empty-search restoration now rebuild the list immediately from memory.
- Added a cancellable, generation-guarded background validation pass that refreshes the list and source counts only when the current navigation state still matches.
- Added an `80ms` coalescing delay so rapid source changes cancel before starting redundant filesystem scans.
- Normal reloads, saves, and window close cancel pending validation, preventing stale background results from replacing newer state.
- Saves update the in-memory snapshot immediately with the new title, snippet, tags, attachments, thumbnail, URL, and modification date.

## Verification

- Passed targeted navigation, autosave, source-folder, search, and external-file tests.
- Added regression coverage proving the cached list is synchronously available and an externally added Markdown file appears after background validation.
- Extended autosave coverage to prove a saved body snippet is immediately available through cached navigation.
- Passed: `swift test` with 108 tests.
- Passed: `git diff --check`.
- Passed: `./scripts/package_app.sh` and installed `/Applications/Mudsnote.app`.
- Installed-app AX smoke passed for `Notes -> #dragsmoke -> All iCloud`, preserving the selected note and editor content.
- Installed-app search smoke returned `5 results` for `smoke`; clearing the query immediately restored the full list.

## Decisions

- Preserve external Markdown visibility through background index validation rather than keeping an indefinitely stale controller cache.
- Keep mutation paths authoritative: local saves update the snapshot immediately, while move, delete, restore, and folder actions retain their normal full reloads.
- Do not add filesystem watchers in this pass; the cache-first plus validated-refresh model removes navigation stalls with substantially less runtime complexity.

## Next

- Continue with higher-impact editing and attachment parity, or deeper toolbar/source hierarchy tuning where side-by-side evidence shows a clear mismatch.

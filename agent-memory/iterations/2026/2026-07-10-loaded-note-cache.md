# Loaded Note Cache

## Scope

- Baseline: `1db5a03 Align Notes source row geometry`
- Keep editor output, file-backed freshness, autosave, attachments, search highlights, and selection behavior unchanged.
- Reduce repeated disk reads and full Markdown-to-attributed-text rendering during note-list navigation.

## Implementation

- Added a bounded 32-entry loaded-note cache keyed by standardized Markdown path.
- Cache hits validate the current filesystem modification date before reuse.
- Attachment-free notes retain their rendered attributed body; attachment notes rerender to avoid stale previews.
- Adjacent notes are prefetched on a utility queue after selection.
- Saving an existing note invalidates its cache entry before writing.

## Verification

- Six targeted cache, external-change invalidation, keyboard navigation, autosave, search-highlight, attachment-tool, and visual-selection checks passed.
- Full `swift test` passed: 103 tests in 2 suites.
- Production build emitted no concurrency warnings.
- `git diff --check` passed.
- `./scripts/package_app.sh` installed the packaged build at `/Applications/Mudsnote.app`.
- Installed-app content-state QA output was byte-identical before and after the optimization: SHA-256 `34d404f4bace33009c02d7ca69416242c20f59c7f06170ce79d7c5e5e5f19d60`.
- Final comparison: `/tmp/mudsnote-visual-qa-loaded-note-cache-20260710/apple-notes-vs-mudsnote.png`.

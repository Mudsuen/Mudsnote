# 2026-07-02 Lightweight search index

## Context

The Apple Notes parity roadmap still listed search indexing as a known gap. Search, tags, and note-list metadata all repeatedly parsed Markdown files from disk, which is acceptable for tiny libraries but does not move toward Notes-grade retrieval speed.

## Change

- Added a lightweight in-memory search index to `NoteStore`.
- Index entries cache title, body, lowercase body, tags, snippet, attachment state, thumbnail URL, and modified date.
- The index is keyed by standardized search roots and per-file signatures.
- File signatures use modification date and file size, so editing a Markdown file refreshes cached search/tag/list results.
- `knownTags`, `listNotes`, and non-empty `searchNotes` now share the same parsed entries.
- The index snapshot is protected by a narrow `NSLock` because `NoteStore` is `@unchecked Sendable`.
- Added regression coverage for cache refresh after a Markdown file changes.

## Verification

- `swift test --filter 'searchFindsNotesAcrossKnownRoots|searchIndexRefreshesWhenMarkdownFileChanges|tagsRoundTripAndKnownTagsAreCollected|listNotesReturnsAllKnownMarkdownFilesByModifiedDate'` passed.
- `swift test` passed with 78 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.

# 2026-07-08 Notes root folder title

## Request

Continue the Apple Notes parity goal after user feedback that the earlier toolbar pass looked closer to Apple Notes, especially the compact editor-tools capsule without an obvious white rim.

## Baseline

- Branch: `main`
- HEAD before work: `7a75818 Soften Notes list hover state`
- Dirty files before work: none
- Visual reference: keep the earlier `a925b48 Remove Notes toolbar capsule rim` direction for the toolbar while continuing lightweight UI parity work.

## Changes

- Kept the current borderless compact editor-tools toolbar direction as the visual baseline instead of reintroducing a brighter capsule outline.
- Changed the default Markdown root display name to `Notes` when the backing folder is the configured notes directory, even if the real filesystem folder is named `Mudsnote`.
- Applied the same display-name normalization to the source list, note-list header, note metadata, and move-to-folder menu.
- Added regression coverage so the root folder still maps to the real URL while visible labels match Apple Notes.
- Updated the parity roadmap to record the compact borderless toolbar and root `Notes` naming constraints.

## Verification

- Commands run before final verification:
  - `swift test --filter 'MarkdownRichEditorTests/librarySourceListDisplaysDefaultNotesFolderLikeAppleNotes|MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryWindowShowsNestedFoldersInSourceList|MarkdownRichEditorTests/libraryWindowSharesExportsAndDeletesMultipleSelectedNotes'`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-notes-root-folder-title-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Final verification:
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-notes-root-folder-title-verified`
- Result:
  - Full `swift test` passed with 92 tests.
  - `git diff --check` passed.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-notes-root-folder-title-verified/apple-notes-vs-mudsnote.png`.
  - Installed app refreshed at `/Applications/Mudsnote.app`.

## Decisions

- Treat the earlier compact toolbar scale and `a925b48` borderless capsule as the closer Notes-like baseline.
- Do not rename or move the user's real notes folder; this is a display normalization only.

## Next

- Continue closing visible shell deltas: toolbar horizontal placement, note-list sample-state parity, source-sidebar hierarchy rhythm, and editor empty/loading states.

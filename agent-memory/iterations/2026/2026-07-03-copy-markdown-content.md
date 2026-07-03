# 2026-07-03 - Copy Markdown Content From Library

## Context

The library toolbar had a Notes-like export button and more-actions menu, but the available destinations were still mostly file-oriented: reveal in Finder, copy path, and export a separate Markdown file. For a local-first Markdown app, copying the selected note's full Markdown is a lightweight share destination that works across other apps without adding heavier share infrastructure.

## Change

- Added `复制 Markdown 内容` to the library more menu and note context menu.
- The action saves pending edits when needed, reads the selected Markdown file, and places the full Markdown on the pasteboard.
- Kept the action disabled for the trash scope, matching existing export behavior.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter 'libraryToolbarUsesNotesLikeDisabledStates|libraryWindowDeletesRestoresAndPermanentlyDeletesNotes'` passed.
- `swift test` passed: 82 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke passed: `open -n /Applications/Mudsnote.app --args --library` produced one on-screen `Mudsnote 笔记` window at 1420x860.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-copy-markdown` passed and wrote `/tmp/mudsnote-visual-qa-copy-markdown/apple-notes-vs-mudsnote.png`.

## Remaining Product Delta

- This adds a lightweight share destination, but full system share-sheet style destinations and richer export formats remain future Notes-parity work.

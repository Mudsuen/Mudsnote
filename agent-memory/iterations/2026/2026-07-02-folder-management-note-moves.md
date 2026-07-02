# 2026-07-02 folder management and note moves

## Request

Continue toward full Apple Notes parity for the macOS library while keeping Mudsnote local-first and lightweight.

## Baseline

- Branch: main
- HEAD: 07bccbc
- Dirty files before work: none

## Changes

- Added `NoteStore` APIs to:
  - create folders under the local notes directory or selected folder
  - rename preferred folders and keep recent-file metadata in sync
  - move notes between local folders without duplicating same-folder moves
  - delete folders by moving their Markdown contents into the local Trash
- Changed new-note save behavior so a new note created while a folder is selected saves into that folder.
- Added a move-to-folder toolbar action.
- Added folder context actions for rename and delete.
- Added note-list context actions for move and delete.
- Kept folder behavior filesystem-backed; the app still manages plain `.md` files and local directories.

## Verification

- `swift test` passed with 63 tests.
- `git diff --check` passed.
- XcodeBuildMCP `build_sim` passed for `MudsnoteCompanion` on the configured iPhone 17 simulator.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged smoke launched `/Applications/Mudsnote.app` and showed a visible `Mudsnote 笔记` window at `1040x764`.
- Visual QA screenshot: `/tmp/mudsnote-window-folder-management-final.png`
- `./scripts/device_smoke.sh` still reports `MudsPhone` as paired but unavailable to CoreDevice with local Xcode 26.5 / iPhoneOS SDK 26.5.

## Decisions

- Treat folders as real filesystem directories.
- Folder deletion moves contained Markdown files into the existing Mudsnote Trash path rather than permanently deleting files.
- The default notes directory cannot be deleted from the folder context menu.

## Next

- Recheck whether the iPhone is available to CoreDevice for real-device install.
- Continue P1 with keyboard/context-menu polish and folder hierarchy disclosure.
- Continue P2 with formatting/checklist/table/attachment toolbar parity.

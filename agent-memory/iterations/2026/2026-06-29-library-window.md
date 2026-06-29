# 2026-06-29 lightweight library window

## Request

Use the current product goal as the ongoing iteration target: keep Mudsnote lightweight, evolve the macOS app toward a Notes-like editor, and continue optimizing iOS for fast capture.

## Baseline

- Branch: main
- Dirty files before work: none from `git status --short`

## Changes

- Added `NoteStore.listNotes(limit:roots:)` to list all known Markdown files by modified date while leaving the existing empty-search recent behavior unchanged.
- Added `LibraryWindowController`, a standard split-view macOS window for the desktop Notes-like path:
  - source-list sidebar
  - search field
  - title field
  - rich Markdown body editor
  - save action
  - separate-window handoff for the selected note
- Added a status-menu `笔记库` entry and `--library` launch argument.
- Added core and app tests for the all-notes list API and the library window loading path.
- Kept quick capture and floating-note behavior separate from the new desktop library window.

## Verification

- `swift test` passed with 57 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged app smoke launched `/Applications/Mudsnote.app --args --library`.
- Process check confirmed the installed app binary ran. The extra `--library` smoke process was closed afterward, leaving the pre-existing resident Mudsnote process.

## Decisions

- The Notes-like desktop surface is a standard resizable window, not another translucent quick-capture panel.
- Main-window opacity ignores panel opacity settings so the library remains a stable editing workspace.
- Quick capture remains the fastest entry point; the library window is for browsing, reviewing, and continuing notes.

## Next

- Add lightweight metadata actions to the library sidebar: pinned/recent grouping, tags, folder filters, and Finder/copy actions.
- Improve main-window editing ergonomics before adding any heavier indexing layer.
- Continue with the iOS quick-capture slice: default target behavior, continuous-save flow, and real-device voice/widget/Shortcuts verification.

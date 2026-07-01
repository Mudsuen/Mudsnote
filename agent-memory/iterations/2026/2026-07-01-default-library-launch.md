# 2026-07-01 default library launch

## Request

Make direct opening of Mudsnote show the Notes-like library window instead of only showing a floating capture surface or menu bar presence.

## Baseline

- Branch: main
- HEAD: c1f8c8d
- Dirty files before work: existing uncommitted Mudsnote iteration files for the modern iOS icon, three-column library, device smoke hardening, and their records.

## Changes

- Changed `AppController` so ordinary launches without an explicit launch surface open the library window by default.
- Preserved explicit launch modes for quick capture, floating note, search, preferences, and library.
- Added app reopen handling so opening the already-running app also brings up the library window.
- Added a regression test for the launch-surface decision.

## Verification

- `swift test` passed with 58 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged app smoke launched a new no-argument instance with `open -n /Applications/Mudsnote.app`.
- System Events confirmed the no-argument test instance opened a window named `Mudsnote 笔记`.
- The no-argument smoke process was closed afterward, leaving the pre-existing resident Mudsnote process running.

## Decisions

- The Notes-like library is now the default desktop identity for direct app launch.
- Quick capture and floating note remain explicit fast-entry surfaces through menu items, hotkeys, or launch arguments.

## Next

- If the user wants direct reopen of an already-running resident instance tested further, verify it after quitting the older resident process so the packaged build is the only active instance.

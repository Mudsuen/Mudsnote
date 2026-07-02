# 2026-07-02 Notes shell header density

## Request

Continue the full Apple Notes parity goal for the macOS library UI.

## Baseline

- Branch: main
- HEAD: 67e21bb
- Dirty files before work: none

## Changes

- Hid the visible window title while keeping the system title string for window identity.
- Made the titlebar transparent to reduce custom app chrome in the Notes-like main window.
- Reduced the middle note-list column width from `320` to `288`.
- Replaced the large source-list `资料库` heading with compact group labels.
- Added a scope-aware note-list title and count/result line.
- Reduced the selected note card corner radius from `10` to `7`.
- Added regression coverage for the hidden titlebar, source group label, and note-list title/count state.

## Verification

- `swift test` passed with 65 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` with no arguments and showed `Mudsnote 笔记` at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-notes-shell-header-density-window.png`.

## Decisions

- Kept local labels such as `Mudsnote` and `所有笔记` instead of claiming iCloud behavior.
- Treated this as P0 shell work; no storage, sync, or editor data-model changes were introduced.

## Next

- Run package and installed-app smoke.
- Continue with side-by-side visual tuning: source-list hierarchy, note-list row density, editor date/title spacing, and toolbar disabled states.

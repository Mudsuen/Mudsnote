# 2026-07-02 collapsible folder disclosures

## Request

Continue the remaining macOS Apple Notes parity work after dropping iOS real-device verification from the goal.

## Baseline

- Branch: main
- HEAD: 13ff846
- Dirty files before work: none
- iOS real-device install/smoke remains outside the active working scope.

## Changes

- Added chevron disclosure buttons for source-list folders with children.
- Folder trees default to expanded and can be collapsed or re-expanded in the current session.
- Collapsing a parent while a child folder is selected moves the active scope back to the parent.
- Expanded app regression coverage for nested folder collapse and re-expand behavior.

## Verification

- `swift test` passed with 66 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` with no arguments and showed `Mudsnote 笔记` at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-folder-disclosure-window.png`.

## Decisions

- Collapse state is session-local for now; no preference or metadata file was added.
- This builds directly on the filesystem-backed folder rows, preserving the local-first Markdown boundary.

## Next

- Continue with editor title/date spacing, toolbar disabled states, keyboard navigation, and attachment indicators.

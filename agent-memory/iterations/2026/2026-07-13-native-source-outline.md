# 2026-07-13 native source outline

## Goal

Move the macOS library sidebar toward Apple Notes' native implementation model while keeping Mudsnote local-first and lightweight.

## Changes

- Replaced the custom source-button stack with `NSOutlineView` using `.sourceList` style.
- Moved folder hierarchy disclosure, keyboard traversal, row reuse, scrolling, selection, inline folder editing, context menus, and drag/drop onto AppKit.
- Preserved snapshot-first source counts and incremental folder create/rename/delete projections; deferred filesystem validation remains off the main actor.
- Kept the existing Notes-matched sidebar material, compact row metrics, inset selection surface, tags, Recently Deleted, and local Markdown scopes.
- Serialized the AppKit test suite because its tests share `NSApp`, window focus, and the system pasteboard.

## Verification

- `swift test`: 154 tests passed in 2 suites.
- The 600-folder virtualization regression instantiates fewer than 40 visible outline cells.
- `./scripts/package_app.sh`: passed and installed `/Applications/Mudsnote.app` with a valid signature.
- Direct CGWindow inspection confirms the installed library window is on screen.
- The installed accessibility smoke and visual capture were not usable in this background session: unchanged Mudsnote and Apple Notes both returned zero System Events windows, while window-only capture produced black pixels. This is host/session evidence, not an outline-specific failure.

## Scope

The macOS base entering this iteration was `38c57b1`; concurrent iOS commits advanced `main` during the work. iOS source changes were not staged or modified by this iteration.

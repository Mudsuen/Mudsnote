# 2026-05-08 settings and toolbar formatting

## Request

- Change Settings to a standard macOS preferences-style window and plan the settings page structure.
- Fix toolbar inline formatting that could fail on repeated actions against the same selected text.
- Make toolbar formatting changes participate in `cmd+z`.

## Baseline

- Branch: main
- HEAD: d2af8b1
- Dirty files before work: none.

## Changes

- Replaced the custom glass Preferences panel with a regular titled Settings window using tabbed panes: General, Shortcuts, and Appearance.
- Added working settings controls for revealing managed folders, restoring default shortcuts, resetting panel opacity, and clearing remembered quick-capture/floating-window positions.
- Kept the Settings window fully opaque while panel opacity still previews and applies to quick capture/floating-note panels.
- Preserved toolbar target selection after each formatting action so consecutive format buttons can apply to the same selected text.
- Registered undo snapshots for programmatic formatting changes, including inline font traits, underline/strikethrough, paragraph/list toggles, and checklist toggles.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --preferences` and confirmed the packaged app process started.

## Decisions

- Settings should be organized by task area instead of one long custom panel: folders in General, key bindings in Shortcuts, and panel/window behavior in Appearance.
- Formatting toolbar actions need explicit undo registration because direct `NSTextStorage` mutations do not reliably enter the text view undo stack.

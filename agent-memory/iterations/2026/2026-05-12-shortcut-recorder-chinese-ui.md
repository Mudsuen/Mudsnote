# 2026-05-12 shortcut recorder and Chinese UI

## Request

- Change shortcut settings from typed text to recognized shortcut recording.
- Use Chinese for the app language.

## Baseline

- Branch: main
- HEAD: 68b2feb
- Dirty files before work: none.

## Changes

- Added `ShortcutRecorderButton` and `ShortcutRecordingWindow` so Settings can capture key events such as `⌥R` and `⌘↩` before normal window key-equivalent routing consumes them.
- Extended `HotKeySpec` to build shortcut specs from `NSEvent`, normalize storage strings, and show macOS-style symbols in the UI.
- Replaced the three shortcut text fields in Settings with recorder controls.
- Switched visible Mudsnote UI text to Chinese across the menu bar menu, Settings, search window, quick-capture chrome, slash commands, tag menu, alerts, and editor status labels.
- Changed the packaged app development region to Simplified Chinese.
- Kept English slash-command aliases like `h1`, `heading`, and `todo` so existing typing habits still work after Chinese command titles.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- `open -na /Applications/Mudsnote.app --args --preferences`
- `plutil -extract CFBundleDevelopmentRegion raw -o - /Applications/Mudsnote.app/Contents/Info.plist` returned `zh-Hans`.
- Confirmed packaged Settings process running as `/Applications/Mudsnote.app/Contents/MacOS/Mudsnote --preferences`.

## Decisions

- Persist shortcut strings in the existing `option+r` / `command+return` format for compatibility, while displaying captured shortcuts as symbols such as `⌥R`.
- Require a captured shortcut to include Command, Option, or Control; Shift-only shortcuts are rejected by the recorder.

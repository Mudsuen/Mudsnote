# 2026-07-19 macOS editor context menu and paint stability

## Scope

- Platform: macOS only.
- Keep iOS source and installation artifacts untouched.

## Changes

- `MarkdownTextView` now identifies trailing blank space inside a laid-out text line before asking AppKit for the native context menu, then restores the pre-click selection after native menu construction.
- Editor right-click menus retain only native Translate plus Cut, Copy, and Paste. Link, attachment, table, AI, and selection-format commands are not appended there.
- Mouse selection in the library editor immediately opens a separate shortcut menu with inline formatting, a Color submenu backed by portable `<mark>` Markdown, and a Convert To submenu for body, headings, bullet lists, numbered lists, and checklists. These actions do not live in the right-click menu.
- Search highlights are removed and reapplied inside one `NSTextStorage` edit transaction. Removing a transient search highlight restores any persisted document highlight underneath it.

## Verification contract

- Regression coverage must prove the concise menu titles, trailing-whitespace selection preservation, selection-format menu structure, highlight formatting actions, and `<mark>` rich-text round trip.
- Validate through `./scripts/verify macos pr` and then `./scripts/verify macos live`; the live flow owns `/Applications/Mudsnote.app`.

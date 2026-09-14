# macOS two-pane material hierarchy

Scope: macos only; checkpoint 57081ab was an unfinished starting point.

The pane tint and spacing choices below were superseded by the user's
2026-09-13 feedback; see 2026-09-13-macos-continuous-material-icon-navigation.md.

The user requested a slightly darker list, brighter document, professional
spacing, and smooth motion. The inspected checkpoint used two native materials
whose active/inactive behavior inverted that hierarchy in dark appearance.

- Preserve NSVisualEffectView behind the window, with a separate semantic tint
  view above it. Drawing a tint in NSVisualEffectView.draw does not reliably sit
  above AppKit's material composition. Resolve tints per appearance and make them
  opaque under Reduce Transparency.
- Keep folder/tag navigation in an anchored native popover, with explicit outline
  keyboard entry and normal Escape dismissal. New note and quick menu sit at the
  trailing edge of the list header; Command-Shift-P opens the menu.
- Keep rich NSTextView geometry synchronous. Implicitly animating its parent's
  constraints briefly blanked glyphs in the real window. Animate only auxiliary
  links and mode changes; replace animations by key and do not defer focus moves.
- Remove the visible knowledge-layer generation and graph routes while retaining
  core metadata compatibility. Incoming/outgoing links and optional suggestions
  use the existing index and cancellation mechanism.
- Verify using an independently identified preview app and synthetic notes. The
  production app remains subject to the verified-main installation requirement.
- Match light-mode selection fill to AppKit emphasis: white focused-row text uses
  the solid accent; dark inactive-row text uses a pale accent.
- A multiline plain-text paste crossing the unified title boundary preserves the
  first paragraph's title attributes and resets subsequent paragraphs to body
  formatting. Rich paste remains handled by the existing normalizer.
- Folder trash reconciliation enumerates the moved folder rather than trusting
  the current navigation snapshot, which can omit externally added notes.

Design reference: Apple Human Interface Guidelines, Materials and Motion:
https://developer.apple.com/design/human-interface-guidelines/materials
https://developer.apple.com/design/human-interface-guidelines/motion

Final real-window evidence: light and dark appearance; 896x560 minimum window;
divider drag from 280 to 340 and back; folder-picker keyboard navigation and
Escape; quick menu; repeated links disclosure with editor focus preserved;
multiline plain paste and saved Markdown readback. All data was synthetic under
/tmp/mudsnote-native-fixture. Screenshots: /tmp/mudsnote-macos-two-pane-light.png
and /tmp/mudsnote-macos-two-pane-dark.png. Independent preview:
/tmp/Mudsnote Native Preview.app. The shared installed app was not replaced.

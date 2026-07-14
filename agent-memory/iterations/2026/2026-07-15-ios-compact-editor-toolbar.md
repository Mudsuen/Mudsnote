# 2026-07-15 iOS compact Notes-style editor toolbar

## Request

Continue the iPhone Apple Notes parity target, with special emphasis on keeping
editing controls in one row and preserving Mudsnote's Markdown and attachment
capabilities.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `956abcb`
- The concurrent `scripts/visual_notes_qa.sh` edit was preserved and excluded.

## Changes

- Replaced the horizontally scrolling collection of individual editor controls with
  seven stable one-row controls: attachments, audio, `Aa`, checklist, table, undo,
  and redo.
- Photos, files, and document scanning now live in one native attachment menu.
- Heading, bold, italic, bullet/numbered lists, indentation, quote, code, and link
  commands now live in one native `Aa` formatting menu.
- The ordinary rendered editor remains the default. Advanced Rich Text/Markdown
  Source selection moved behind a Notes-style ellipsis menu so the top and bottom
  bars no longer show duplicate `Aa` controls.
- New attachment and formatting menu copy is localized in English and Simplified
  Chinese.
- UI automation opens both native menus, verifies their important commands, applies
  Bold, and verifies the Markdown round trip. Menu dismissal now uses an explicit
  outside tap so screenshots cannot land on a transition frame.

## Verification

- Generic iOS Simulator build and String Catalog compilation passed.
- Focused editor UI automation passed three times while the toolbar, top menu, and
  visual capture were refined.
- Final retained screenshot:
  `/tmp/mudsnote-compact-toolbar-final-stable/91A37BED-7C28-4FFA-AFB1-5A6F40FA4BA4.png`.
  It shows all seven controls in one row with the keyboard visible, a centered edited
  date, trailing save state, and the ellipsis advanced-options entry.
- Final full App and UI suite: 98 passed, 0 failed, 0 skipped.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
- Final result bundle:
  `/tmp/MudsnoteCompactToolbarFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.15_01-14-55-+0800.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteCompactToolbarRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible over USB but unavailable to CoreDevice; the install
  attempt failed because CoreDevice could not locate the unavailable device.

## Decisions

- Common Notes actions stay visible; less frequent format and attachment variants
  use native menus. This keeps the toolbar complete without horizontal discovery.
- Audio remains a direct action because it is a Mudsnote capture advantage and needs
  an immediate stop/retry state.
- Markdown Source remains available as an advanced option, but normal editing never
  requires switching away from the rendered editor.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical keyboard/menu and attachment smoke checks.
- Continue the next Notes-parity gap in editor paragraph styles or note retrieval.

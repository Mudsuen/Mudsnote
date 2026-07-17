# iOS unified native note entry

## Request

Unify ordinary New Note with the existing fast capture workflow, remove the separate lightning entry, keep all capture commands on one compact row, use a native Notes-style search toolbar, make opened notes switch between half and full height by swiping, remove note-level share/full-screen buttons, and fix editor caret placement and movement. Continue the iPhone-only, no-new-table scope and install the result on the connected iPhone.

## Baseline

- Branch: `main`.
- Prior iOS checkpoint: `b619432` (`Add folder drag nesting on iPhone`).
- Dirty files before work: none.

## Changes

- New Note is now the sole in-app creation entry and opens the durable capture composer; the standalone note-creation wrapper and lightning button were removed.
- Successful capture dismisses the sheet back to the library, while an empty interactive dismissal creates no note and durable draft recovery remains unchanged.
- Attachment, audio, tag, bold, checklist, more, destination, and submit controls fit one borderless row. Less common list/quote/code formatting stays in the More menu, and the deferred table-authoring control is not shown.
- Folder home and note-list search use a native bottom toolbar containing a UIKit text field, microphone, and black-symbol yellow New Note action. The text-field delegate owns focus transitions so empty suggestions, suggestion filtering, subsequent text entry, and clearing remain deterministic across the toolbar's separate SwiftUI host.
- Opened notes retain native medium/large sheet detents and the grabber but remove explicit expand/collapse and note-level share controls. PDF export and the remaining local note lifecycle actions stay available.
- The editor initially selects the end of the note. Its rich-text presentation no longer reapplies on unrelated SwiftUI updates, and the checklist tap recognizer now begins only over a checklist marker and cooperates with system text gestures, so ordinary taps move the caret normally.

## Verification

- Simulator build passed on iPhone 17 Pro / iOS 26.5.
- Full single-destination regression passed with parallel testing disabled: 106/106 unit tests and 52/52 UI tests, 158/158 total, zero failures and zero skipped.
- UI evidence confirmed the native one-row library toolbar and the eight-control capture row at the same iPhone viewport.
- Generic iOS Release archive succeeded at version `1.0 (1)` with App Intents SSU generation for English and Simplified Chinese.
- App and Widget passed strict code-sign verification.
- The development-signed App installed on physical `MudsPhone` / iPhone Air and appeared in the device inventory as `app.mudsnote.companion` version `1.0 (1)`; the Widget process was observed alive.

## Storage

- Iteration build, test, screenshot, and archive artifacts were kept under `/tmp` and removed after verification; the sole simulator was shut down.

## Next

- Continue the next highest-impact iPhone Apple Notes parity gap without reintroducing a second note-entry path, note-level share/full-screen buttons, a second capture row, iPad validation, or new table-authoring UI.

# iOS Notes-style folder drag nesting

## Request

Continue the iPhone Apple Notes parity goal while retaining Mudsnote's Markdown, New Note, and Quick Note advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `9a8fc91` (`Add swipe note moves on iPhone`).
- Dirty files before work: none.
- Only iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was booted; parallel testing stayed disabled.

## Product audit

- Apple's current iPhone Notes folder guide says dragging one folder onto another creates a subfolder.
- Mudsnote already had safe menu-driven folder moves, but Edit mode only exposed an overflow menu and had no direct drag affordance or target feedback.
- A fresh baseline was captured from the real Edit flow at `/tmp/mudsnote-ios-folder-drag-audit/01-folder-edit-baseline.png`.
- Accepted final evidence is `/tmp/mudsnote-ios-folder-drag-audit/02-folder-drag-ready.png`, `/tmp/mudsnote-ios-folder-drag-audit/03-folder-drag-complete.png`, and `/tmp/mudsnote-ios-folder-drag-audit/04-folder-nested.png`.

## Changes

- Real folders in Edit mode now reserve space for a standard reorder handle beside the existing overflow action.
- The handle is a native SwiftUI drag source, and the full destination row plus its handle accept drops.
- Valid drops reject the same folder and descendant targets, then call the existing atomic `AppModel.moveFolder` operation. The existing status toast confirms completion and the snapshot refresh removes the source row and updates destination counts.
- A targeted folder receives a short yellow surface and outline transition while the drag is over it.
- Dragging is intentionally limited to Edit mode. An initial version registered dragging in normal browsing, but compatibility testing showed SwiftUI's lift animation competed with the existing long-press menu; scoping the feature preserved navigation, swipe-delete, and context-menu behavior.
- No table-authoring, iPad, or dedicated accessibility scope was added.

## Verification

- The new UI test creates Archive, enters Edit mode, uses a slow full touch drag from the Projects handle to the Archive handle, verifies the source handle disappears, exits Edit, opens Archive, and finds `Archive/Projects`.
- Folder edit/rename, normal-mode long-press move-to-top-level, and drag nesting passed together 3/3.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5: 158/158 passed with zero failures and zero skipped (106 unit tests and 52 UI tests). One existing Find in Note dismissal emitted a Simulator animation-notification delay but completed and passed without recurrence.
- Generic iOS Release archive succeeded at version `1.0 (1)`.
- App and Widget passed strict code-sign verification; the privacy manifest, App Intents metadata, and English/Simplified Chinese SSU resources were embedded.
- Physical device `MudsPhone` / iPhone Air remained listed as `unavailable`; the Release installation attempt returned CoreDevice error 1011 before reaching the phone.

## Storage

- Peak removable artifacts were about 733 MiB: 289 MiB test DerivedData, 192 MiB archive DerivedData, 22 MiB archive, and 230 MiB xcresults/evidence.
- DerivedData, archives, xcresults, failed probes, and Simulator runtime state are removed after verification; only the four accepted PNGs remain in `/tmp` for the handoff.

## Next

- Continue the next highest-impact iPhone Notes parity gap while preserving Edit-only folder dragging, portable Markdown, and the iPhone-only/no-new-table scope.

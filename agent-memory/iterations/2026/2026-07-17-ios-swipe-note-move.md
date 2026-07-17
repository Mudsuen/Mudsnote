# iOS Notes-style swipe note move

## Request

Continue the iPhone Apple Notes parity goal while retaining Mudsnote's Markdown, New Note, and Quick Note advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `10ee20f` (`Add Notes-style attachment views on iPhone`).
- Dirty files before work: none.
- Only iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was booted; parallel testing stayed disabled.

## Product audit

- Apple's current iPhone Notes folder guide places Move beside Delete after a left swipe on a note.
- Mudsnote's note row exposed Pin from the leading swipe and Delete from the trailing swipe, while Move was available only from a long-press context menu.
- The selected gap was the high-frequency list organization flow: reveal Move beside Delete, select a destination in a native half-sheet, then update the same list after a real move.
- Visual evidence: `/tmp/mudsnote-ios-swipe-move-audit/04-baseline-final-comparison.png`.

## Changes

- A trailing left swipe now exposes a yellow Move action beside the existing red Delete action whenever at least one valid destination exists.
- Move opens a medium/large native sheet with a visible drag indicator, Cancel action, top-level Notes destination, and all other folders except the current one.
- Destination rows use existing Mudsnote colors and system symbols, show parent paths for nested folders, disable duplicate submission while moving, and dismiss only after the existing atomic `AppModel.moveNote` succeeds.
- English and Simplified Chinese Move copy was added to the existing String Catalog.
- No table-authoring, iPad, or dedicated accessibility scope was added.

## Verification

- The new end-to-end UI test verifies that left swipe reveals Move and Delete, the destination sheet opens, and selecting Top Level changes `Projects/UI Lifecycle.md` to `UI Lifecycle.md` in the live list.
- The new flow, multi-selection move, and opened-note move/delete compatibility cluster passed 3/3.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5: 157/157 passed with zero failures (106 unit tests and 51 UI tests). A first run was interrupted after the Simulator animation service repeatedly delayed an existing new-note dismissal test; that test passed alone in 16.8 seconds after restarting the same Simulator, and the complete retry passed in about 17 minutes 36 seconds.
- Generic iOS Release archive succeeded at version `1.0 (1)`.
- App and Widget passed strict code-sign verification; the privacy manifest, App Intents metadata, and English/Simplified Chinese SSU resources were embedded.
- Physical device `MudsPhone` / iPhone Air was listed as `unavailable`; the Release installation attempt returned CoreDevice error 1011 before reaching the phone.

## Storage

- Build, test, and archive artifacts stayed under `/tmp`; no additional Simulator device was created or booted.
- DerivedData, archives, xcresults, and Simulator runtime state are removed after verification; only the accepted PNG audit evidence is retained in `/tmp` for this handoff.

## Next

- Continue the next highest-impact iPhone Notes parity gap while preserving portable Markdown, the single-row capture layout, and the current iPhone-only/no-new-table scope.

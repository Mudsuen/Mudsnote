# iOS Notes-style note-list capture bar

## Request

Continue the full iPhone Apple Notes parity goal while retaining Mudsnote's capture and Markdown advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `2b78016` (`Expose Notes-style folder editing`).
- Dirty files before work: none.

## Product audit

- Captured the current All Notes list, rendered editor, and Gallery flow in this run.
- Used Apple's current iOS 26 Gallery screenshot from the official iPhone Notes guide as the reference surface.
- The largest daily-use gap was structural: Mudsnote's Search, audio capture, Quick Note, and New Note controls disappeared after entering All Notes, Daily, or a custom folder, while Apple Notes keeps Search and New Note available at the bottom of note lists.
- The initial Mudsnote Gallery also omitted the Notes-style note count beneath the large title.

## Changes

- Reused the existing single-row Notes bottom command bar in All Notes, Daily, and every custom-folder note list.
- Preserved the black New Note symbol in the yellow action circle and retained Mudsnote's microphone and lightning Quick Note extensions.
- Added list-local full-text search backed by the existing body, attachment OCR, and scanned-PDF search pipeline.
- All Notes includes file and Inbox memo results; Daily and custom folders filter results to their visible scope.
- Search results open the same rendered half-sheet reader and keep the complete editor path available.
- Selection mode still replaces the capture bar with Move, Tags, and Delete actions, restoring the capture bar after Done.
- New Note from Daily or a custom folder starts in that folder; All Notes keeps the top-level destination.
- Added a localized note-count subtitle below list titles and retained the existing List/Gallery presentation choice.
- No table-authoring behavior changed.

## Verification

- Product Design preflight found no saved product context, so the official Apple reference and current implementation screenshots were captured fresh.
- Focused scope unit test, searchable-list UI test, and Gallery persistence/layout test passed.
- Official Apple Gallery and final Mudsnote Gallery screenshots were compared side by side at equal height; navigation, title/count hierarchy, grouped content, and bottom actions align while Mudsnote keeps its dark theme and Quick Note action.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5, simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`: 148/148 passed (101 unit, 47 UI), zero failures and zero skipped.
- Parallel testing remained disabled and no additional simulator was used.
- Generic iOS Release archive succeeded at version `1.0 (1)`.
- App and Widget passed strict code-sign verification; both privacy manifests were embedded; no App Intents/SSU archive warning was emitted.
- Physical device `MudsPhone` / iPhone Air remained `unavailable` to CoreDevice. DDI inspection and installation both returned CoreDevice error 1011 before reaching the phone.

## Storage

- Peak temporary artifacts were about 481 MB DerivedData, 20 MB archive, 4.7 MB screenshot evidence, and about 1.1 MB of logs.
- All artifacts stayed under `/tmp`; the sole used simulator was shut down and all temporary artifacts were removed after verification.

## Next

- Continue the next highest-impact iPhone Notes parity gap, preserving this persistent capture/search contract and leaving table authoring deferred.

# iOS Notes-style Gallery content previews

## Request

Continue the full iPhone Apple Notes parity goal while retaining Mudsnote's Markdown, New Note, and Quick Note advantages. Do not add iPhone table-authoring functionality, dedicated accessibility work, or iPad validation.

## Baseline

- Branch: `main`.
- HEAD: `0c6f700` (`Keep capture available in note lists`).
- Dirty files before work: none.

## Product audit

- Captured the current Gallery and full editor on iPhone 17 Pro / iOS 26.5.
- Downloaded Apple's current Gallery screenshot from the official iPhone Notes guide and compared it with Mudsnote at equal height.
- Apple Gallery surfaces recognizable note contents such as photos and checklists. Mudsnote's cards were uniform title/summary boxes, so users could not visually identify image-heavy or checklist notes without opening them.
- The highest-impact gap selected for this iteration was real Gallery content previews; table authoring remained deferred.

## Changes

- Gallery cards now show the first referenced image and up to two checklist rows, up to four checklist rows when no image is present, or the existing text preview as fallback.
- Checklist rows preserve checked/unchecked state and strip common inline Markdown formatting markers from the compact label.
- The existing file-store actor extracts this small Gallery snapshot alongside title, preview, tags, and other cached list metadata. The SwiftUI view does not open or scan Markdown files.
- Image previews reuse the existing attachment inventory and lazy thumbnail component instead of adding a parallel decoder or cache.
- Existing card selection, pinning, date grouping, folder label, context menu, search bar, and Quick Note/New Note controls remain unchanged.
- UI-test fixtures now use a real SF Symbols image and realistic checklist content so the visual regression exercises the shipped rendering path.
- No table-authoring behavior changed.

## Verification

- Product Design preflight found no saved product context, so official Apple and current implementation evidence was captured fresh.
- Focused list-metadata unit coverage and Gallery UI coverage passed.
- Official Apple Gallery and final Mudsnote Gallery screenshots were combined and inspected side by side at equal height. The final Mudsnote card exposes a recognizable image plus rendered checklist state while retaining its dark theme and Quick Note control.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5, simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`: 148/148 passed, zero failures and zero skipped.
- Parallel testing remained disabled and no additional simulator was used.
- Generic iOS Release archive succeeded at version `1.0 (1)`.
- App and Widget passed strict code-sign verification; the app privacy manifest was embedded; App Intents SSU generation completed for English and Simplified Chinese with no archive warning.
- Physical device `MudsPhone` / iPhone Air was visible to CoreDevice but remained `unavailable`; the installation retry returned CoreDevice error 1011 before reaching the phone.

## Storage

- Peak removable build/audit storage was about 586 MB: 512 MB test DerivedData, 48 MB Xcode archive cache, 21 MB archive, 3 MB screenshots, and 1.5 MB logs.
- The sole used simulator was shut down and all iteration-specific temporary artifacts were removed after verification.

## Next

- Continue the next highest-impact iPhone Notes parity gap while preserving cached list metadata, Gallery content recognition, and the existing capture/search contract; table authoring remains deferred.

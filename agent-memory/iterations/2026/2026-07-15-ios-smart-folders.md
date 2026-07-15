# 2026-07-15 iOS Smart Folders

## Request

Continue the iPhone Apple Notes parity target by adding Notes-style Smart
Folders while preserving Mudsnote's Markdown source of truth, standalone new
notes, quick notes, and rendered Markdown editing. Scope remained iPhone-only;
no iPad or accessibility work was added.

## Baseline

- Branch: `main`
- HEAD: `92ed295`
- Dirty files before work: none
- Simulator contract: only iPhone 17 Pro / iOS 26.5
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`, with parallel testing disabled.

## Changes

- Added versioned Smart Folder definitions stored in
  `.mudsnote/smart-folders.json`. Definitions contain only portable filter
  metadata; Markdown files and Inbox quick-note blocks remain in their original
  locations.
- Added Notes-style `All` / `Any` matching with tri-state tag include/exclude,
  edited/created date ranges, attachment presence, checklist state, and pinned
  state filters.
- Extended normal-note and quick-note metadata with checklist and unchecked-item
  projections so saved filters do not reread full note bodies during view
  rendering.
- Added the complete iPhone lifecycle: create from the New Folder alert, edit in
  a native form, browse matching normal and quick notes together, long-press to
  edit or delete, and explicitly confirm that deletion leaves notes in place.
- Added Simplified Chinese localization for the full lifecycle and filter set.
- A damaged optional Smart Folder configuration no longer blocks the Markdown
  library. Snapshot loading falls back to no Smart Folders while preserving the
  unreadable file; strict create/update/delete operations still fail rather
  than silently overwriting potentially recoverable data.
- Apple behavior references used for the product boundary:
  <https://support.apple.com/en-us/102288> and
  <https://support.apple.com/en-lamr/guide/iphone/iphc43adabc2/ios>.

## Verification

- `git diff --check` passed.
- Generic iOS Simulator build passed.
- Focused matching, persistence, checklist metadata, damaged-configuration, and
  end-to-end Smart Folder UI tests passed.
- Visual inspection confirmed one Smart Folder renders both the matching normal
  note and Inbox quick note without moving either source. Evidence:
  `/tmp/mudsnote-smart-folder-ui/82B3D651-AF28-458F-89CD-CEF53CA2E2CE.png`.
- Final full suite passed 129 tests with 0 failures and 0 skipped. Result bundle:
  `/Users/Donald/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Logs/Test/Test-MudsnoteCompanion-2026.07.15_08-41-25-+0800.xcresult`.
- Only the required iPhone 17 Pro simulator was used. All simulators were shut
  down after testing.
- The final signed Release build passed at
  `/Users/Donald/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- CoreDevice listed MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`) as
  `unavailable`. Installation was attempted and failed with CoreDevice error
  1011 because Xcode could not locate an available device session; no physical
  install or launch claim was made.

## Decisions

- Smart Folders are saved queries, not storage containers. Deleting one cannot
  delete or move a Markdown note or quick-note block.
- The versioned JSON file is the only proprietary metadata; note content stays
  fully portable Markdown.
- Excluded tags always veto a match. Remaining selected filters follow the
  folder's `All` / `Any` rule.
- Optional feature metadata cannot take down core note access, but damaged data
  is never silently replaced by a write operation.

## Next

- Continue the broad Notes parity pass with the next highest-value missing
  iPhone workflow after a fresh source/UI audit.
- Restore MudsPhone CoreDevice availability, install the signed Release, and
  repeat Smart Folder create/edit/delete plus normal-note editing on hardware.

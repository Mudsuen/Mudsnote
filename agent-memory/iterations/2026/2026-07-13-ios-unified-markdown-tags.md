# 2026-07-13 iOS unified Markdown tags

## Request

Continue the iPhone Apple Notes parity target while preserving Mudsnote's local
Markdown model. Close the split where Tags indexed only Inbox quick notes and
ignored tags in ordinary Markdown note files.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `7bb9404`
- Pre-existing macOS edits were preserved and excluded.

## Changes

- Ordinary Markdown list metadata now extracts Unicode hashtags and carries them
  in the shared note inventory.
- Tag extraction is case-, diacritic-, and width-insensitive for de-duplication,
  while preserving the first user-facing spelling.
- Fenced and inline code are excluded from the tag index. Fenced code is also
  excluded from title and list-preview extraction, fixing code-language leakage
  into note summaries.
- The home Tags section now aggregates distinct ordinary notes and Inbox quick
  notes instead of indexing only quick notes. The Inbox container file itself is
  excluded so quick-note tags are not double counted.
- A unified tag destination shows ordinary Markdown notes and quick notes in
  separate Notes-style sections, retaining each note type's editing and lifecycle
  actions.

## Verification

- Generic iOS Simulator build passed.
- Focused metadata coverage verified Unicode tags, case-insensitive de-duplication,
  inline-code exclusion, fenced-code exclusion, and clean list previews.
- Focused snapshot coverage verified tags are carried by an ordinary Markdown file.
- Focused iPhone UI automation verified one tag opens a destination containing both
  an ordinary Markdown note and a quick note.
- Final full App and UI suite: 93 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteUnifiedTagsFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_20-05-10-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteUnifiedTagsDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- The Release app installed successfully on MudsPhone (iPhone Air). Automatic
  launch was attempted, but SpringBoard rejected the current development build as
  not explicitly trusted by the device; physical visual smoke remains pending.

## Decisions

- Hashtags remain plain portable Markdown text; the index is derived and can always
  be rebuilt without owning note data.
- Tag counts represent distinct note records, not raw hashtag occurrences.
- Inbox.md is a storage container for quick notes and therefore does not count as a
  second tagged note.

## Next

- Reconfirm the current developer profile under VPN & Device Management on
  MudsPhone, then launch the already installed build for a physical tag smoke.
- Continue the next Notes-parity list, organization, or editor interaction gap.

# 2026-07-02 note-list attachment indicator

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity.

## Baseline

- Branch: main
- Dirty files before work: none
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: note-list rows lacked attachment indicators.

## Changes

- Added `hasAttachments` to `NoteSearchResult`.
- Populated attachment presence from Markdown bodies that are already loaded by list/search/trash/recent paths.
- Added a compact SF Symbol `paperclip` indicator beside note-list metadata when a note contains a Markdown link into `Attachments/`.
- Kept the indicator hidden for normal notes and constrained to a fixed 12x12 size so the row layout remains stable.
- Reduced duplicate IO in empty search results by loading each recent note once for title, snippet, tags, and attachment state.

## Verification

- `swift test` passed with 67 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-note-list-attachment-indicator.png`.

## Decisions

- Do not add attachment scanning to the launch path.
- Attachment indicators should come from existing bounded hydration or existing search/list note loads.
- Full thumbnail previews remain a later polish item.

## Next

- Continue with keyboard navigation, exact row spacing, thumbnail previews, toolbar disabled states, and side-by-side visual QA.

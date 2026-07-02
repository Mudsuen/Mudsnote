# 2026-07-02 centered editor date line

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity.

## Baseline

- Branch: main
- Dirty files before work: none
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: editor metadata/date placement was not close enough.

## Changes

- Changed the library editor status line for loaded notes from `date · folder` to date-only text.
- Moved the status label into a dedicated editor date row so it centers across the right editor pane instead of relying on the label's intrinsic width inside the vertical stack.
- Kept transient new/dirty status behavior for clarity while editing.
- Added app regression coverage for the editor status identifier, center alignment, date-only string, and absence of the folder separator.

## Verification

- `swift test` passed with 67 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-centered-editor-date-line.png`.

## Decisions

- Folder context stays in the note list metadata and source list counts.
- The editor header should remain focused on note timestamp, matching the Apple Notes reference more closely.

## Next

- Continue with exact editor title/body vertical spacing, toolbar disabled states, keyboard navigation, attachment indicators, and side-by-side visual QA.

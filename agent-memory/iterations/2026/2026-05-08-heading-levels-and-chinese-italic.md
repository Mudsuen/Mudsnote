# 2026-05-08 heading levels and Chinese italic

## Request

- Support Markdown heading levels 1, 2, and 3 from the editor UI/shortcuts.
- Fix italic formatting not being visible or serializable for Chinese text.

## Baseline

- Branch: main
- HEAD: aca4709
- Dirty files before work: none.

## Changes

- Split the toolbar heading action into `H1`, `H2`, and `H3`.
- Added heading shortcuts:
  - `cmd+option+1`: heading 1
  - `cmd+option+2`: heading 2
  - `cmd+option+3`: heading 3
- Added heading 2 and heading 3 slash-command entries.
- Changed italic formatting to apply both an italic font trait and `.obliqueness`, so Chinese text without a native italic face still appears slanted.
- Updated Markdown serialization to treat `.obliqueness` as italic and continue writing `*...*`.
- Tightened bullet-list parsing so `*中文*` is not misread as a bullet list; list markers now require following whitespace.

## Verification

- `swift test`
- `./scripts/package_app.sh`
- Launched `/Applications/Mudsnote.app --floating-note` and confirmed the packaged app process started.

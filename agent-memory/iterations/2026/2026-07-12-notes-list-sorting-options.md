# 2026-07-12 Notes list sorting options

## Request

Continue Apple Notes UI and core-function parity while keeping file-backed architecture efficient.

## Baseline

- Branch: `main`
- HEAD: `33def02`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- Mudsnote offered edit-date/title sorting and date grouping, but its menu hierarchy differed from Notes and creation-date sorting was absent.

## Changes

- Captured Apple Notes' View Options menu before implementation: Sort By first, Group By Date second, with Date Edited, Date Created, and Title choices.
- Removed the disabled `显示为列表` placeholder and reordered the actionable menu hierarchy.
- Added `createdAt` to search results, index entries, and file signatures; bumped the disk-cache schema so existing indexes rebuild once.
- Reads creation and modification dates from the same `attributesOfItem` call, avoiding a second metadata scan.
- Added creation-date ordering and grouping while preserving pinned-note precedence and selected-note identity.
- Visible row dates now use creation time when creation-date sorting is active.
- Preserved the existing persisted raw values (`dateEdited = 0`, `title = 1`) and assigned creation date to `2` so upgrades do not reinterpret a user's title-sort preference.

## Verification

- Focused projection, controller, menu-state, selection-preservation, and search-index persistence tests passed.
- Installed-app reverse-order fixture proved edit-date order changes to creation-date order and keeps the selected note.
- Full Swift suite passed after the visible-date correction.
- Final package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.
- Installed reverse-order fixture switched from edit-date order `First, Second, Third` with 2027 row dates to creation-date order `Third, Second, First` with actual `13:10` creation times while preserving the selected First note.

## Decisions

- Omit Notes' attachment browser and destructive root actions because they are outside the requested lightweight Markdown core.
- Keep creation metadata in the shared bounded index rather than querying files during each menu action.

## Next

- Continue editor complex-content visual tuning and attachment preview parity.

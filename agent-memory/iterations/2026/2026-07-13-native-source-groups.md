# 2026-07-13 native source groups

## Request

Continue moving the macOS library toward Apple Notes using native system implementation and efficient architecture.

## Baseline

- Branch: `main`
- Starting macOS commit: `d18747c`
- Concurrent iOS work was present and remained outside this iteration.

## Changes

- Made `iCloud` and `Tags` real root parents in `NSOutlineView`.
- Nested All iCloud, local folders, Recently Deleted, and tag scopes under their matching parent.
- Persisted native disclosure changes without deleting hidden child models.
- Deferred folder/tag loading while its group is collapsed and restored selected scope rows on expansion.
- Removed the side effect from `shouldSelectItem`; AppKit calls that delegate as a query during reload.
- Allowed empty selection while every selectable child is hidden.
- Rebalanced cell and group leading insets around native outline indentation.

## Verification

- `swift test`: 154 tests passed in 2 suites.
- Installed `/Applications/Mudsnote.app` from `./scripts/package_app.sh`.
- `codesign --verify --deep --strict`: passed.
- Computer Use AX tree reports iCloud and Tags as expanded rows with native `Collapse` actions.
- Same-height live comparison: `/tmp/apple-notes-vs-mudsnote-groups-final-206.png`.

## Decisions

- Keep hidden children in the outline model; collapse is a view state, not a model deletion.
- Group expansion notifications must be verified against the current item identity and settled AppKit state before persistence.

## Next

- Continue with content-state editor tuning and deeper drag/drop polish from the parity roadmap.

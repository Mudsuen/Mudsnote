# 2026-07-12 Full-height native sidebar

## Request

Correct the upper sidebar mismatch: the rounded independent region must include the traffic lights and adjacent source toolbar icons.

## Baseline

- Branch: `main`
- HEAD: `d132aa3`
- Pre-existing dirty file: `iOS/MudsnoteCompanionUITests/MudsnoteCompanionUITests.swift`, left untouched.
- The source material was rounded only inside a raw `NSSplitView` content pane, so it started below the titlebar.

## Changes

- Added `.fullSizeContentView` to the library window.
- Migrated the root from manually added split subviews to `NSSplitViewController`.
- Uses `NSSplitViewItem.sidebar` for sources, `contentList` for the note list, and a regular split item for the editor.
- Enabled `allowsFullHeightLayout` so the source material reaches the window top behind traffic lights and source toolbar controls.
- Anchored the source stack to `safeAreaLayoutGuide.topAnchor`, preventing source rows from entering the titlebar controls.
- Source visibility now maps to `NSSplitViewItem.isCollapsed`; stored source/note widths and tracking separators remain attached to the managed split view.
- Divider-resize persistence moved from delegate ownership to the split view's resize notification because `NSSplitViewController` owns its delegate.

## Verification

- Focused tests cover full-size content, native split controller presence, three managed panes, expanded/collapsed state, toolbar tracking separators, and split-width persistence.
- Installed expanded screenshot shows the rounded source region enclosing traffic lights, Add Folder, and sidebar toggle while rows remain below the safe area.
- Installed collapsed screenshot shows the region fully removed and the note list/library title taking the left edge without overlap.
- Full Swift suite passed after the root-container migration.
- Final package installed at `/Applications/Mudsnote.app` and passed strict deep code-sign verification.

## Decisions

- Use AppKit's native sidebar/content-list ownership rather than placing another titlebar overlay behind standard window controls.

## Next

- Continue complex attachment preview parity and per-symbol toolbar tuning.

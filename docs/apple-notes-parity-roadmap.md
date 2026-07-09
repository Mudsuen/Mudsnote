# Mudsnote Apple Notes Parity Roadmap

## Goal

Mudsnote macOS should become a local-first Markdown notes app whose main desktop experience matches Apple Notes' core function and UI closely enough that it can replace the user's everyday Apple Notes workflow.

This is a product target, not a single cosmetic pass. Completion requires interaction parity, information architecture parity, visual parity, and packaged-app verification.

## Product Boundary

Mudsnote should replicate Apple Notes' desktop experience where it fits a lightweight local Markdown app:

- local `.md` files remain the source of truth
- quick capture and floating notes remain fast entry points
- the default no-argument app launch opens the Notes-like library
- Apple/iCloud-private features are represented only when they can be implemented locally without turning Mudsnote into a sync service

Not in scope unless explicitly requested:

- iCloud sync implementation
- Apple account integration
- collaboration/sharing through Apple services
- direct reading or writing of Apple Notes private databases
- iOS real-device installation or validation for this macOS Notes-parity goal

## Definition Of Done

The goal is reached only when all of these are true:

- Opening `/Applications/Mudsnote.app` directly shows the Notes-like library, not only a floating capture panel.
- The macOS main window visually matches the supplied Apple Notes screenshot at the same state:
  - three-pane layout
  - dark sidebar and source list density
  - recency-sectioned note list
  - golden selected note card
  - centered editor date
  - compact top toolbar
  - right-side search field
- The core Apple Notes workflows work end to end:
  - create note
  - edit rich text
  - format text
  - add checklist
  - add table
  - add attachment
  - search
  - filter by folder/tag
  - move note
  - delete to trash
  - restore from trash
  - permanently delete
  - create/rename/delete folders
  - create/use tags
  - open note in separate window
  - reveal/copy underlying Markdown file
- The app stays usable with plain Markdown files outside the app.
- Regression tests cover the main workflows.
- `swift test`, `./scripts/package_app.sh`, and installed-app smoke verification pass.
- Verification is macOS-only unless a separate iOS goal is explicitly created.
- Visual QA uses side-by-side comparison against the Apple Notes screenshot, not screenshot-only inspection.

## Parity Scorecard

Use this checklist to decide whether future work is moving toward the goal.

### 1. Window And Toolbar

- Unified titlebar and toolbar behave like a Notes window.
- Toolbar contains functional icon buttons for:
  - new folder
  - sidebar toggle
  - more actions
  - new note
  - text formatting
  - checklist
  - table
  - attachment
  - share/export or file actions
  - search
- Toolbar controls are icon-first and use native symbols where possible.
- The editor-tools group should keep the earlier compact, borderless dark capsule treatment: `184x32`, `19pt` toolbar symbols, plain dark `NSView` fill, clear border when rim alpha is zero, and no oversized custom buttons.
- Keyboard shortcuts map to expected note actions.

### 2. Source List

- Left pane is a true source list, not only a few filter buttons.
- Supports:
  - account/library group
  - local call-recordings smart source
  - all notes
  - folders
  - nested or collapsed folders
  - tags
  - trash/recently deleted
  - counts
- Empty local folders should still show `0` counts in the source list when they are visible.
- Selection state, disclosure state, hover, and disabled states are visible and native-feeling.
- Source rows should stay in the compact Apple Notes rhythm: small icons, 36pt rows, restrained counts, and tight section spacing.
- The default Markdown root is presented as `Notes` in the source list, note metadata, and move menus, even if the local folder is named `Mudsnote`.

### 3. Note List

- Middle pane groups notes by recency:
  - Today
  - Yesterday
  - Previous 7 Days
  - Previous 30 Days
  - years
- Rows show title, first useful body line, folder, date/time, and attachment/thumbnail indicators when present.
- Selected row uses Notes-like golden highlight.
- List supports keyboard navigation, double-click/open, context menu, and drag/move when practical.

### 4. Editor

- Right pane behaves like a real note editor:
  - centered date/status line
  - title inferred from first line or explicit title field
  - rich text editing backed by Markdown serialization
  - paragraphs, headings, bold, italic, underline/strikethrough
  - bullets, numbered lists, checklists
  - tables
  - links
  - tags
  - attachments
- Empty note, unsaved note, and dirty states are clear without heavy chrome.
- Empty Markdown files keep a blank editor title while the note list can still show the filename, matching Apple Notes' empty-new-note feel without losing local file identity.
- Save remains reliable and local-first.

### 5. Search

- Search field sits in the Notes-like toolbar position.
- Search can scope to all notes, current folder, or tag.
- Results preserve sectioning and highlight matches where useful.
- Search uses the lightweight index once the note count makes scan-on-demand too slow.

### 6. File And Data Model

- Markdown remains readable and portable.
- Folders map to filesystem directories or a documented local metadata layer.
- Trash is implemented as a reversible local state before permanent delete.
- Attachments are stored in a local attachments folder with stable relative links.
- Derived metadata can use a lightweight cache, but cache loss must not lose notes.

### 7. Verification

- Unit tests cover store behavior, editor serialization, list filtering, trash, folders, attachments, and shortcuts.
- Packaged app smoke covers direct launch, create/edit/save, search, delete/restore, folder move, and attachment rendering.
- Visual QA captures the same window state as the Apple Notes reference and records remaining deltas.

## Implementation Phases

### P0: Lock The Shell

Objective: make the first screen structurally match Apple Notes.

- Native Notes-like toolbar
- right-side search field in toolbar
- source list counts and folder rows
- recency note list refinements
- centered editor date/status
- visual QA comparison harness

Exit criteria: direct launch screenshot is visibly close to Apple Notes' three-pane shell before deep features are evaluated.

### P1: Core Note Workflows

Objective: make the shell useful for daily notes.

- create note in selected folder
- rename/edit note
- move between folders
- create/rename/delete folders
- delete to trash
- restore/permanent delete
- context menus and keyboard shortcuts

Exit criteria: user can manage the full note lifecycle without Finder.

### P2: Rich Editor Parity

Objective: match Apple Notes' everyday editing tools.

- toolbar formatting popover
- checklist button
- table insertion/editing
- link insertion/editing
- attachment insertion/rendering
- paste normalization for rich text and files

Exit criteria: ordinary Apple Notes editing sessions can be recreated in Mudsnote and still save to readable Markdown.

### P3: Search, Metadata, And Scale

Objective: make retrieval feel Notes-grade.

- search scope controls
- highlighted matches
- folder/tag filters
- task and attachment indicators
- lightweight local index cache
- recent access and pinned notes

Exit criteria: searching and returning to old notes is faster than manually navigating folders.

### P4: Polish And Parity States

Objective: close visible mismatch and edge-state gaps.

- hover/selection/focus polish
- empty, loading, no-result, trash, and locked/unavailable states
- toolbar disabled states
- accessibility labels
- keyboard navigation
- resize behavior and minimum-width layout

Exit criteria: side-by-side QA shows only intentional product-boundary differences.

### P5: Optional Apple Notes Adjacent Features

Objective: add local equivalents where useful.

- smart folders
- backlinks/wiki links
- daily note
- import/export flows
- share/export actions
- optional local AI transforms kept explicit and non-indexing

Exit criteria: these features improve local Markdown workflow without making the app heavier than the Notes replacement goal needs.

## Current Known Gaps

- Toolbar has a Notes-like expanded top chrome, split-view-tracking separators aligned to the source/list/editor pane boundaries, grouped editor-tools capsule for format/checklist/table/link/attachment actions with compact `184x32` plain dark-fill treatment, a hard no-rim border path when the border alpha is zero, calmer icon-level enabled/disabled tinting that keeps the compact custom controls stable, compact `30x28` borderless icon menu buttons for share/export and more actions, Markdown export/share affordances for system sharing, copying content, exporting one file, and sharing/exporting multiple selected Markdown files, a more-actions menu with selection-count-aware file action labels, a wider Notes-like search field, stateful source-list toggling, restrained toolbar symbol sizing, and context-aware disabled states, but still needs deeper per-symbol toolbar tuning against Notes.
- Titlebar, list headers, default window proportion, and shared layout metrics are closer to Notes, with the default shell brought back to the earlier compact `1420x860` Notes-like canvas, screen-clamped presentation, narrower source/list columns, and less card-like note-list selection geometry so the editor pane is not squeezed by oversized navigation panes.
- Source list has compact group labels, a local `Call Recordings` smart source with a Notes-like phone-waveform icon derived from the existing note snapshot, tighter Notes-like default column geometry, stronger Notes-like typography and row height, selected/unselected source-row font weight separation, medium-weight icons, brighter Notes-like unselected row text/icons, true all-note counts from a shared library snapshot, restrained count color that no longer competes with selected source titles, warm selected-row tint, quieter hover feedback, tightened top inset/disclosure/count geometry, launch-safe root folder rows, deferred full folder loading, loading/empty state rows, tag rows after shell visibility, session-local folder disclosure controls, Notes-like collapsible folder/tag sections, a Notes-like recently-deleted row below the folder group, toolbar show/hide behavior, and cached drag-target validation, but still needs deeper hierarchy visual tuning.
- Note-list rows show Notes-like compact three-line metadata with title, date-plus-preview without duplicated weekday prefixes, a separate folder/tags row with a folder icon, bounded body previews, a darker Notes-like column, a true filesystem-backed all-notes scope, tighter Notes-like default column geometry, denser recency group/note row rhythm, tightened title/snippet/meta typography and row height with stronger title/preview weights, shared-snapshot folder/tag filtering, centralized horizontal spacing, near-full-width selected highlights with sampled darker Notes-like gold fill, low-contrast hover feedback, subtle row separators, native Markdown file drag-out, drag-to-folder moves with cached validation, multi-selection file actions, selection-count-aware action labels, multi-note move/delete/share/export, multi-note drag-to-folder moves with piled count previews, compact attachment indicators, local image thumbnails, launch-safe shell-first direct-open hydration with background first-note loading and immediate title/date shell, keyboard open/delete and Up/Down note browsing, and empty/no-result/trash feedback, but still needs deeper drag-and-drop polish for edge states.
- Editor now uses a centered date-only header for loaded notes, explicit left-aligned note titles, debounced autosave, lighter save-progress copy, compact Notes-like title typography, a slightly stronger 17pt body reading size, wider body line rhythm, a Notes-like date-to-title vertical rhythm, and a Notes-like content inset closer to the editor divider, but still needs deeper side-by-side visual tuning.
- Rich editor has Markdown-level table/link/attachment insertion from the library toolbar, note-list image thumbnails, in-editor previews for local image references, openable non-image local attachment chips with metadata/context actions, selected-source Markdown export, and full-note Markdown copy, but still lacks full rich table editing and richer attachment preview types.
- Search is in the top toolbar and supports current/all scoping with visible row highlights, editor-side match highlights, no-result feedback, multi-result stepping from the search field, keyboard loading into the editor, debounced typing reloads with immediate keyboard-command flush, cancellable detached search-result refreshes, search reloads that skip unrelated source-count refreshes, background indexing status during full-library hydration, and a prewarmed lightweight Markdown index with disk-backed snapshot persistence, but still needs deeper incremental refresh polish.
- Visual QA has a repeatable active-window side-by-side harness with quiet source-loading rows, pointer-hover suppression before capture, explicit frontmost-app verification before screenshot capture, point/pixel/backing-scale/window-bounds metadata, labeled comparison output against the supplied Apple Notes screenshot, empty-note and content-note fixture selection modes, focus-stable requested-note selection that avoids an editor caret in comparison captures, canonical `1420x860` capture sizing even on smaller visible frames, tighter compact-shell geometry, and a compact no-rim toolbar baseline, but still needs per-iteration delta notes and closer toolbar/source-list visual tuning.

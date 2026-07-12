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
  - note-list display and sorting options
  - new note
  - text formatting
  - checklist
  - table
  - attachment
  - search
- Toolbar controls are icon-first and use native symbols where possible.
- The editor-tools group should keep the earlier compact, borderless dark capsule treatment: `184x32`, `19pt` toolbar symbols, plain dark `NSView` fill, clear border when rim alpha is zero, whole-capsule disabled fade, and no oversized custom buttons.
- Copy/export and current-note actions remain available through native menus and keyboard commands rather than occupying the toolbar; collaboration/share chrome is intentionally omitted.
- The middle-column list-options and new-note actions should use independent compact `30x30` dark circular buttons with `16pt` symbols and no visible rim.
- Source and note columns are independently resizable within stable limits; their widths and source-list visibility persist across launches while the editor absorbs ordinary window resizing.
- Keyboard shortcuts map to expected note actions.
- The app exposes a lightweight native macOS main menu: `Command-N` creates an editable note in the three-pane library, `Command-F` focuses library search, responder-chain edit commands remain native, and quick capture stays on its separate global hotkey.

### 2. Source List

- Left pane is a true source list, not only a few filter buttons.
- Supports:
  - account/library group
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
- paste normalization for rich text and files (HTML/RTF, Finder files, and clipboard images implemented; embedded rich-media paste remains open)

Exit criteria: ordinary Apple Notes editing sessions can be recreated in Mudsnote and still save to readable Markdown.

### P3: Search, Metadata, And Scale

Objective: make retrieval feel Notes-grade.

- search scope controls
- highlighted matches
- folder/tag filters
- task and attachment indicators
- lightweight local index cache
- recent access and pinned notes
- stale recent-file references self-heal during asynchronous launch hydration without adding a synchronous filesystem scan
- visible uncached-note selection reads Markdown off the main thread, cancels stale requests, and keeps adjacent prefetch lower priority than the active selection

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
- local Markdown copy/export actions
- optional local AI transforms kept explicit and non-indexing

Exit criteria: these features improve local Markdown workflow without making the app heavier than the Notes replacement goal needs.

## Current Known Gaps

- Toolbar uses Notes-like unified titlebar chrome so traffic lights and controls share one row, with split-view-tracking separators aligned to the source/list/editor pane boundaries. New Note sits immediately across the tracked editor divider, matching Notes ownership in expanded and collapsed states; the currently unnecessary share and ellipsis controls are absent. It uses a compact `30x30` native macOS 26 glass circle, while editor format/checklist/table/link/attachment actions use one `184x32` `NSGlassEffectView`. Disabled state remains an efficient group-level fade with icon-level command availability, while custom CALayer fill and border rendering has been removed. Menu-backed editor commands now use normal AppKit click-release activation and a centered button-relative lower-edge anchor instead of intercepting mouse-down. List sorting and date grouping remain available through state-validated native View-menu commands without restoring toolbar clutter. A wider Notes-like search field, stateful source-list toggling, restrained symbols, and native app/File/Edit/View/Window commands remain present; deeper per-symbol tuning remains open.
- Titlebar, list headers, default window proportion, and shared layout metrics now use a `940x630pt` shell close to the supplied `931x623pt` Apple Notes window. Default source/list columns are reference-measured `212/200pt`; source/list widths, source visibility, and the whole workspace frame persist across launches. Restored frames are clamped onto the nearest visible display, while canonical visual QA ignores personal frame state. Version 5 resizes only exact previous-default `1080x680/720pt` frames around their existing center, and version 6 replaces only exact stored `220/200pt` pane defaults; manually resized windows and panes remain intact.
- Source list is a full-height native `NSSplitViewItem.sidebar` with a darkened native material and `24pt` rounded clipping boundary covering the titlebar, traffic lights, Add Folder, and sidebar-toggle controls in expanded mode. The material does not draw a second outline over AppKit's native sidebar edge. Its rows begin below the titlebar safe area. User collapse runs through a `0.22s` native split-item animation; the whole region, Add Folder control, and source tracking separator disappear, the sidebar control becomes a fixed `30pt` native glass circle, and the `200pt` content-list item becomes leftmost while retaining its current library title at the Notes-matched collapsed origin. Native separators align the list and editor beneath the titlebar in both states. Persisted widths, compact `184x32pt` zero-gap source rows, explicit `4pt` iCloud-heading and `6pt` Tags section breaks, shared counts, deferred loading, disclosure, recently deleted, keyboard hierarchy navigation, drag targeting, and field-editor-backed inline create/rename remain intact. The non-core call-recordings source remains intentionally omitted; deeper hierarchy tuning remains open.
- Note-list rows show Notes-like three-line metadata with title, date-plus-preview without duplicated weekday prefixes, a separate folder/tags row with a folder icon, bounded body previews, a darker Notes-like column, a true filesystem-backed all-notes scope, `54pt` recency groups with a fixed title baseline and `76pt` note rows, reference-matched `20pt` group headings, `15pt` selection starts, `40pt` content baselines, asymmetric selected-card breathing room around the scrollbar, and a Notes-style list-options hierarchy with persistent edit-date/creation-date/title sorting plus optional date grouping. The list is anchored below its pane safe area and uses nonfloating recency headers so selection-driven scrolling cannot hide the first note under a group title. Creation metadata reuses the indexed file-signature read, and group headers plus visible row dates follow the active date basis. A persistent `Pinned` group stays above date groups and follows note rename/move/delete lifecycles; single- and multi-note pin/unpin actions, search-result relevance order preservation, shared-snapshot folder/tag filtering, centralized horizontal spacing, quieter selection/hover states, subtle row separators, Markdown file drag-out, scan-free configured-root drag targeting, drag-to-folder moves, multi-selection file actions, multi-note move/delete/copy/export, piled drag previews, attachment indicators, local image thumbnails, launch-safe shell-first hydration, keyboard browsing, and empty states are present. Drag hit testing rejects external files and internal attachment resources without indexing the library on the main thread. The unlocked content-state side-by-side capture confirms the added group spacing preserves complete first rows and stable recency rhythm; deeper drag-and-drop polish remains open.
- Editor now uses a safe-area-anchored centered date-only header for loaded notes, a reference-aligned `18pt` safe-area origin, explicit left-aligned note titles, debounced autosave that leaves the displayed timestamp unchanged while editing and refreshes it from the file modification date after a successful save, compact `24pt` Notes-like title typography, a `15pt` body reading size, restrained line rhythm, clear-reference-matched `8pt` date-to-title spacing, and a shared `23–24pt` visible reading edge produced by a `22pt` outer inset plus only `2pt` of TextKit body padding. Successful autosave also reprojects visible list title, preview, edit date, sorting, grouping, selection, and source counts directly from the updated memory snapshot; active searches refresh off the main actor. Empty notes and no-selection states keep a quiet blank canvas instead of showing a custom instructional overlay; deeper content-state tuning for complex notes remains open.
- Rich editor provides a stateful Notes-style `Aa` menu with idempotent H1/H2/H3/Body selection, checklist/bullet/numbered styles, and bold/italic/underline/strikethrough while dedicated toolbar actions retain toggle behavior. It renders Markdown tables as native editable AppKit grids while preserving portable Markdown on disk; the table uses a `99.25%` content width so all four border edges remain inside the drawable text-container bounds. Table workflows include Tab/Shift-Tab navigation, automatic row creation, row/column insertion and deletion, Command-Delete row removal, and context menus. Links use a Notes-style two-field sheet with validation and editable labels/addresses. Attachment insertion, local previews, Quick Look, rich/file/image paste, Markdown export/copy, and stable relative attachment storage are present; embedded rich-media paste and richer inline attachment types remain open.
- Search is in the top toolbar and supports current/all scoping with visible row highlights, editor-side match highlights, no-result feedback, multi-result stepping from the search field, keyboard loading into the editor, debounced typing reloads with immediate keyboard-command flush, cancellable detached search-result refreshes, search reloads that skip unrelated source-count refreshes, background indexing status during full-library hydration, and a prewarmed lightweight Markdown index with disk-backed snapshot persistence. Same-root refreshes validate all lightweight signatures but reuse unchanged entries from memory or disk, so only added or changed Markdown is reparsed. Folder, exact-tag, and Inbox scopes filter the full-library entries before ranking and limiting instead of replacing the full index root or truncating before scope filtering. An immutable active-search session performs that validation once, then reuses the entries across character and scope changes until search clears or a note/folder mutation invalidates it. A recursive, coalesced FSEvents monitor now invalidates that session and refreshes list metadata after external Markdown or folder changes, while short-lived path suppression prevents Mudsnote's own saves and moves from feeding back into the editor.
- Note switching uses a bounded, modification-date-validated loaded-note cache, retains rendered attributed text for attachment-free notes, and prefetches nearby rows on a utility queue so repeated keyboard navigation avoids redundant disk reads and Markdown rendering without serving stale externally edited files.
- List scrolling uses reused table cells plus bounded `88px` ImageIO thumbnails with positive/negative caching; first-time thumbnail requests are deduplicated and decoded on a utility task, then only still-matching rows are reloaded. Recent-note resolution reuses indexed all-note metadata instead of synchronously reopening up to 80 Markdown files.
- Recently Deleted navigation and counts now paint from a bounded in-memory snapshot. Background library validation hydrates normal and trashed Markdown together off the main actor, while trash, restore, and permanent-delete commands update both snapshots immediately.
- Recently Deleted keyboard search flushes filter cached title, preview, and tag metadata synchronously, then hand off to detached full-text validation so Return and arrow navigation never wait on trash-file parsing.
- First-search keyboard flushes across all scopes use loaded metadata when no search session exists, then build and publish the complete indexed session off the main actor; subsequent keyboard flushes reuse that session directly.
- Folder, tag, and Inbox source counts are aggregated from the in-memory note snapshot in one pass, including parent-folder rollups and case-insensitive per-note tag deduplication, instead of filtering the whole library once per visible source. Initial full-library hydration builds this index on the same background task and reuses it only if the visible folder-path set is unchanged.
- Post-save source-count aggregation now runs in a cancellable utility task with generation and folder-path guards, while visible row metadata remains immediate; autosave no longer performs the up-to-10,000-note count pass on the main actor.
- Source, folder, tag, recent-note, and empty-search navigation now paints from the loaded library snapshot immediately, then runs a coalesced cancellable filesystem-index validation off the main actor. Generation checks reject stale validation results; save, move, trash, restore, folder rename, and folder deletion update snapshot paths and metadata immediately, so external Markdown changes remain visible without making repeated navigation block on a full file-signature scan.
- Visual QA has a repeatable active-window side-by-side harness with quiet source-loading rows, pointer-hover suppression before capture, explicit frontmost-app verification, physical external-display preference when one is connected, deterministic expanded/collapsed source-list state, true window-only capture normalization with bottom-to-top coordinate conversion for full-screen fallback crops, point/pixel/backing-scale/window-bounds/capture-mode metadata, explicit `2x` point metrics for the checked-in Retina references, fixture-and-sidebar-state routing to the matching Apple Notes reference, same-region `304x292pt` collapsed comparison, focus-stable requested-note selection that avoids an editor caret in comparison captures, canonical `1080x720` sizing, reference-scale shell geometry, and a compact no-rim toolbar baseline. The accepted scale comparison is stored under `docs/visual-qa/compact-scale-comparison.png`.

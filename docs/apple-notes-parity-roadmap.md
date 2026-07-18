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
- Packaged app smoke now covers direct launch, create/edit/save, search, delete to Recently Deleted, restore, folder move, Finder-file attachment paste, portable storage, and attachment rendering after relaunch through `scripts/library_smoke.sh`.
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
- persistent native list/gallery presentation with `Command-1` / `Command-2`, same-note selection preservation, and scan-free projection from the loaded snapshot
- stale recent-file references self-heal during asynchronous launch hydration without adding a synchronous filesystem scan
- visible uncached-note selection reads Markdown off the main thread, cancels stale requests, and keeps adjacent prefetch lower priority than the active selection

Exit criteria: searching and returning to old notes is faster than manually navigating folders.

### P4: Polish And Parity States

Objective: close visible mismatch and edge-state gaps.

- hover/selection/focus polish
- empty, loading, no-result, trash, and locked/unavailable states
- toolbar disabled states
- accessibility labels, concise three-pane VoiceOver semantics, and stateful folder-disclosure actions
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

- Toolbar uses Notes-like unified titlebar chrome so traffic lights and controls share one row, with split-view-tracking separators aligned to the source/list/editor pane boundaries. Expanded Add Folder uses a trailing-aligned `63pt` wrapper so it and Sidebar Toggle land at the measured Apple Notes positions without an extra spacer item or overflow chevron. Both expanded source actions keep native hover-only `.toolbar` controls but use a dedicated `13pt` SF Symbol configuration; equal-scale `2x` QA matches Apple Notes' visible `44x31px` folder and `38x30px` sidebar boundaries within one pixel without changing the `30pt` hit areas. The runtime layout regression additionally requires the final AppKit button images to remain `20x15pt` and `18x14pt`, so a generic `19pt` toolbar symbol cannot replace the calibrated images unnoticed. New Note uses a trailing-aligned native `30pt` glass button inside a `44pt` layout slot, placing its center within roughly `2pt` of the normalized reference's editor-divider offset; a native fixed gap then precedes the editor tools, while flexible space separates that command cluster from a reference-width `160x32pt` Search field in a matching `160x36pt` wrapper. The currently unnecessary share and ellipsis controls are absent. New Note uses its own `13pt` compact-glass symbol while the collapsed Sidebar Toggle retains `12pt`; both remain native macOS 26 `.glass` buttons with unscaled image drawing. Editor format/checklist/table/link/attachment actions retain one reference-width `155x32pt` `NSGlassEffectView` with five `31pt` tracks, trailing-aligned in a transparent `162pt` toolbar slot so the capsule bounds match the normalized Notes reference. Group icons use an editor-only `13pt` SF Symbol configuration and `Aa` is native `17pt` text; their rendered boundaries match the reference within two Retina pixels, and the item-level border is disabled so only the glass surface draws an outline. Each track remains a native `.toolbar` button whose border appears only under the pointer, so AppKit owns hover and pressed feedback without custom CALayer rendering. Disabled state remains an efficient group-level fade with icon-level command availability. Menu-backed editor commands use normal AppKit click-release activation and a centered button-relative lower-edge anchor. List sorting and date grouping remain available through state-validated native View-menu commands without restoring toolbar clutter. Stateful source-list toggling, restrained symbols, and native app/File/Edit/View/Window commands remain present; further toolbar tuning should follow same-state visual evidence rather than global symbol changes.
- The checked-in Apple Notes references include a uniform `5pt` black capture margin; visual QA removes it before measuring. The resulting canonical shell is `921x613pt` with `200/200pt` logical source/list defaults, and the rendered `2x` dividers align with the normalized reference at `x=416px` and `x=816px`. Source/list widths, source visibility, and the whole workspace frame persist across launches. Restored frames are clamped onto the nearest visible display, while canonical visual QA ignores personal frame state. Layout migration version 8 recenters only exact previous-default `940x630`, `1080x680`, and `1080x720pt` frames and replaces exact prior `205/200pt` pane defaults; manually resized windows and panes remain intact.
- Source list is a full-height native `NSSplitViewItem.sidebar` with a darkened native material and `24pt` rounded clipping boundary covering the titlebar, traffic lights, Add Folder, and sidebar-toggle controls in expanded mode. The material does not draw a second outline over AppKit's native sidebar edge. Its rows begin below the titlebar safe area. User collapse runs through a `0.22s` native split-item animation; the whole region, Add Folder control, and source tracking separator disappear, while the sidebar control becomes a `30pt` native glass circle trailing-aligned inside a `34pt` compact wrapper. The `200pt` content-list item becomes leftmost, and its `13pt` library title uses independent measured offsets of `12pt` when expanded and `-11.5pt` when collapsed, with a geometric non-overlap contract. Native separators align the list and editor beneath the titlebar in both states. The source hierarchy itself is a public AppKit `NSOutlineView` using `.sourceList` style, so AppKit owns row reuse, scrolling, disclosure, keyboard traversal, selection, field-editor-backed inline create/rename, context menus, and drag/drop. `iCloud` and `Tags` are real expandable root parents: All iCloud, local folders, and Recently Deleted live under iCloud, while tag scopes remain modeled beneath Tags even when collapsed. AppKit therefore exposes native expanded/collapsed rows and system disclosure accessibility actions; persisted disclosure skips unnecessary background loading and restores the active scope selection when reopened. Mudsnote supplies compact `32pt` rows, `13.5pt` regular labels, `12pt` section headings, and `15pt` symbols rendered in a `22x20pt` native image slot so their canvas is not downscaled; a `7.5pt` content inset and `3pt` icon-title gap align symbol trailing edges and title origins with the reference. Selection and hover use independent `10/10/0pt` row-highlight insets rather than scroll content padding, producing the same `180x32pt` rounded surface as Apple Notes without moving row content. Local folder/tag/trash scopes, shared counts, deferred background hierarchy loading, snapshot-backed projection without main-thread filesystem I/O, incremental create/rename/delete updates, and stale-load generation rejection remain present. A 600-folder regression instantiates fewer than 40 visible cells. Equal-scale OCR places the main source-label widths within roughly `1–4%` of the Apple Notes reference, while live same-height capture aligns source icons and group headings. The non-core call-recordings source remains intentionally omitted; deeper hierarchy tuning remains open.
- Note-list rows show Notes-like three-line metadata with title, date-plus-preview without duplicated weekday prefixes, tail-truncated attributed previews, a separate folder/tags row with a folder icon, bounded body previews, a darker Notes-like column, a true filesystem-backed all-notes scope, reference-height `45pt` recency groups with `15pt` bold headings, and `76pt` note rows. The first group title uses a `15pt` bottom inset while following groups use `2pt`, matching Apple's larger pre-heading breathing room without changing row height. Against the normalized reference, selected cards use `10/27pt` leading/trailing and asymmetric `6/4pt` top/bottom insets; note text starts at `35pt`, uses `2.5pt` row spacing plus `4.5/7.5pt` top/bottom content insets, and preserves `10pt` inside the selected surface. Unthumbnailed rows fill the available horizontal space instead of retaining intrinsic stack width, while lowered compression resistance and a bounded trailing constraint keep long titles, previews, and metadata truncated inside the visible surface. The table owns one hover row and reconciles it against the current pointer and visible rect on every scroll, preventing reused/traversed rows from retaining hover paint. The list is anchored below its pane safe area and uses nonfloating recency headers so selection-driven scrolling cannot hide the first note under a group title. Creation metadata reuses the indexed file-signature read, and group headers plus visible row dates follow the active date basis. A persistent `Pinned` group stays above date groups and follows note rename/move/delete lifecycles; single- and multi-note pin/unpin actions, search-result relevance order preservation, shared-snapshot folder/tag filtering, centralized horizontal spacing, quieter selection/hover states, subtle row separators, Markdown file drag-out, scan-free configured-root drag targeting, drag-to-folder moves, multi-selection file actions, multi-note move/delete/copy/export, piled drag previews, attachment indicators, local image thumbnails, launch-safe shell-first hydration, keyboard browsing, and empty states are present. Drag hit testing rejects external files and internal attachment resources without indexing the library on the main thread. Normalized `2x` collapsed captures give identical Apple Notes/Mudsnote selected-card bounds of `20,204–345,339px`; deeper drag-and-drop polish remains open.
- A persisted native gallery mode is available through View > Show as Gallery (`Command-2`), with Show as List (`Command-1`) restoring the canonical three-pane workspace. Gallery mode collapses only the content-list split item, keeps the Notes-like source sidebar, and fills the remaining pane with grouped `NSCollectionView` preview cards. It reuses the bounded 240-note list projection, thumbnail cache, async decode tasks, selection model, drag writers, context menus, and source/search scopes; no additional filesystem enumeration or note index is introduced. Hidden gallery state retains only its pure in-memory section projection, so list-mode launch cannot instantiate collection cells or synchronously decode gallery previews. Double-click and Return open the same selected note in the list/editor workspace, New Note returns to list mode, and empty/search/trash states remain visible. A 10,000-row grouping regression stays below `100ms`; installed same-input comparison is `/tmp/mudsnote-gallery-vs-notes.jpg`. Richer document-page rendering inside text-only cards remains a future fidelity opportunity.
- Editor now uses a safe-area-anchored date-only header for loaded notes, a normalized-reference `6.25pt` date-row origin and `-8.5pt` horizontal center offset, explicit `.fill` vertical distribution, explicit left-aligned note titles, debounced autosave that leaves the displayed timestamp unchanged while editing and refreshes it from the file modification date after a successful save, compact `24pt` Notes-like title typography, a `15pt` body reading size, restrained line rhythm, `10.75pt` date-to-title spacing, and a `25pt` body reading edge produced by a `23pt` outer inset plus only `2pt` of TextKit body padding. The top-inset and date-spacing sum remains `17pt`, moving only the date upward while preserving the already aligned title/body origin; the horizontal offset matches the reference's visible editor region without shifting content. Successful autosave also reprojects visible list title, preview, edit date, sorting, grouping, selection, and source counts directly from the updated memory snapshot; active searches refresh off the main actor. Rich Markdown serialization snapshots the immutable source string once per save and caches font traits per font identity, keeping a 5,000-run debug workload near `27ms` instead of repeatedly bridging the whole document. Empty notes and no-selection states keep a quiet blank canvas instead of showing a custom instructional overlay; deeper content-state tuning for complex notes remains open.
- Rich editor provides a stateful Notes-style `Aa` menu with idempotent H1/H2/H3/Body selection, checklist/bullet/numbered styles, and bold/italic/underline/strikethrough while dedicated toolbar actions retain toggle behavior. It renders Markdown tables as native editable AppKit grids while preserving portable Markdown on disk; the table uses a `99.25%` content width so all four border edges remain inside the drawable text-container bounds. Table workflows include Tab/Shift-Tab navigation, automatic row creation, row/column insertion and deletion, Command-Delete row removal, and context menus. Links use a Notes-style two-field sheet with validation and editable labels/addresses. Attachment insertion, local previews, Quick Look, rich/file/image paste, Markdown export/copy, and stable relative attachment storage are present; embedded rich-media paste and richer inline attachment types remain open.
- Search is in the top toolbar and supports current/all scoping with visible row highlights, editor-side match highlights, no-result feedback, multi-result stepping from the search field, keyboard loading into the editor, debounced typing reloads with immediate keyboard-command flush, cancellable detached search-result refreshes, search reloads that skip unrelated source-count refreshes, background indexing status during full-library hydration, and a prewarmed lightweight Markdown index with disk-backed snapshot persistence. Same-root refreshes validate all lightweight signatures but reuse unchanged entries from memory or disk, so only added or changed Markdown is reparsed. Folder, exact-tag, and Inbox scopes filter the full-library entries before ranking and limiting instead of replacing the full index root or truncating before scope filtering. An immutable active-search session performs that validation once, then reuses the entries across character and scope changes until search clears or a note/folder mutation invalidates it. A recursive, coalesced FSEvents monitor now invalidates that session and refreshes list metadata after external Markdown or folder changes, while short-lived path suppression prevents Mudsnote's own saves and moves from feeding back into the editor.
- Note switching uses a bounded loaded-note cache, retains rendered attributed text for attachment-free notes, and prefetches nearby rows on a utility queue. Cache hits paint immediately; file modification-date validation and any stale Markdown reload run in one detached utility task with cancellation, selection-generation, selected-path, and dirty-editor guards, so repeated keyboard navigation avoids both redundant rendering and synchronous filesystem metadata reads without serving stale external edits.
- List scrolling uses reused table cells plus bounded `88px` ImageIO thumbnails with positive/negative caching; first-time thumbnail requests are deduplicated and decoded on a utility task, then only still-matching rows are reloaded. Recent-note resolution reuses indexed all-note metadata instead of synchronously reopening up to 80 Markdown files.
- Recently Deleted navigation and counts now paint from a bounded in-memory snapshot. Background library validation hydrates normal and trashed Markdown together off the main actor, while trash, restore, and permanent-delete commands update both snapshots immediately.
- Recently Deleted keyboard search flushes filter cached title, preview, and tag metadata synchronously, then hand off to detached full-text validation so Return and arrow navigation never wait on trash-file parsing.
- First-search keyboard flushes across all scopes use loaded metadata when no search session exists, then build and publish the complete indexed session off the main actor; subsequent keyboard flushes reuse that session directly.
- Folder, tag, and Inbox source counts are aggregated from the in-memory note snapshot in one pass, including parent-folder rollups and case-insensitive per-note tag deduplication, instead of filtering the whole library once per visible source. Initial full-library hydration builds this index on the same background task and reuses it only if the visible folder-path set is unchanged.
- Post-save source-count aggregation runs in a cancellable utility task with generation and folder-path guards, while visible row metadata remains immediate. Snapshot mutation no longer re-sorts up to `10,000` notes on the main actor: it removes matching raw paths, binary-searches the existing modified-date order, inserts once, and trims once. URL normalization is confined to the save boundary, and a debug-build `10,000`-entry regression gate keeps this update below `50ms`.
- Inbox, folder, and tag navigation project directly from the loaded snapshot into a bounded 240-note result. The projection preserves snapshot order, reserves only visible capacity, and stops after the final visible match instead of materializing every match across the 10,000-note snapshot.
- Non-default title and creation-date sorting apply the visible limit after global scope ordering. A chunked top-K projection retains at most twice the 240-note window, precomputes date-group and pinned keys, and keeps the 10,000-note grouped-title path below `100ms` in debug tests; the default edit-date path still stops after its final visible match.
- Source, folder, tag, recent-note, and empty-search navigation now paints from the loaded library snapshot immediately, then runs a coalesced cancellable filesystem-index validation off the main actor after one cooperative yield and without a fixed debounce delay. Generation checks reject stale validation results; save, move, trash, restore, folder rename, and folder deletion update snapshot paths and metadata immediately, so external Markdown changes remain visible without making repeated navigation block on a full file-signature scan.
- Visual QA has a repeatable active-window side-by-side harness with quiet source-loading rows, pointer-hover suppression before capture, explicit frontmost-app verification, physical external-display preference when one is connected, deterministic expanded/collapsed source-list state, a dedicated collapsed fixture that matches the checked-in reference selection and date groups, true window-only capture normalization with bottom-to-top coordinate conversion for full-screen fallback crops, point/pixel/backing-scale/window-bounds/capture-mode metadata, explicit `2x` point metrics for the checked-in Retina references, fixture-and-sidebar-state routing to the matching Apple Notes reference, automatic four-edge `5pt` content-margin removal for built-in references, same-region `294x282pt` collapsed comparison, focus-stable requested-note selection that avoids an editor caret in comparison captures, canonical `921x613pt` sizing, normalized source/fixture metadata, reference-scale shell geometry, and a compact no-rim toolbar baseline. The accepted scale comparison is stored under `docs/visual-qa/compact-scale-comparison.png`.

# Mudsnote AI Handoff

## Latest iteration (156)

- Save progress no longer replaces the editor status/time text; the library date updates from the file modification date only after a successful save.
- Sidebar collapse coordinates split-item animation, title offset, and toolbar visibility state.
- The unused list ellipsis is removed, and remaining menu-backed toolbar controls use normal click-release activation with a centered lower-edge anchor.

## Latest iteration (157)

- Recently Deleted uses a bounded in-memory snapshot for navigation and counts.
- Background source validation loads normal and trashed notes together off the main actor.
- Trash, restore, and permanent-delete commands update the snapshot immediately.

## Latest iteration (158)

- Recently Deleted keyboard search flushes use cached title, preview, and tag metadata immediately.
- A detached full-text search replaces the provisional result, preserving body-only matches without blocking keyboard interaction.

## Latest iteration (159)

- First-search keyboard flushes use scope-filtered snapshot metadata instead of building the search index on the main actor.
- Detached indexed search publishes the reusable full-text session afterward; established sessions still rank synchronously in memory.

## Latest iteration (160)

- View > Sort By exposes edit-date, creation-date, and title sorting without restoring the toolbar ellipsis.
- View > Group By Date uses native menu validation to reflect live or persisted state.

## Latest iteration (161)

- Default/canonical library geometry is `940x630pt`, close to the `931x623pt` Apple Notes reference.
- Version-5 migration recenters only exact old-default frames and preserves custom window sizing.

## Latest iteration (162)

- Successful autosave immediately updates visible list metadata, ordering, groups, selection, and counts from the in-memory snapshot.
- Search-state saves schedule detached result refresh instead of synchronously rebuilding the index.

## Latest iteration (163)

- Post-save folder/tag/Inbox count aggregation runs on a cancellable utility task with generation and folder-set guards.
- Visible note rows still update synchronously from memory before aggregate counts publish.

## Latest iteration (164)

- The full-height source surface retains its rounded clipping and darkened native material without drawing a second layer border.
- AppKit remains the sole owner of the sidebar and split-pane edge treatment.

## Latest iteration (165)

- Collapsed and expanded note lists share reference-measured horizontal baselines: `20pt` group headings, `15pt` selection starts, and `40pt` row content.
- The `200pt` content-list pane and scrollbar clearance remain unchanged.

## Latest iteration (166)

- Editor title and body now share a Notes-like `23–24pt` visible reading edge.
- The outer stack uses `22pt`; TextKit contributes only another `2pt` to body text.

## Latest iteration (167)

- Expanded source-pane default/minimum width is `212pt`, with `184pt` inset rows.
- Layout migration version 6 replaces only exact previous `220/200pt` defaults and preserves custom pane widths.

## Latest iteration (168)

- Editor date-to-title spacing is `8pt`, based on the user's clear Apple Notes title crop.
- Title and body move together; the centered date and toolbar geometry remain unchanged.

## Latest iteration (169)

- Source rows use a compact `32pt` zero-gap rhythm matching Apple Notes.
- The iCloud heading retains `4pt` separation and Tags retains a deliberate `6pt` section break.

## Latest iteration (170)

- Note-list date groups use `45pt` rows with a `15pt` title bottom inset.
- Group headings and first note cards align vertically in both expanded and collapsed reference states.

## Latest iteration (171)

- Toolbar order is New Note, fixed space, editor tools, flexible space, Search.
- New Note to editor-tools separation measures about `19.5pt`, close to the `18.5pt` reference gap; share and ellipsis remain omitted.

## Latest iteration (172)

- Toolbar search uses a `160x32pt` field in a `180x36pt` wrapper.
- Search behavior and focus contracts are unchanged; only horizontal toolbar occupancy was reduced.

## Latest iteration (173)

- The editor content stack begins `12pt` below the safe-area boundary instead of `18pt`.
- Date, title, and body move upward together; their internal spacing and shared horizontal reading edge remain unchanged.

This document is the fastest safe handoff for another AI taking over `Mudsnote`.

## Read Order

1. `README.md`
2. `AGENTS.md`
3. `docs/AI_HANDOFF.md`
4. `CHANGELOG.md`
5. `docs/REFACTOR_LOG.md` if you need to understand why a file was split or where something moved
6. `docs/raycast-notes-benchmark.md` if the task is about product direction, search, metadata density, or Notes/Raycast parity

## Product Summary

`Mudsnote` is a pure SwiftPM macOS menu bar app for fast Markdown capture and lightweight note editing.

Current core behavior:

- menu bar app with status item
- global quick-capture hotkey
- separate floating note hotkey
- full editor windows for existing notes
- search window
- preferences window
- plain `.md` storage on disk
- autosaved drafts
- recent files menu
- compatibility migration from legacy `QuickMarkdown` settings and paths

Current branding:

- app name is `Mudsnote`
- packaged app path is `/Applications/Mudsnote.app`
- generated app assets live under `assets/`

## Architecture Map

### Entry and orchestration

- `Package.swift`
  Defines the two targets: `MudsnoteCore` and executable `Mudsnote`.
- `Sources/Mudsnote/main.swift`
  App entry point.
- `Sources/Mudsnote/AppController.swift`
  App lifecycle, status menu, global hotkeys, window creation, reuse, and routing.

### Persistence and settings — `Sources/MudsnoteCore/`

Split into focused files (see `docs/REFACTOR_LOG.md` for full rationale):

- `Models.swift` — value types: `NoteFile`, `NoteSearchResult`, `DraftSnapshot`, `StoredWindowFrame`, `StoredWindowOrigin`, `MarkdownEditorDocument`
- `NoteStore.swift` — class declaration, init, stored properties, shared helpers
- `NoteStore+Settings.swift` — `NoteStoreDefaultsKey` enum, all `UserDefaults`-backed properties and frame persistence
- `NoteStore+Migration.swift` — legacy `QuickMarkdown` → `Mudsnote` migration (do not delete until users are confirmed migrated)
- `NoteStore+Drafts.swift` — `saveDraft`, `loadDraft`, `deleteDraft`
- `NoteStore+Notes.swift` — `loadNote`, `saveNewNote`, `updateNote`, `listRecentFiles`, YAML parsing, filename slug
- `NoteStore+Search.swift` — `searchNotes`, `knownTags`, `knownSearchRoots`, scoring

### Chrome building blocks — `Sources/Mudsnote/Chrome/`

Split into focused files:

- `Helpers.swift` — `pin`, `insetted`, `sha256Hex`, `chooseDirectory`, `displayPath`, `positionPanelNearTopCenter`
- `Palette.swift` — semantic color functions (`panelAccentColor`, etc.)
- `OpacityMath.swift` — opacity math and `WindowOpacityAdjusting` protocol
- `Surfaces.swift` — `makeModernSurface`, `GradientBackdropView`
- `Buttons.swift` — `HoverToolbarButton`, `FocusAwareAccentButton`, `FocusAwareSecondaryButton`, style helpers
- `Scrolling.swift` — `SlimScroller`, `ScrollIndicatorOverlay`
- `Panels.swift` — `QuickEntryPanel` + `HitCatchingView` (co-located — `fileprivate` coupling)
- `DragHosts.swift` — `WindowMoveBackgroundView`, `SubviewPassthroughView`, `FocusProxyContainerView`, `FocusableTextField`, `DragHandleView`, `PassthroughOverlayView`

### Editor controller — `Sources/Mudsnote/`

Split into focused extension files (same `EditorWindowController` class, no behavior change):

- `EditorWindowController.swift` — class declaration, nested enums, all stored properties, `init`, public interface, window delegate, protocol stubs
- `EditorWindowController+UI.swift` — `buildUI`, `buildStandardEditorUI`, `buildQuickCaptureUI`, button factories, observers, content loading, chrome refresh
- `EditorWindowController+TextHelpers.swift` — text manipulation primitives, shortcut routing, `userDidEdit`
- `EditorWindowController+Draft.swift` — autosave timer, `persistDraft`, `currentDocument`, `serializedBodyMarkdown`
- `EditorWindowController+Formatting.swift` — paragraph kind, inline font traits, strikethrough/underline, toolbar state, keyboard shortcuts, button actions
- `EditorWindowController+TagsAndSuggestions.swift` — tag token matching, inline suggestion popover, slash commands, tag menu
- `EditorWindowController+Save.swift` — `savePressed`, `cancelPressed`, `searchPressed`, `quickCaptureDirectoryPressed`, error alerts
- `EditorWindowController+Appearance.swift` — reveal animation

### Other editor/UI files

- `Sources/Mudsnote/MarkdownRichEditor.swift`
  Rich text editor behavior, Markdown round-trip, list/checklist handling, text view subclasses, and editor scroll/clip views.
- `Sources/Mudsnote/QuickCaptureDocumentState.swift`
  Quick-capture-specific title/body/tag shaping and tag toggling.
- `Sources/Mudsnote/SuggestionPopoverController.swift`
  Inline suggestion UI for tags and slash commands.

### Supporting windows

- `Sources/Mudsnote/SearchWindowController.swift`
- `Sources/Mudsnote/PreferencesWindowController.swift`
- `Sources/Mudsnote/Branding.swift`
- `Sources/Mudsnote/HotKey.swift`

### Tests

- `Tests/MudsnoteCoreTests/`
  Store, migration, drafts, recent files, frame persistence, search.
- `Tests/MudsnoteAppTests/MarkdownRichEditorTests.swift`
  Markdown rendering/serialization plus quick-capture UI-support helpers.

## Current UX Direction

The user has repeatedly pushed `Mudsnote` toward a more native macOS utility-panel feel, especially for quick capture.

The current desktop goal is full Apple Notes core-function and UI parity for the macOS library window, bounded by local-first Markdown storage. Use `docs/apple-notes-parity-roadmap.md` as the checklist before choosing new desktop UI work.

The important quick-capture direction remains:

- quick capture is not a shrunken full editor
- quick capture has separate `title + body`
- quick capture uses a dedicated bottom shelf for destination and save/cancel
- quick capture metadata actions are sparse and visually light
- title/body must remain easy to re-focus after moving between fields
- shared panel chrome should feel native, not like a custom HUD

Do not casually revert these choices.

## Quick Capture Rules

If the task touches quick capture, assume the hot files are:

- `Sources/Mudsnote/EditorWindowController.swift`
- `Sources/Mudsnote/Chrome/`
- `Sources/Mudsnote/MarkdownRichEditor.swift`
- `Sources/Mudsnote/QuickCaptureDocumentState.swift`

Quick-capture-specific rules that now matter:

- keep title and body as genuinely separate inputs
- do not fake title/body separation by parsing a single editor later
- do not reintroduce the full editor toolbar into quick capture unless the user explicitly asks
- icon/text density is a product decision, not just a code cleanup
- keep the title header clickable after focus moves into the body
- when using borderless panels, blank container views must not swallow drag or focus gestures

## Verification Standard

For meaningful UI or editor changes, use this baseline:

1. `swift test`
2. `./scripts/package_app.sh`
3. Launch the packaged app, not only the debug binary

Useful launch modes:

- `/Applications/Mudsnote.app --args --quick-capture`
- `/Applications/Mudsnote.app --args --search`
- `/Applications/Mudsnote.app --args --preferences`

The visual Notes QA script passes `--visual-qa-external-screen`; when a physical external display is connected, the canonical test window is centered there so UI automation does not occupy the built-in display.

Packaged-app smoke expectations depend on the task, but for quick capture they should usually include:

- confirm the panel opens
- confirm title and body are both editable
- confirm focus can move from title to body and back
- confirm `Save` still writes a correct Markdown file
- confirm draft restore still works if the flow touched persistence

Do not trust screenshots alone for input/focus changes.

## Known Limits And Caveats

- Transparent borderless panel live-resize still has some system shadow/compositing edge cases.
- Synthetic drag verification is unreliable in this workspace for borderless panels; manual confirmation or broader smoke evidence is more trustworthy than raw CGEvent replay.
- Accessibility scripting is useful for smoke tests, but some text-entry flows remain less stable than direct manual interaction.

## Safe Change Strategy

When another AI takes over, the safest sequence is:

1. identify whether the task is core-store, window orchestration, quick capture, search, preferences, or branding
2. open only the hot files for that slice
3. make the smallest change that preserves the current UX direction
4. run unit tests
5. rebuild the packaged app
6. do one real packaged-app smoke aligned to the changed behavior
7. if the change establishes a new durable rule, update local docs or workspace memory

## Recommended Starting Points By Task

### Persistence, defaults, migration, drafts

Start with:

- `Sources/MudsnoteCore/`
- `Tests/MudsnoteCoreTests/`

### Quick capture or floating note UX

Start with:

- `Sources/Mudsnote/EditorWindowController.swift`
- `Sources/Mudsnote/Chrome/`
- `Sources/Mudsnote/MarkdownRichEditor.swift`
- `Tests/MudsnoteAppTests/MarkdownRichEditorTests.swift`

### Search and list density

Start with:

- `Sources/Mudsnote/SearchWindowController.swift`
- `Sources/MudsnoteCore/`
- `docs/raycast-notes-benchmark.md`

### Preferences, hotkeys, app menu behavior

Start with:

- `Sources/Mudsnote/AppController.swift`
- `Sources/Mudsnote/PreferencesWindowController.swift`
- `Sources/Mudsnote/HotKey.swift`
- `Sources/MudsnoteCore/`

### Branding, iconography, menu bar image

Start with:

- `Sources/Mudsnote/Branding.swift`
- `assets/source/`
- `scripts/generate_icon_assets.sh`
- `scripts/package_app.sh`

## What Another AI Should Avoid

- Do not rename paths, defaults, or directories again unless the user explicitly asks.
- Do not delete legacy migration support unless the user is done with compatibility.
- Do not rely on only one screenshot as proof for editor or focus fixes.
- Do not treat `CHANGELOG.md` as a substitute for reading the implementation.
- Do not assume quick capture and full editor should share the same chrome.

## Minimal Handoff Prompt

If you need to hand the project from one AI to another, this prompt is enough:

> Work in the repo root. Read `README.md`, `AGENTS.md`, and `docs/AI_HANDOFF.md` first. Preserve the current native-macOS quick-capture direction: separate title/body, light metadata rail, bottom destination/save shelf, and reliable title/body refocus. Validate nontrivial changes with `swift test`, `./scripts/package_app.sh`, and a packaged-app smoke test relevant to the edited behavior.

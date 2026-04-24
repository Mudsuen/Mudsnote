# Mudsnote AI Handoff

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

The important current direction is:

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

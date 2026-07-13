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

- The editor content stack began `12pt` below the safe-area boundary instead of `18pt`; iteration 184 refined this to `6pt` from the newer clear reference.
- Date, title, and body move upward together; their internal spacing and shared horizontal reading edge remain unchanged.

## Latest iteration (174)

- Expanded Add Folder and Sidebar Toggle align with Apple Notes through a trailing-aligned `68pt` Add Folder wrapper, without introducing a spacer toolbar item or overflow chevron.
- The five-button editor-tools glass group is `155pt` wide with `31pt` button tracks, matching the measured reference density.

## Latest iteration (175)

- Collapsed Sidebar Toggle uses a trailing-aligned `34pt` wrapper around the existing `30pt` glass control; expanded state remains unchanged.
- The collapsed list title originally used a `-58pt` state offset; iteration 186 recalibrated it to `-7pt` and added a non-overlap geometry contract for the current toolbar layout.

## Latest iteration (176)

- The source split item uses a `205pt` logical default/minimum so its rendered native sidebar edge lands within about `3pt` of Apple Notes.
- Source rows are `180pt` wide with `14/11pt` horizontal insets; migration version 7 updates only untouched `212/200pt` pane defaults.

## Latest iteration (177)

- The editor vertical stack uses `.fill`, so the date and title remain tightly anchored at the top and the body receives all flexible height.
- Visual comparison: `/tmp/mudsnote-editor-stack-fill-177/apple-notes-vs-mudsnote.png`.

## Latest iteration (178)

- Source navigation still paints from the in-memory snapshot first, then starts detached filesystem validation after a cooperative yield rather than a fixed `80ms` delay.
- Cancellation and generation checks continue to reject stale validations; the focused race test passed 10 consecutive runs and the full suite passed.

## Latest iteration (179)

- The source surface, note list, search scope, title field, editor body, and modification-date label now expose stable accessibility names.
- Visual source-count labels are excluded from the accessibility tree; the owning source button exposes the count as its accessibility value instead.

## Latest iteration (180)

- Nested-folder disclosure buttons expose the concrete folder name and current expand/collapse action to VoiceOver.
- The label is regenerated with each source-row rebuild, so it stays aligned with persisted disclosure state.

## Latest iteration (181)

- `scripts/library_smoke.sh` exercises the installed three-pane app against an isolated temporary library.
- It proves direct library launch, `Command-N`, title/body editing, autosave to exact Markdown, search filtering, trash/restore, folder move, Finder-file attachment paste, portable attachment storage, and attachment rendering after relaunch.

## Latest iteration (182)

- The File menu now exposes state-validated "移到最近删除" and "恢复笔记" actions while leaving the compact toolbar unchanged.
- `scripts/library_smoke.sh` proves both actions against isolated filesystem state.

## Latest iteration (183)

- The File menu now exposes a state-validated "移到文件夹" submenu populated from the current library hierarchy without adding toolbar chrome.
- `scripts/library_smoke.sh` proves the restored note can be moved into an isolated folder; iteration 185 extends the same installed workflow through attachment rendering and relaunch.

## Latest iteration (184)

- The editor stack now begins `6pt` below its safe-area boundary, moving the centered date, title, and body upward together.
- The calibrated `8pt` date-to-title spacing, typography, horizontal reading edge, toolbar, and pane geometry remain unchanged.

## Latest iteration (185)

- `scripts/library_smoke.sh` now pastes a real Finder PDF into the installed app and verifies its local copy plus portable relative Markdown link.
- Accessibility evidence proves both the rendered editor attachment and note-list indicator before and after a full app relaunch.

## Latest iteration (186)

- Folder hierarchy loading now produces a complete bounded tree snapshot off the main thread; source disclosure projects visible rows from that snapshot without filesystem I/O.
- The collapsed note-list title uses a measured `-7pt` offset and a geometric test prevents it from intersecting the compact sidebar button.

## Latest iteration (187)

- Collapsed visual QA now seeds the same `感悟` selection and date groups as its Apple Notes reference instead of reusing whichever normal content fixture was requested.
- The compact note-list title/group typography is `13pt/15pt`, the collapsed title offset is `-11pt`, and attributed list previews retain tail ellipsis behavior.
- Editor date-to-title spacing is `4pt`, moving only the title/body rhythm upward while preserving the calibrated date-row origin.

## Latest iteration (188)

- Source labels use `13.5pt` regular text, source section headings use `12pt`, and source symbols use `15pt`; the existing `32pt` rows and pane geometry are unchanged.
- Equal-scale Vision OCR reduced the main source-label width mismatch from roughly `14–16%` to about `1–4%` for Notes, Resources, Archives, and Recently Deleted.

## Latest iteration (189)

- The note table owns a single weak hover row and recomputes it from the current pointer plus `visibleRect` whenever its clip view scrolls, preventing stale hover paint on traversed rows.
- Note text now compresses and tail-truncates within a boundary `10pt` inside the selected card's trailing edge; long-title installed screenshots no longer overflow the gold selection surface.

## Latest iteration (190)

- Loaded-note cache hits paint their cached document immediately without reading filesystem metadata on the main actor.
- A detached utility task validates the file modification date and reloads externally changed Markdown; cancellation, selection generation, selected-path, and dirty-editor checks reject stale or destructive results.
- The regression injects a `350ms` metadata read and requires cached-note selection to return within `150ms` while proving the read never executes on the main thread.

## Latest iteration (191)

- Unthumbnailed note rows use horizontal fill distribution and a low-hugging text stack, so title, date/preview, and folder metadata consume the full safe width instead of truncating at intrinsic width.
- Equal-scale collapsed QA now aligns the selected card at `10pt` from the list edge and `31pt` from the trailing table edge; note text starts at `35pt` and preserves `10pt` inside the selected-card trailing edge.
- The layout regression verifies both near-full available text width and the actual text drawing boundary, not only the label frame.

## Latest iteration (192)

- The library editor stack uses an `18pt` safe-area top inset and `28pt` horizontal inset; date-to-title and title-to-body spacing remain `4pt/8pt`.
- In the deterministic collapsed fixture, the installed title now measures `x=459–546, y=196–238px` at `2x`, against Apple Notes' `x=459–543, y=197–238px`.
- Shared editor-origin calibration must use the current state-matched capture; do not reuse older clear crops without reproducing their exact window, pane, and selected-note state.

## Latest iteration (193)

- Original `2x` pixel inspection supersedes the scaled-montage estimate from iteration 191: selected-card leading/trailing insets are `15/22pt`, note text starts at `40pt`, and separators start at `42pt`.
- The selected surface uses asymmetric `6pt` top and `4pt` bottom insets; its installed bounds exactly match Apple Notes at `30,214–355,349px` in the collapsed fixture.
- First group labels retain a `15pt` bottom inset while following groups use `2pt`; this aligns the second section at `y=418px` without changing the correct `45pt` group or `76pt` note row heights.
- Note metadata uses `2.5pt` vertical spacing and `4.5/7.5pt` top/bottom content insets; the remaining line-bound differences are within roughly `1–2pt` of native font rasterization.

## Latest iteration (194)

- The three checked-in Apple Notes references contain a uniform `5pt` black capture margin. `scripts/visual_notes_qa.sh` now crops those margins before comparison, records source/normalized paths and content insets in metadata, and leaves externally supplied references uncropped by default.
- The normalized expanded reference is `921x613pt`; the canonical window now uses that exact size with `200/200pt` source and note columns. At `2x`, the rendered source and editor dividers align with Apple Notes at `x=416px` and `x=816px`.
- Layout migration version 8 replaces only exact previous `940x630`, `1080x680`, and `1080x720` default frames plus the prior `205/200pt` pane defaults. Customized frames and pane widths remain untouched.
- Normalized collapsed comparison supersedes iteration 193's margin-bearing coordinates: the selected card now matches Apple Notes at `20,204–345,339px`, with `10/27pt` card insets, a `35pt` text start, and a trailing text constraint that keeps long titles inside the card.
- The collapsed title, list stack, and editor content origins were shifted by the same normalized-reference delta. Tightened Add Folder and Search wrappers keep every required toolbar item visible at the smaller canonical width without an overflow chevron.

## Latest iteration (195)

- Vision OCR on the normalized collapsed captures measured the Apple Notes `All iCloud` title at `x=309.7px` and Mudsnote at `x=300.0px`; their vertical origins already matched.
- The collapsed title leading offset is `-11.5pt`, moving only the title about `4.5pt` right while preserving the aligned sidebar button, list card, and editor origins. The `-11pt` and `-12pt` probes landed `2.2px` right and `1.7px` left of the reference respectively, so the final value uses the Retina half-point between them.
- At iteration 195 the expanded title still used `0`; iteration 196 supersedes that historical value with the independently measured `12pt` expanded offset.

## Latest iteration (196)

- Normalized expanded OCR measured the top `All iCloud` title at `x=455.0px` in Apple Notes and `x=430.9px` in Mudsnote, while the `Today` list heading already matched at `x=444.4px`.
- The source-visible title now uses an independent `12pt` leading offset. The source-hidden title retains its measured `-11.5pt` offset, so expanded and collapsed toolbar states no longer share an incorrect local origin.
- State-transition coverage verifies the constraint switches to the collapsed value and restores the expanded value after reopening the source sidebar.
- Final normalized OCR measures expanded Mudsnote at `x=454.9px` versus Apple Notes `x=455.0px`, while collapsed remains `x=309.9px` versus `x=309.7px`.

## Latest iteration (197)

- Expanded empty and content captures placed the centered editor date at `y=136.5px`, versus Apple Notes `y=123.0px`; the collapsed editor title was already within `2px` vertically.
- The editor top inset is now `6.25pt` and date-to-title spacing is `10.75pt`. Their sum remains `17pt`, so the date moves up `6.75pt` while title and body origins remain unchanged.
- Treat the date row and title/body content as independently calibrated vertical relationships; do not move the whole editor stack when only the date baseline differs.
- Final empty and content captures both measure the Mudsnote date at exactly `y=123.0px`; the collapsed editor title remains `y=184px` versus Apple Notes `y=186px`.

## Latest iteration (198)

- After vertical alignment, the Apple Notes date center remained stable at about `x=1311.9px` in both normalized empty and content references, while Mudsnote centered at `x=1328–1329px` over the full editor pane.
- The status label now uses an independent `-8.5pt` horizontal center offset, matching Apple Notes' visible editing region without moving the title, body, pane, or toolbar.
- Keep date-row centering separate from the editor content insets; the native reference accounts for the right-side scrolling region in its perceived center.
- Final empty-state OCR centers Mudsnote and Apple Notes at `x=1311.9px`; content-state Mudsnote centers at `x=1310.6px`, within `1.3px` of the same reference center. The `y=123px` baseline and collapsed title remain unchanged.

## Latest iteration (199)

- New Note and the collapsed Sidebar Toggle use native macOS 26 `.glass` buttons, so AppKit owns their hover and pressed animation.
- The `155x32pt` editor-tools glass group retains five `31pt` tracks; each track is a native `.toolbar` button with `showsBorderOnlyWhileMouseInside` instead of a custom drawn highlight.
- Expanded Add Folder and Sidebar Toggle use the same hover-only toolbar button behavior. Static visual geometry remains on the compact baseline, and real-pointer captures verify hover rendering.
- Full tests, installed-app library smoke, packaging, and strict signature validation pass for this implementation.

## Latest iteration (200)

- New Note now occupies a `44pt` toolbar layout slot with its native `30pt` glass button trailing-aligned, matching Apple Notes' divider-to-button offset without moving the search field or pane dividers.
- Compact New Note and collapsed Sidebar Toggle symbols use a dedicated `12pt` SF Symbol configuration with `.scaleNone`; this produces approximately reference-sized `15–17pt` image canvases inside the small native glass bezels.
- Keep expanded toolbar symbols on the existing `19pt` configuration and proportional scaling. The compact correction is intentionally isolated to `.glass` controls.
- Final expanded and collapsed visual evidence lives under `/tmp/mudsnote-visual-qa-200-final-expanded` and `/tmp/mudsnote-visual-qa-200-final-collapsed`.

## Latest iteration (201)

- The editor-tools item now uses a transparent `162pt` layout slot with the unchanged `155x32pt` `NSGlassEffectView` trailing-aligned, moving the visible capsule right by `7pt` without moving Search or changing hit targets.
- Grouped checklist/table/link/attachment icons use an editor-only `14pt` SF Symbol configuration; expanded source controls retain their existing `19pt` symbols.
- Grouped `Aa` is a native `13pt` regular text button instead of a custom bitmap image.
- `NSToolbarItem.isBordered` is explicitly false for the group, preventing a second shifted outline around the glass capsule.
- Final packaged visual evidence is `/tmp/mudsnote-visual-qa-201-editor-tools-final/apple-notes-vs-mudsnote.png`.

## Latest iteration (202)

- Post-save `sourceCountSnapshot` maintenance no longer re-sorts up to `10,000` notes on the main actor.
- `LibraryNoteListProjection.upsertByModifiedDate` removes old/new paths, binary-searches the descending modified-date insertion point, inserts once, and enforces the existing limit.
- The save boundary supplies both raw and standardized paths; the hot removal loop compares `.path` directly and does not normalize every snapshot URL.
- Regression coverage includes rename replacement, duplicate prevention, ordering, capacity, and a debug-build `10,000`-entry update budget below `50ms`.
- Collapsed visual regression evidence is `/tmp/mudsnote-visual-qa-202-collapsed/apple-notes-vs-mudsnote.png`.

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

The iPhone goal is now the same core Apple Notes product model, with Mudsnote's
capture flow replacing conventional New Note and Quick Note entry. Use
`docs/ios-apple-notes-parity-roadmap.md` for the iOS scope, exclusions, architecture,
and verification contract. iPhone work is no longer capture-only.

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
4. Run `./scripts/library_smoke.sh` when the change touches the three-pane library's create/edit/save/search path

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

# Mudsnote Refactor Log — Iteration 30 (2026-04-18)

This document records every file-level change made during the structural refactor (iteration 30), and the reason for each decision.

## Guiding constraints

1. No behavior change — all 21 tests must stay green.
2. No public API change — `@testable import MudsnoteCore` and `@testable import Mudsnote` symbol surfaces preserved.
3. No UX regression — quick-capture title/body separation, bottom shelf, borderless panel chrome, and native feel must be intact.
4. Every god-object becomes focused files, not a rewrite.

---

## MudsnoteCore — split from 1 file to 6 files

**Why:** `MudsnoteCore.swift` (841 lines) mixed value-type models, settings persistence, legacy migration, draft I/O, note I/O, and search scoring in a single file. Finding the search scoring function required scrolling past 600 lines of unrelated code.

| New file | What it contains | Reason for this boundary |
|---|---|---|
| `Models.swift` | `NoteFile`, `NoteSearchResult`, `DraftSnapshot`, `StoredWindowOrigin`, `StoredWindowFrame`, `MarkdownEditorDocument` | All value types. No behavior, no side effects. Easiest to read in isolation. |
| `NoteStore.swift` | Class declaration, stored properties, init, `defaultNotesDirectory`, `defaultAppSupportDirectory`, `deduplicatedDirectories` | Everything needed to instantiate the store. Acts as the entry point when reading the class. |
| `NoteStore+Settings.swift` | `NoteStoreDefaultsKey` enum, all `UserDefaults`-backed properties, frame read/write helpers | One cohesive topic: what the user has configured and where it is stored. |
| `NoteStore+Migration.swift` | `LegacyDefaultsKey`, `MigrationKey`, `migrateLegacyDefaultsIfNeeded` and private helpers | Migration logic touches legacy keys nowhere else in the codebase. Isolating it makes it safe to read, audit, or eventually delete without touching any other slice. |
| `NoteStore+Drafts.swift` | `saveDraft`, `loadDraft`, `deleteDraft`, `draftsDirectory`, `draftFileURL` | Draft persistence is a standalone JSON I/O concern. |
| `NoteStore+Notes.swift` | `listRecentFiles`, `loadNote`, `saveNewNote`, `updateNote`, `markdownFiles`, `parseStoredDocument`, `writeNote`, filename/slug helpers, formatters | All on-disk note read/write logic. Touches the `.md` format and YAML front-matter. |
| `NoteStore+Search.swift` | `knownSearchRoots`, `knownTags`, `searchNotes`, `scoredMatch`, `snippet`, `firstMeaningfulLine` | All search scoring and ranking. The most algorithmically interesting part — now easy to find. |

**Visibility change:** `DefaultsKey` was a `private` nested enum. Since extensions in other files cannot access `private` members, it was extracted to a module-internal `NoteStoreDefaultsKey` enum. Still not part of the `public` API.

---

## AppUI — split from 1 file to 8 files under `Sources/Mudsnote/Chrome/`

**Why:** `AppUI.swift` (981 lines) was a dumping ground — `sha256Hex`, opacity math, color palette, a full custom NSPanel, drag-host views, scrollbars, and button types all in one file with no organizing principle.

| New file | What it contains | Reason for this boundary |
|---|---|---|
| `Chrome/Helpers.swift` | `displayPath`, `sha256Hex`, `chooseDirectory`, `pin`, `insetted`, `positionPanelNearTopCenter` | Pure utility functions with no visual dependencies. |
| `Chrome/Palette.swift` | `panelAccentColor`, `panelPrimaryTextColor`, etc. | All semantic color tokens in one place. Easy to update the whole palette without touching layout code. |
| `Chrome/OpacityMath.swift` | `clampedPanelOpacity`, `normalizedPanelOpacity`, `accentSurfaceAlpha`, `primarySurfaceAlpha`, `secondarySurfaceAlpha`, `windowAlphaValue`, `WindowOpacityAdjusting` | All opacity math derived from `NoteStore` bounds. One file for the whole opacity system. |
| `Chrome/Surfaces.swift` | `makeModernSurface`, `GradientBackdropView` | The two surface/backdrop types that use `macOS 26` glass or `NSVisualEffectView` — both relate to the window background surface. |
| `Chrome/Buttons.swift` | `styleAccentButton`, `styleSecondaryButton`, `styleToolbarButton`, `HoverToolbarButton`, `FocusAwareAccentButton`, `FocusAwareSecondaryButton` | Every button type and its styling. |
| `Chrome/Scrolling.swift` | `SlimScroller`, `ScrollIndicatorOverlay` | The two custom scroll components. |
| `Chrome/Panels.swift` | `QuickEntryPanel` + `HitCatchingView` | Co-located because `HitCatchingView` uses `QuickEntryPanel.installCursorRects` which is `fileprivate` — keeping them in the same file preserves that access contract. |
| `Chrome/DragHosts.swift` | `WindowMoveBackgroundView`, `SubviewPassthroughView`, `FocusProxyContainerView`, `FocusableTextField`, `DragHandleView`, `PassthroughOverlayView` | All views that customize hit-testing or drag behaviour for the borderless panel. |

**No behavior changes.** `WindowMoveBackgroundView` and `SubviewPassthroughView` symbols referenced by `@testable import Mudsnote` tests are unchanged.

---

## EditorWindowController — split from 1 file to 8 files (1 core + 7 extensions)

**Why:** `EditorWindowController.swift` (2106 lines) handled quick-capture UI building, full-editor UI building, Markdown formatting commands, tag suggestion, slash command completion, draft autosave, save/cancel/search flows, reveal animation, and window focus appearance — all in one class. Every PR that touched formatting also touched draft logic, and vice versa.

**Approach:** Swift extensions across files. Same class identity — no extraction into sub-controllers. This is zero-risk: same class, same symbol, same behavior, just in separate files. The only mechanical change is removing `private` from members that need cross-file visibility; since `Mudsnote` is an executable target, `internal` (the default) does not expose anything externally.

| New file | What it contains |
|---|---|
| `EditorWindowController.swift` | Class declaration, nested enums (`SlashCommand`, `InlineSuggestionContext`, `ToolbarAction`, `QuickCaptureAction`), all stored properties, `init`, public interface (`showWindowAndFocus`, `hideWindowForToggle`, etc.), window delegate methods, `MarkdownTextViewCommands` protocol stubs, `NSTextFieldDelegate` stubs |
| `EditorWindowController+UI.swift` | `buildUI`, `buildStandardEditorUI`, `buildQuickCaptureUI`, all button/view factories, `configureSuggestionPopover`, `configureObservers`, `loadInitialContent`, `applyInitialContent`, `applyBodyMarkdown`, `refreshChrome`, `refreshQuickCaptureChrome`, `updateWindowFocusAppearance` |
| `EditorWindowController+TextHelpers.swift` | `userDidEdit`, `interpretTypedMarkdownIfNeeded`, `updateTypingAttributesFromInsertionPoint`, `visibleLineRangeForSelection`, `selectedLineRanges`, `replaceText`, `insertTextAtSelection`, `scrollSelectionToVisible`, `handleShortcutEvent`, `performStandardEditCommand` |
| `EditorWindowController+Draft.swift` | `markDocumentDirty`, `persistDraft`, `currentDocument`, `currentQuickCaptureTitleValue`, `serializedBodyMarkdown` |
| `EditorWindowController+Formatting.swift` | `handleStructuredNewline`, `toggleParagraphKind`, `convertCurrentLineToParagraph`, `insertStructuredLine`, `toggleChecklistIfNeeded`, `toggleInlineFontTrait`, `applyStrikethrough`, `applyUnderline`, `updateToolbarSelectionState`, `setToolbarActionState`, `handleEditorShortcut`, `toolbarButtonPressed`, `quickCaptureActionPressed` |
| `EditorWindowController+TagsAndSuggestions.swift` | `refreshTrackedTags`, `mergedDocumentTags`, `currentTagToken`, `rankedMatchingTags`, `updateInlineSuggestions`, `currentInlineSuggestionContext`, `acceptInlineSuggestion`, `dismissInlineSuggestions`, `positionSuggestionView`, `applyTag`, `applySlashCommand`, `commitPendingTagIfNeeded`, `neutralTypingAttributesForCurrentLine`, tag menu and string algorithm helpers |
| `EditorWindowController+Save.swift` | `savePressed`, `cancelPressed`, `searchPressed`, `quickCaptureDirectoryPressed`, `presentErrorAlert` |
| `EditorWindowController+Appearance.swift` | `prepareRevealAnimation`, `performRevealAnimation` |

---

## Verification

- `swift test` — 21/21 tests pass (unchanged from before refactor)
- `./scripts/package_app.sh` — clean release build, installs to `/Applications/Mudsnote.app`
- Quick-capture smoke: launched `--quick-capture`, typed title + Tab + body, triggered save with `Cmd+Return`, verified `.md` file written to `~/Documents/Mudsnote/` with correct `# Title\n\nBody` content
- Preferences smoke: launched `--preferences`, verified popup/slider/hotkey-field/save elements present

---

## What was deliberately not changed

- No behavior changes anywhere
- No UserDefaults key renames (would break existing user data)
- No public API changes (would break tests)
- No quick-capture UX changes (title/body separation, bottom shelf, native feel — all preserved)
- Legacy migration code untouched
- Test files untouched

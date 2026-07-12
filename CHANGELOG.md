# Mudsnote Changelog

This file tracks user-visible iterations for the current prototype.
For each iteration, keep three parts:

- Problem
- Fix
- Lesson

Known open issue:

- Window live-resize still shows a dark trailing shadow/transition on some systems even after switching away from the default window shadow path. This is likely tied to macOS compositing for transparent borderless resizable panels and may require a more drastic rendering fallback during resize.

## Iteration Count

As of 2026-03-23, this prototype has gone through 26 implementation iterations in this chat, including the initial MVP.

## Iterations

### 144. Safe-area editor rhythm
- Problem: After enabling full-size content for the native sidebar, the editor date row entered the titlebar and the 30pt title remained visibly larger than Apple Notes.
- Fix: Anchored the editor stack to the window safe area, reduced the title to 24pt, and reset date-to-title spacing to 8pt while preserving the 15pt body.
- Lesson: Full-height sidebars require each neighboring pane to define its own titlebar-safe content boundary; compensating with oversized spacing is fragile.

### 01. Initial MVP
- Problem: No working app yet.
- Fix: Built a menu bar Markdown capture app with global hotkey, recent notes, settings, and app packaging.
- Lesson: Start with a real `.app` target early so menu bar, focus, and hotkey behavior are tested in the correct runtime shape.

### 02. Modernized visual shell
- Problem: First UI pass was too plain and lacked per-note save path selection.
- Fix: Added glass-style shell, updated settings UI, and per-note folder selection.
- Lesson: Keep file persistence simple first, but expose storage choice early because it affects real adoption.

### 03. Things-style quick entry
- Problem: Capture window felt oversized and low-utility.
- Fix: Reworked the capture UI toward a compact quick-entry layout and added search, autosave drafts, and borderless behavior.
- Lesson: Fast-capture tools live or die on window size, focus behavior, and default actions more than on feature count.

### 04. Rounded translucent visual pass
- Problem: The capture bar and glass treatment still felt heavy.
- Fix: Rounded the main input shell and increased overall translucency.
- Lesson: In floating tools, fewer surfaces and lighter contrast usually outperform dramatic panel stacking.

### 05. Compact shell tuning
- Problem: Outer frame, title area, and body were still too large and opaque.
- Fix: Tightened the card, reduced corner emphasis, and added better transparency balance.
- Lesson: Size and spacing problems are often more important than decorative styling.

### 06. Golden-ratio resize pass
- Problem: Window proportions still looked stretched.
- Fix: Resized the panel closer to a 1.62:1 ratio.
- Lesson: Quick-entry windows benefit from card-like proportions instead of long horizontal slabs.

### 07. Further size reduction
- Problem: Capture still felt too large for “flash note” use.
- Fix: Reduced overall size again and tightened content spacing.
- Lesson: For capture tools, bias toward smaller defaults and expand only when content proves the need.

### 08. Bottom bar compression
- Problem: Bottom controls consumed too much visual weight.
- Fix: Reduced bottom area height and compressed controls.
- Lesson: Bottom bars should support the editor, not compete with it.

### 09. System-radius refinement
- Problem: Corner radii and folder interaction still felt off-pattern.
- Fix: Reduced corner radius to feel more native and moved folder choice toward inline interaction.
- Lesson: Matching macOS window geometry matters more than strong custom styling.

### 10. Settings-driven directories
- Problem: Directory management was incomplete and visually fragmented.
- Fix: Added managed directories in settings and simplified the bottom structure.
- Lesson: Configuration should be centralized; don’t force operational UI to carry setup responsibilities.

### 11. Live opacity control
- Problem: Transparency was static and hard to tune.
- Fix: Added opacity control in settings and propagated it to active windows.
- Lesson: Visual tuning options need live preview or users will keep guessing and reopening.

### 12. Real-time opacity application
- Problem: Opacity only affected part of the surface and button position changes looked ineffective.
- Fix: Applied opacity to the whole shell and corrected layout assumptions.
- Lesson: If a spacing change “does nothing,” the issue is usually the parent constraint model, not the spacing constant itself.

### 13. Blur + stronger opacity floor
- Problem: Low-opacity settings still felt too transparent.
- Fix: Raised the opacity floor and added stronger blur treatment.
- Lesson: Transparent windows need blur and darkness together; transparency alone just looks washed out.

### 14. Unified single editor surface
- Problem: Separate title and body regions broke visual unity.
- Fix: Merged title/body into one Markdown editor surface and replaced the old footer arrangement.
- Lesson: A single editing surface reduces cognitive overhead and makes toolbar behavior easier to reason about.

### 15. WYSIWYG rich text round-trip
- Problem: Raw Markdown markers in the editor hurt usability.
- Fix: Added rich rendering for headings, lists, checkboxes, emphasis, and Markdown round-trip serialization.
- Lesson: Once rich rendering exists, every edit path must preserve round-trip safety.

### 16. Shortcut routing cleanup
- Problem: Editor shortcuts were unreliable and some toolbar options were visually noisy.
- Fix: Simplified the toolbar and moved formatting shortcut handling higher in the event chain.
- Lesson: Borderless floating editors often need explicit shortcut routing instead of relying on default responder behavior.

### 17. Focus-state and hover cleanup
- Problem: Focus visuals and toolbar state were inconsistent.
- Fix: Normalized focus/hover styling and removed special-case save emphasis.
- Lesson: In compact toolbars, consistency beats “primary action” coloring almost every time.

### 18. Standard edit commands + active format state
- Problem: Copy/paste and selection-based toolbar state were incomplete.
- Fix: Forwarded standard edit commands explicitly and lit toolbar buttons based on cursor/selection state.
- Lesson: Standard editing commands should be treated separately from app-specific formatting commands.

### 19. Font, paste, scrollbar, and save polish
- Problem: Pasted content brought in foreign fonts and the shell controls still felt rough.
- Fix: Normalized pasted text, unified font sizing, tightened the scrollbar, and refined save button spacing.
- Lesson: Paste normalization is mandatory in rich editors, not a polish task.

### 20. Inline tags and slash commands
- Problem: Path selection consumed space and tagging/commands were missing.
- Fix: Removed file-path UI from the capture bar, added inline tags, YAML tag persistence, and initial slash commands.
- Lesson: Secondary metadata entry should happen inline whenever possible.

### 21. Smaller list glyphs and better tag flow
- Problem: Bullet/checklist visuals were clumsy and tag creation interrupted typing.
- Fix: Refined list glyphs, enabled checklist toggling, and stopped showing tag popovers when no match existed.
- Lesson: Suggestion UI should never block free typing when there is no useful suggestion.

### 22. Bracket shortcuts and immediate list rendering
- Problem: Checklist shortcuts and empty list lines did not render immediately.
- Fix: Added `[]`/`【】` checklist shortcuts and immediate visual rendering for empty bullet/ordered lines.
- Lesson: Structural shortcuts must provide instant visible feedback or users think they failed.

### 23. Resizable panel and inline tag rendering
- Problem: Window size was fixed and tags still depended on footer UI.
- Fix: Enabled panel resizing, removed bottom tag chips, and rendered tags inline in blue at their original positions.
- Lesson: If metadata already exists in document content, don’t mirror it in a second control surface unless needed.

### 24. Drag bar and tag submission fixes
- Problem: Resizing artifacts persisted and tag submission was inconsistent on Enter/Space.
- Fix: Added a top drag bar, disabled some live-resize effects, and made Enter/Space commit tags with neutral post-tag typing attributes.
- Lesson: Temporary formatting state after structured insertion is a common source of “why is my next text blue/bold” bugs.

### 25. Lightweight inline suggestion surface
- Problem: Tag suggestions were too heavy and backspace could still feel stuck.
- Fix: Replaced popover-style suggestions with an in-window floating list and preserved cursor offsets during line re-render.
- Lesson: Re-rendering a rich text line must preserve selection offsets, or backspace/editing will feel broken immediately.

### 26. Right-aligned save, resize-path switch, and scroll visibility
- Problem: Footer alignment, live-resize artifacts, and list newline scrolling still needed work.
- Fix: Switched to content-layer shadow rendering with explicit `shadowPath`, restored toolbar-left/save-right footer layout, and forced selection scroll-on-insert.
- Lesson: Transparent borderless resizable windows are sensitive to how shadows are rendered; when artifacts remain, document the limitation and separate it from ordinary layout issues.

### 27. Quick-capture toggle + window position memory
- Problem: Pressing the capture hotkey always tried to show or recreate the quick-capture panel, so an in-progress draft could not be toggled hidden/visible and the panel forgot its previous position.
- Fix: Retained hidden quick-capture controllers when they still had meaningful draft content, toggled them with the hotkey instead of recreating them, and persisted the panel origin for future new quick-capture windows.
- Lesson: For floating capture tools, visibility state and content state are separate concerns; cleanup logic must not treat a hidden draft window like a closed disposable window.

### 28. Quick-capture frame memory + unconditional toggle reuse
- Problem: The first toggle implementation still depended too much on content-state checks, which made show/hide unreliable in practice, and only the origin was remembered instead of the full window shape.
- Fix: Reused the same quick-capture controller until the window is actually closed, toggled visibility directly on that controller, and persisted the full frame (`x/y/width/height`) so both position and size come back.
- Lesson: Floating capture windows are easier to reason about when their lifecycle is tied to "closed vs not closed" instead of "currently visible and non-empty".

### 29. Configurable save shortcut + floating note mode
- Problem: Quick capture only had one global shortcut and one save affordance, so there was no way to add a second always-on-top note surface or trigger save from a configurable `Command+Return`-style shortcut.
- Fix: Split settings into quick-capture hotkey, floating-note hotkey, and save shortcut; added a second floating-note controller with its own draft/frame memory and reused the existing editor layout without the save button.
- Lesson: As soon as one compact tool gains multiple entry points, treat global shortcuts, in-editor shortcuts, and window modes as separate configuration layers instead of overloading a single hotkey field.

### 30. Structural refactor — god objects split into focused files

- Problem: Three source files had grown into large god objects that were hard to navigate and modify safely: `MudsnoteCore.swift` (841 lines, all persistence mixed together), `AppUI.swift` (981 lines, unrelated chrome helpers sharing a file), and `EditorWindowController.swift` (2106 lines, every editor concern in one class). Making a targeted change in any one required reading hundreds of lines of unrelated code.
- Fix: Split each god object into focused files without changing any behavior or public API. `MudsnoteCore.swift` became six files (`Models`, `NoteStore`, `NoteStore+Settings`, `NoteStore+Migration`, `NoteStore+Drafts`, `NoteStore+Notes`, `NoteStore+Search`). `AppUI.swift` became eight files under `Chrome/` (`Helpers`, `Palette`, `OpacityMath`, `Surfaces`, `Buttons`, `Scrolling`, `Panels`, `DragHosts`). `EditorWindowController.swift` became seven files via Swift extensions (`+UI`, `+TextHelpers`, `+Draft`, `+Formatting`, `+TagsAndSuggestions`, `+Save`, `+Appearance`). All 21 tests pass and the packaged app quick-capture/save flow was confirmed.
- Lesson: Splitting a large Swift class into per-responsibility extension files (one extension per file) is a zero-risk refactor if you change `private` to `internal` on cross-file members — the module boundary still prevents external access, and the tests verify nothing changed.

### 31. List prefix deletion resets paragraph state

- Problem: Deleting the visible checkbox/list marker could leave the line internally marked as checklist/list, so toolbar state and Markdown serialization still treated it as a task item.
- Fix: Validate that list prefixes are still visibly intact before trusting stored paragraph attributes, and normalize a damaged list-prefix line back to a plain paragraph during editing.
- Lesson: Rich-text structural state must be invalidated when the visible structural marker is deleted; otherwise display, toolbar state, and saved Markdown drift apart.

### 32. Standard Settings and behavior preferences

- Problem: Settings still used an older tab chrome with a placeholder planning section, and review found behavior bugs around repeated Settings opens, opacity preview affecting Settings, and ambiguous duplicate shortcuts.
- Fix: Moved Settings to a macOS preference-toolbar layout, added real controls for Finder reveal after save, floating-note window level, and editor spell checking, reused an already-open Settings window, kept Settings fully opaque during opacity preview, and rejected duplicate shortcut assignments before saving.
- Lesson: A Settings page should only expose controls backed by real behavior; window-level preferences also need immediate propagation to already-open panels.

### 33. Shortcut recording and Chinese UI

- Problem: Shortcut settings still required typing strings like `option+r`, which is fragile and unlike macOS shortcut preferences; the visible app UI also still mixed English labels with Chinese usage.
- Fix: Added recorder-style shortcut controls that capture real key events and display macOS shortcut symbols, normalized captured shortcuts back into the existing persisted format, and switched the main menu, Settings, search, editor chrome, slash commands, alerts, and status labels to Chinese.
- Lesson: Shortcut configuration should capture keyboard events before window key equivalents can consume them; UI language should be changed across the user-visible flow in one pass instead of per-panel.

### 34. Local AI command layer

- Problem: The project needed AI capability without turning a fast Markdown capture app into a bulky chat workspace.
- Fix: Added an opt-in local Ollama AI provider, Settings controls, editor context-menu actions, and `/summarize`, `/fix`, `/todos` slash commands with preview-before-apply behavior.
- Lesson: AI fits Mudsnote best as explicit, small-scope Markdown transformations with visible privacy boundaries and no background note indexing.

### 35. Lightweight Notes-style library window

- Problem: Mudsnote could capture and search notes, but it did not yet have a lightweight desktop surface for browsing and continuing existing Markdown notes in one place.
- Fix: Added a `笔记库` menu item and `--library` launch mode that open a standard split-view notes window with a source-list sidebar, search, title field, rich Markdown editor, save action, and separate-window handoff. Added a `NoteStore.listNotes` API for all known Markdown files without changing the existing recent-first search behavior.
- Lesson: The Notes-like desktop path should stay separate from quick capture; the main window handles review and continuation while quick capture remains the fastest entry point.

### 36. Continuous iOS quick capture

- Problem: The iOS quick-capture sheet saved a memo and immediately dismissed, which made repeated mobile capture slower than the target workflow.
- Fix: Changed iOS draft sending to keep the capture sheet open by default, clear the saved draft, preserve the selected target, reset the route to text, and disable duplicate sends while a write is in flight. Reworked the target menu into a compact visible target pill so the current destination is visible without opening the menu.
- Lesson: The mobile app should optimize for consecutive capture bursts; target choice should be visible and persistent, while editing depth stays on the desktop side.

### 37. Modern icon and three-column library

- Problem: The iOS companion still used an older icon style, and the macOS library window needed another step toward the familiar Notes source list + note list + editor workflow.
- Fix: Added a reproducible modern iOS icon generator and regenerated the companion icon set. Reworked the macOS library into a three-column split view with library scopes, recent notes, Inbox, tag filters, search, note list, and the existing Markdown editor. Hardened the real-device smoke script to preflight Developer Disk Image availability and give a clear unlock prompt.
- Lesson: Keep the phone surface optimized for capture and make desktop browsing richer through lightweight structure first: source filters, stable panes, and direct editing before heavier indexing.

### 38. Default launch opens the library

- Problem: Double-clicking Mudsnote could leave the user in the menu bar or floating-note path instead of opening the new Notes-like main interface.
- Fix: Changed ordinary no-argument launches and app reopen events to show the `笔记库` window by default, while preserving explicit `--quick-capture`, `--floating-note`, `--search`, `--preferences`, and `--library` launch modes.
- Lesson: Once a desktop app gains a real main workspace, direct launch should reveal that workspace; quick capture remains an explicit fast entry point, not the default app identity.

### 39. Apple Notes-style date grouping

- Problem: The desktop library had three panes, but the middle note list was still a flat table and did not read like Apple Notes' time-sectioned note list.
- Fix: Added non-selectable date group rows for today, yesterday, previous 7 days, previous 30 days, and older years. Left-aligned the note cards and replaced the default selected row with a Notes-like golden highlight. The first real note still auto-selects, tag/search filtering still works, and group rows are skipped by selection.
- Lesson: Faithful Notes parity is mostly information architecture before decoration; sectioning the note list by recency makes the library feel immediately more native.

### 40. Notes-like source counts

- Problem: The left source list still lacked Apple Notes' quick count cues, so folders and tags did not communicate scope size at a glance.
- Fix: Added right-aligned counts to the main library scopes and tag rows while preserving the existing button-based filtering behavior. The source rows keep their click targets, selected tint, and tag filtering test coverage.
- Lesson: Sidebar parity should improve scan density without changing the storage model; count overlays are a lightweight step before deeper folder hierarchy work.

### 41. Native Notes-like library toolbar

- Problem: The main library still carried search, new-note, open, and save controls inside content panes, which made the shell feel like a custom browser rather than Apple Notes.
- Fix: Added a native `NSToolbar` with icon-first actions for adding a folder, toggling the source list, creating a note, opening a note separately, saving, and searching. Moved search into the right side of the toolbar, added real folder rows to the source list, and centered the editor status/date row above the note title. Changed the launch list to use recent-backed metadata first so the direct-open library appears before any full directory indexing work.
- Lesson: P0 Notes parity should move global actions into native window chrome before deeper feature work; shell structure changes make the app feel closer to Notes only if the app still opens immediately.

### 42. Launch-safe recent metadata

- Problem: The packaged app could start a process without showing a window because the status menu and library source list synchronously read recent file attributes and scanned tags before the main library appeared.
- Fix: Made recent-file listing IO-light by deriving display titles and stable dates from stored paths, save-time metadata, and filename prefixes; avoided synchronous tag scans in the library launch path; and added a regression test for stale recent paths. The library now opens directly from `/Applications/Mudsnote.app` even when deeper indexing may need to be deferred.
- Lesson: The Notes-like main window is the app identity now; expensive indexing, tag discovery, unavailable path handling, and full metadata hydration must happen after the shell is visible or in an asynchronous index layer.

### 43. Recently Deleted lifecycle

- Problem: The Notes-like library could browse and edit notes, but it still lacked the Apple Notes lifecycle path for deleting, restoring, and permanently deleting notes.
- Fix: Added a local Markdown Trash under app support with original-path metadata, a `最近删除` source-list scope, toolbar delete/restore actions, read-only deleted notes, and regression tests for delete-to-trash, restore, and permanent delete from both core storage and the library window.
- Lesson: Notes parity is not only a three-column shell; daily replacement requires reversible note lifecycle operations that keep plain Markdown files recoverable and outside a database.

### 44. Clear iOS unavailable-device diagnosis

- Problem: The iOS device smoke script reported an unavailable paired phone as a generic missing or locked device, which obscured Xcode/CoreDevice compatibility issues.
- Fix: Updated `scripts/device_smoke.sh` to detect paired-but-unavailable iPhones, print the CoreDevice list, Xcode version, and iPhoneOS SDK version, and point the user toward matching DeviceSupport/DDI before retrying.
- Lesson: Real-device verification should distinguish connection, trust, lock, and SDK/DDI compatibility failures; otherwise the next action is unclear.

### 45. Folder management and note moves

- Problem: The Notes-like library could show folder rows, but daily Apple Notes workflows still required Finder for creating folders, moving notes, renaming folders, and deleting folders.
- Fix: Added local folder creation, folder rename, note move, and folder delete-to-Trash APIs; wired the library window so new notes save into the selected folder, notes can move between folders, and folder rows expose rename/delete actions. Added core and app regression tests for the full folder lifecycle.
- Lesson: A Notes replacement needs in-app information architecture controls; showing filesystem directories is only useful once the app can manage them without leaving the three-pane workflow.

### 46. Library editor tools toolbar

- Problem: The macOS library window visually approached Apple Notes, but the main editor toolbar still lacked the everyday editing tools for formatting, checklists, tables, links, and attachments.
- Fix: Added Notes-style editor toolbar items for formatting, checklist, table, link, and attachment actions. The library editor now shares the rich Markdown command path for inline formatting and checklists, inserts readable Markdown tables and links, copies attachments into a local `Attachments/yyyy/mm/` folder, and saves standard relative Markdown links. Added app regression coverage for the toolbar items and saved Markdown output.
- Lesson: Toolbar parity should stay functional and local-first; a lightweight Notes clone can add table and attachment workflows through portable Markdown before investing in heavier rich rendering.

### 47. Notes-style more actions

- Problem: The library toolbar had gained functional editing controls, but file/lifecycle actions still crowded the top bar and made it less like Apple Notes.
- Fix: Moved open, move, save, delete, restore, reveal, and copy-path workflows into a single Notes-style more-actions menu. Added reveal-in-Finder and copy-Markdown-path actions for the selected note, kept context-menu access, and updated regression coverage for the default toolbar shape and file menu workflows.
- Lesson: Apple Notes parity is partly action hierarchy; common editing tools belong on the toolbar, while less frequent file operations should live behind a compact menu without losing functionality.

### 48. Search scope and match highlighting

- Problem: The toolbar search field could filter the note list, but it still felt unlike Apple Notes because it lacked an explicit current/all scope and did not show where the match occurred.
- Fix: Added a compact `当前 / 所有` search scope control in the note list header, switched active searches to `NoteStore.searchNotes` so results include body snippets, and highlighted matching title/snippet text in note rows. Added app regression coverage for current-folder search, all-notes search, snippets, and highlight attributes.
- Lesson: Search parity should improve retrieval feedback before adding a heavier index; scoped search and visible matches give a Notes-like result loop while keeping the storage model simple.

### 49. Notes-like shell header density

- Problem: The library still had a visible app title, a large custom source-list heading, and a generic middle-column `笔记` label, so the first screen did not match Apple Notes' quiet titlebar and scope-aware note list header.
- Fix: Hid the window title in the titlebar while preserving the system window title, tightened the note-list column width, changed the source list to compact Notes-style group labels, added a selected-scope title plus result/count line to the note-list header, and reduced the selected note card radius. Added app regression coverage for the hidden titlebar, source group label, and list title/count states.
- Lesson: Notes parity needs density contracts as much as features; the shell should communicate current scope and count without adding heavier controls or changing the Markdown storage boundary.

### 50. Note-list preview snippets

- Problem: Normal library rows showed title and metadata but no body preview, so the middle column still lacked the Apple Notes scanning loop outside active search.
- Fix: Added bounded preview hydration for the first recent-backed rows so the list shows each note's first meaningful body line while count refreshes still use the lightweight metadata path. Locked row labels to single-line truncation to prevent long titles or snippets from overlapping the compact Notes-style row layout.
- Lesson: List parity should improve scanability without turning launch into a full indexing pass; bounded visible-row hydration gives useful previews while preserving the fast shell-first path.

### 51. Darker Notes-style note list

- Problem: The middle note list still rendered as a broad gray table surface, which made the shell feel less like Apple Notes' dark list column and weakened the selected note card.
- Fix: Switched the note table to a plain transparent style, gave the list column a darker background, and kept the custom golden selection drawing. The scroll view clip now stays transparent so the list column reads as one dark pane.
- Lesson: Visual parity often depends on removing default AppKit table styling; keep native behavior, but own the background and selection surfaces where Apple Notes has a strong visual signature.

### 52. Nested folder source rows

- Problem: The source list showed only flat preferred folders, so local subfolders could not be browsed from the Notes-like sidebar even though Apple Notes relies on visible folder hierarchy.
- Fix: Added a lightweight folder-row model that expands preferred roots into indented local subfolders, reuses the existing folder scope for selection/search/new notes, updates folder counts to include descendant notes, and includes nested folders in the move-note menu. Added app regression coverage for selecting a nested folder and moving to it.
- Lesson: Folder hierarchy can be represented directly from the filesystem before adding heavier disclosure-state or metadata layers; keep the first pass local-first and bounded.

### 53. Collapsible folder disclosures

- Problem: Nested folder rows made the source list more complete, but without disclosure controls, larger local folder trees would become too long and unlike Apple Notes.
- Fix: Added chevron disclosure buttons for folders with children, default-expanded local folder trees, in-memory collapse state, and selection fallback to the parent folder when collapsing the currently selected child. Expanded the nested-folder regression test to cover collapse and re-expand behavior.
- Lesson: Folder disclosure state can stay lightweight and session-local first; the key parity behavior is visible hierarchy control without changing Markdown storage.

### 54. Deferred source folders and tags

- Problem: The active goal no longer includes iOS real-device validation, and the macOS Notes-like window still had two launch-path risks: tag rows were intentionally absent from the first sidebar shell, while real preferred folders could block direct launch during synchronous directory scans.
- Fix: Kept the first library shell lightweight by rendering root folders immediately, loading the full folder tree off the main launch path, and loading tag source rows after the window is visible. Folder disclosure and folder-management actions still refresh the current tree synchronously when the user asks for that structure. Tag rows now display as a single `#` symbol plus the bare tag name in the sidebar while preserving `#tag` in list titles and metadata. Added regression tests for deferred tags, explicit folder-tree loading, search scopes, and nested disclosure behavior.
- Lesson: Apple Notes parity should be shell-first: the three-pane window must appear on direct open before optional indexing, tag discovery, or deeper filesystem traversal can run.

### 55. Centered editor date line

- Problem: The right editor header still displayed `date · folder`, and the label could sit visually off-center, making the editor pane less like Apple Notes' centered date line.
- Fix: Changed the library editor status line to show only the formatted note date for loaded notes, moved the label into a dedicated centered date row, and kept dirty/new-note status text for transient editing states. Added regression coverage for the editor status identifier, center alignment, date-only text, and absence of folder separators.
- Lesson: Apple Notes parity depends on small information hierarchy decisions: folder context belongs in the note list/source list, while the editor header should stay focused on the note timestamp.

### 56. Note-list attachment indicator

- Problem: Library notes could insert and save Markdown attachment links, but the Notes-like middle list had no compact signal that a note contained an attachment.
- Fix: Added a lightweight `hasAttachments` flag to `NoteSearchResult`, populated it from already loaded Markdown bodies in list/search/trash/recent paths, and rendered a small SF Symbol paperclip beside the note-list metadata. The empty-search path now loads each recent note once instead of separately reading body and tags.
- Lesson: Attachment parity should reuse existing bounded hydration and search reads; list affordances should not bring back launch-time full-file scans.

### 57. Note-list keyboard actions

- Problem: The middle note list relied on mouse double-clicks and toolbar/menu actions for opening or deleting selected notes, leaving a gap versus Apple Notes' keyboard-driven list workflow.
- Fix: Added a lightweight `LibraryNoteTableView` that handles unmodified Return/Enter to open the selected note in a separate window and Delete/Forward Delete to delete or permanently delete the selected note, while leaving all other keys to AppKit's table navigation. Added regression coverage for open, delete-to-trash, and permanent-delete keyboard paths.
- Lesson: Keyboard parity should extend the existing lifecycle actions instead of creating parallel behavior; arrow-key selection remains native while high-intent keys map to Notes-like workflows.

### 58. Note-list empty states

- Problem: Empty note-list results still collapsed to a blank middle column, so failed searches and empty trash states lacked the clear edge-state feedback Apple Notes provides.
- Fix: Added a lightweight centered note-list empty label that appears for no search results, empty normal scopes, and an empty Recently Deleted scope. The state is driven by the already loaded `listRows`, so it does not add filesystem scanning or indexing work. Added regression coverage for normal hidden state, no-result search, and empty trash after permanent delete.
- Lesson: Edge-state parity should be explicit but cheap; list feedback can be UI-only when the current row model already knows whether the scope is empty.

### 59. Note-list width fill

- Problem: In the packaged macOS app, the middle note list could render as a narrow table pinned to the right side of its column, leaving large blank space and placing the scrollbar over note text.
- Fix: Added a small `LibraryNoteScrollView` that keeps the table document view left-aligned and width-filled, made the sidebar stack explicitly fill the note-list header and list container, and disabled conflicting automatic table-column resizing. Added regression coverage for the document view origin and single-column width contract.
- Lesson: AppKit scroll/table views need an explicit width contract inside stack views; visual parity depends on verifying the packaged window, not only source-level constraints.

### 60. Notes-like toolbar disabled states

- Problem: The library toolbar and menus still exposed actions in unavailable contexts, especially empty libraries and Recently Deleted, making the shell feel less like Apple Notes' context-aware command surface.
- Fix: Added shared toolbar/menu state helpers for selected-note, editable-document, move, restore, and more-actions availability. Formatting, checklist, table, link, attachment, save, move, open, delete, restore, and more actions now enable only when their current context can actually run. Context menus and action handlers share the same state. Added regression coverage for empty library, new blank note, normal selected note, and trash selection states.
- Lesson: Toolbar parity is not only icon placement; disabled state must follow the same document lifecycle rules as the editor and note list.

### 61. Markdown export action

- Problem: The Notes-like toolbar still lacked a share/export affordance, so portable Markdown actions were hidden behind reveal/copy-path workflows instead of appearing where Apple Notes shows sharing.
- Fix: Added a `square.and.arrow.up` toolbar item and matching menu action for exporting the selected note as Markdown. Export saves pending edits first, then copies the current `.md` file to a user-chosen destination without introducing a new storage format. Added regression coverage for toolbar presence, enabled/disabled export states, and exported Markdown content.
- Lesson: Share parity can stay lightweight by exporting the local source file directly; the UI gains a Notes-like affordance without adding account, sync, or proprietary document behavior.

### 62. Note-list image thumbnails

- Problem: Notes with image attachments still looked like ordinary attachment rows in the middle list, while Apple Notes uses compact thumbnails to make visual notes scannable.
- Fix: Added a lightweight optional thumbnail URL to `NoteSearchResult`, resolved from the first local Markdown image or image attachment reference. The note list now shows a clipped 46px thumbnail for existing local images and falls back to the paperclip for non-image attachments. Added core parsing coverage and app-level row rendering coverage.
- Lesson: Thumbnail parity can reuse already loaded Markdown bodies; do not add a separate media index until the visible list actually needs it.

### 63. Tighter note-list row density

- Problem: The note list was functionally rich but still a little too loose compared with Apple Notes, especially after adding thumbnails. Direct app launch also exposed a startup risk where synchronous preview hydration could hold the window at a zero-size shell.
- Fix: Reduced normal row height, tightened row vertical padding, slightly reduced the note title font, adjusted selected-card inset/radius, and sized image thumbnails to a compact 44px square. The app launch path now uses a regular activation policy, shows the library shell first, then hydrates previews and the selected note after the window is visible. Added regression coverage for the row-height, typography, and thumbnail-size contract.
- Lesson: Notes parity needs explicit density values and shell-first startup; launch should reveal the three-pane library before optional preview work runs.

### 64. In-editor local image previews

- Problem: Image attachments were visible in the note list, but opening the note still showed only Markdown image syntax in the editor.
- Fix: Render local `![alt](path)` references as bounded inline image attachments when the current note path can resolve them, while storing the original Markdown on the attachment so save/serialize remains lossless. Library and standalone editor loads now pass the current file URL as the relative image base.
- Lesson: Attachment preview parity can stay lightweight if the editor only resolves local Markdown references at render time and keeps Markdown as the source of truth.

### 65. Search keyboard result flow

- Problem: Toolbar search showed scoped results, but keyboard flow still required pointer interaction to enter the result list, load the focused result, or clear the query.
- Fix: Added search-field command handling: Down selects the first visible note result and focuses the list, Return loads the focused result into the editor, and Escape clears the query back to the current library scope. Added regression coverage for the keyboard path.
- Lesson: Notes parity depends on fast keyboard transitions between search, list, and editor; small responder-chain commands are enough before adding heavier indexing.

### 66. Search result stepping polish

- Problem: The search keyboard path could enter the first result, but reverse navigation from the search field still fell back to default AppKit behavior instead of selecting the last visible result.
- Fix: Added Up-arrow handling for the toolbar search field so it selects and focuses the last visible note result, while Return preserves the currently selected result instead of forcing the first result. Expanded regression coverage for first/last result selection.
- Lesson: Search parity is a responder-chain detail as much as a search algorithm detail; preserve the user's current result selection before loading it.

### 67. Library editor autosave

- Problem: The Notes-like library editor still behaved like a manual-save editor after typing, leaving a visible dirty state until switching notes or closing the window.
- Fix: Added a lightweight debounced autosave for editable library notes. Edits schedule a short save timer, explicit saves cancel the timer, trash remains read-only, and close still flushes pending edits. Added regression coverage that edits to an existing library note are written back automatically.
- Lesson: Apple Notes parity requires save behavior as much as visual resemblance; debounce autosave keeps Markdown files current without adding a database or background index.

### 68. Subtler autosave status copy

- Problem: After adding library autosave, the editor still used a manual-save style dirty label, which made the centered metadata line feel less like Apple Notes.
- Fix: Replaced the persistent `已修改` dirty label with short autosave-progress copy for existing and new notes, then returned to the normal date line after save. Tightened autosave regression coverage for the status transition.
- Lesson: A Notes-like editor should communicate persistence without making manual save state the main visual focus.

### 69. Editor vertical rhythm

- Problem: The library editor still used uniform vertical spacing between date, title, and body, so the right pane felt less like Apple Notes' centered date plus tight title/body composition.
- Fix: Enlarged the library note title, reduced body text top inset, widened editor side margins, and replaced uniform stack spacing with explicit date-to-title and title-to-body spacing. Added layout contract coverage for these values.
- Lesson: Apple Notes parity depends on asymmetric editor spacing; date/title/body rhythm should be encoded as a contract, not left to default stack spacing.

### 70. Search-field result stepping

- Problem: Search could jump into the note list, but repeated Up/Down commands from the search field could not step through multiple visible results before opening one.
- Fix: Kept search-field focus while Up/Down selects the previous or next visible note result, with no-selection Down starting at the first result and no-selection Up starting at the last. Return preserves and loads the selected result. Expanded regression coverage for continuous stepping.
- Lesson: Search parity is not only retrieval quality; keyboard search should let users scan result candidates before committing to the editor.

### 71. Source-list density polish

- Problem: The Notes-like library shell still had a slightly loose source list: group labels, row height, count text, and selected-row radius did not yet match Apple Notes' compact sidebar feel.
- Fix: Tightened source-list stack spacing, reduced source row height, softened selected-row corner radius, reduced group/count typography, and added layout contract coverage for the source row and count label.
- Lesson: Apple Notes parity needs the left source list to carry hierarchy through density and typography, not only through folders and counts.

### 72. Notes visual QA harness

- Problem: Visual parity was still judged from separate screenshots, and the default direct-open library window could show a focused search field that did not match the static Apple Notes reference state.
- Fix: Added the supplied Apple Notes screenshot as a project reference, added `scripts/visual_notes_qa.sh` to launch the installed app and generate a side-by-side comparison image, and changed default library focus from the search field to the note list. Added regression coverage that default show does not focus search.
- Lesson: A repeatable visual baseline turns vague Notes-like polish into concrete deltas; default focus state is part of the visual contract.

### 73. Wider Notes-like library default

- Problem: The first side-by-side visual QA artifact showed Mudsnote's main library window was narrower than the Apple Notes reference, compressing the editor pane and changing the three-pane balance.
- Fix: Increased the default and direct-open library window width from 1040 to 1160 while preserving the existing height and split-pane widths, giving the editor more room without changing the storage or navigation model.
- Lesson: Window proportion is part of Notes parity; compare captured pixels before tuning individual row and toolbar spacing.

### 74. Autosave debounce stability

- Problem: Full app test runs could starve the library editor's RunLoop-backed autosave timer long enough for the autosave assertion to miss the save, exposing a fragile debounce implementation.
- Fix: Replaced the autosave `Timer` with a cancellable `Task` debounce and changed the autosave regression to wait for the saved state instead of assuming an exact wake-up instant.
- Lesson: Notes-like autosave must be eventual and resilient under UI load; tests should assert the state contract, not a precise timer boundary.

### 75. Lightweight search index

- Problem: Notes-like search, tags, and list metadata still re-read Markdown bodies on repeated queries, which works for small folders but does not match the expected retrieval speed of Apple Notes as libraries grow.
- Fix: Added an in-memory Markdown search index keyed by search roots and file signatures. `knownTags`, `listNotes`, and non-empty `searchNotes` now share parsed entries and rebuild only when path, modification date, or size changes. Added regression coverage that modifying a Markdown file refreshes cached search and tag results.
- Lesson: Local-first Markdown can still feel indexed; cache parsed document metadata while keeping the filesystem as the source of truth.

### 76. Note-list arrow navigation

- Problem: The Notes-like note list handled open/delete keys, but Up/Down navigation still depended on AppKit defaults and could land on recency group rows instead of behaving like a note browser.
- Fix: Added explicit Up/Down handling for the library note list. Keyboard movement now skips group rows, clamps at list boundaries, scrolls the target row into view, saves pending edits, and loads the selected note into the editor. Added regression coverage for group-row skipping and note loading.
- Lesson: Apple Notes parity depends on keyboard browsing details; grouped rows are visual structure, not keyboard destinations.

### 77. Non-image attachment previews

- Problem: The rich editor rendered local image attachments inline, but PDFs and other local files still appeared as plain Markdown links, leaving attachment parity below Apple Notes.
- Fix: Added a local-file attachment chip for existing non-image Markdown links while preserving the original Markdown through serialization. Added regression coverage for file-link rendering and toolbar-inserted attachments.
- Lesson: Attachment parity can stay local-first by turning filesystem-backed links into visible editor affordances without changing Markdown storage.

### 78. Openable attachment chips

- Problem: Non-image attachment chips were visible, but still behaved like static glyphs instead of an Apple Notes-style file affordance.
- Fix: Stored the resolved local file path on rendered attachment chips, switched the editor cursor to a hand over file attachments, and opened the file through the system workspace on double-click in both library and floating editors.
- Lesson: Lightweight attachment parity should make local files directly reachable while keeping the Markdown link as the durable source of truth.

### 79. Attachment context actions

- Problem: Attachment chips could be opened with a double-click, but right-clicking them still showed only the generic editor menu instead of file-specific actions.
- Fix: Added attachment-aware editor context menus for local file chips, with open, reveal in Finder, and copy path actions in both the library and floating editors. Added regression coverage for the library attachment menu contract and hardened visual QA when window-level capture is unavailable.
- Lesson: Desktop Notes parity needs contextual file actions at the point of interaction, not only global note-level actions.

### 80. Attachment metadata and Markdown copy

- Problem: Attachment chips were actionable, but their secondary line did not identify the file type or size, and the context menu could not copy the durable Markdown link.
- Fix: Added deterministic file-type/size metadata to local attachment chips, stored that metadata on the rendered attachment, and added a copy Markdown link menu action alongside open, reveal, and copy path. Expanded attachment regression coverage.
- Lesson: A local-first Notes clone should make attachments useful as visible file objects while keeping the Markdown reference one click away.

### 81. Note-list selected card inset

- Problem: The note-list selected row still read as a nearly full-width table highlight, while Apple Notes uses a more card-like selected note with visible side inset and rounded corners.
- Fix: Increased the custom selected-row inset and radius, and aligned note-row content padding with the selected card. Added a layout contract test for the selected-card geometry.
- Lesson: Notes parity depends on selection geometry as much as color; the note list should feel like scannable cards, not a generic table.

### 82. Search index prewarming

- Problem: The lightweight Markdown index existed, but the first tags/search operation could still pay the indexing cost on the main library path.
- Fix: Added an explicit search-index prewarm API and moved deferred library tag loading onto a utility queue that prewarms the index before publishing tag rows. Added regression coverage that prewarming builds a reusable snapshot without changing search/tag results.
- Lesson: Notes-grade search can stay lightweight if the app warms filesystem metadata off the main thread before the user asks for retrieval.

### 83. Source-list loading states

- Problem: The source list loaded folders and tags asynchronously, but the folder/tag sections could look unfinished while work was pending or when no tags were available.
- Fix: Added lightweight folder and tag status rows for loading and empty states, without changing source-row selection tags or filesystem storage. Added regression coverage for initial loading copy and cleanup after folder/tag rows load.
- Lesson: Notes-like sidebars need explicit quiet states; async loading should read as intentional, not missing content.

### 84. Notes-like layout metrics

- Problem: Default window, source column, note column, search field, and row widths were scattered as magic numbers, making side-by-side Notes tuning fragile.
- Fix: Added a shared `LibraryNotesLayout` spec and wired the library window, source rows, note table, and toolbar search to it. Added regression checks for split widths, search width, and note-table resizing.
- Lesson: Pixel-level Notes parity needs one source of truth for layout before repeated visual tuning.

### 85. Active-window visual QA

- Problem: The Apple Notes comparison harness could capture Mudsnote while it was not the active foreground window, making toolbar and window chrome colors harder to compare.
- Fix: The visual QA script now explicitly activates Mudsnote before and after the launch delay, then captures the library window.
- Lesson: Visual parity checks need stable foreground state; otherwise screenshots mix product differences with OS focus differences.

### 86. Notes-like source selection tint

- Problem: The library source list still used the system accent selection tint, which appeared blue and diverged from Apple Notes' warmer dark-sidebar selected source rows.
- Fix: Added a local source-selection palette with a dark selected fill and warm foreground tint for selected icons, titles, and counts. Kept the global editor/toolbar accent unchanged.
- Lesson: Notes parity needs local surface palettes; changing the app-wide accent would make unrelated controls less native.

### 87. Note-list hover feedback

- Problem: Note-list rows had selected and keyboard states, but pointer movement over rows did not give a quiet native-feeling preview state.
- Fix: Added a subtle inset hover background for note rows only. Group headers remain non-hoverable, preserving their section-label behavior.
- Lesson: Pointer polish should reinforce existing list semantics without turning section labels into interactive-looking rows.

### 88. Note-list Markdown file drag-out

- Problem: Note-list rows still behaved like static table rows when dragged, so notes could not participate in native macOS file workflows.
- Fix: Enabled external copy dragging for note rows and exposed each note as its backing Markdown file URL. Group headers remain non-draggable.
- Lesson: Drag support should preserve the local-first contract: a dragged note is the real `.md` file, not an app-private object.

### 89. Drag notes to folders

- Problem: Notes could be moved through menus, but the library still lacked the direct drag-to-folder interaction expected from a Notes-like desktop sidebar.
- Fix: Added source-row drop targets for folders, validating dragged notes against the current Markdown library and moving them into the target folder with a subtle drop highlight. Same-folder, trash, non-Markdown, and non-library file drops are rejected.
- Lesson: Drag-to-folder can stay lightweight when it reuses the existing filesystem-backed move path instead of introducing app-private drag models.

### 90. Stable source shell for visual QA

- Problem: The Apple Notes comparison harness could capture the library before deferred source folders and tags finished loading, making screenshots show loading rows instead of the steady Notes-like sidebar state.
- Fix: Made source loading rows quiet once the sidebar has usable root folder rows, and hid transient tag-indexing copy while tags load in the background. The visual QA script now explicitly opens the library path while normal app launches keep the shell-first deferred loading path.
- Lesson: Visual QA needs deterministic state, and users benefit from the same quieter shell when background indexing is slow.

### 91. Note-list row separators

- Problem: Unselected note rows in the middle pane lacked the faint horizontal separators used by Apple Notes, so the list read more like isolated text blocks than a dense scannable note list.
- Fix: Added low-contrast inset separators for normal note rows while keeping section headers and the selected golden card visually clean. Added regression coverage for the separator geometry and opacity contract.
- Lesson: Small list chrome matters for Notes parity; separators should clarify row boundaries without competing with selection or hover states.

### 92. Note-list horizontal rhythm

- Problem: The middle pane still mixed hard-coded title, empty-state, row-content, and list-container insets, making side-by-side Notes tuning brittle and leaving the note list feeling less deliberately aligned.
- Fix: Centralized the note-list horizontal rhythm into layout constants, named the note-list stack for inspection, and exposed note-cell content insets for regression coverage.
- Lesson: Pixel-level Notes parity needs stable spacing contracts before repeated visual passes can converge.

### 93. Stateful source-list toggle

- Problem: The Notes-like sidebar toolbar button existed, but its state was not inspectable and its label did not communicate whether the source list would be shown or hidden.
- Fix: Added a tested source-list visibility contract and updated the toolbar item label, tooltip, and accessibility description as the source list is shown or hidden.
- Lesson: Toolbar parity is not only icon placement; Notes-like controls need stateful behavior that remains correct across direct clicks and future shortcuts.

### 94. Cached drag-move validation

- Problem: Dragging a note across folder rows repeatedly validated the dragged Markdown file by scanning the note library, which could become unnecessary work in large local-first libraries.
- Fix: Cached the movable Markdown path set for drag validation and invalidated it after save, move, delete, restore, and folder mutations. Added coverage that proves a moved note is immediately recognized at its new path after the cache was warmed.
- Lesson: Notes-like drag interactions need to stay responsive during hover, not only after drop; local-first validation can be fast without weakening the real-file contract.

### 95. True all-notes scope

- Problem: The `所有笔记` scope and source counts were still driven by recent-file state, so plain Markdown files copied into the library outside Mudsnote could be omitted from the Notes-like All view.
- Fix: Switched `所有笔记`, Inbox matching, and source-list counts to use the indexed full-library note results while keeping `最近` backed by recent files. Added coverage for a Finder-created Markdown file that appears in All but not Recent.
- Lesson: Local-first interoperability means All Notes must be filesystem-backed, not only app-recent-backed.

### 96. Single library snapshot per refresh

- Problem: After `所有笔记` became filesystem-backed, one library refresh could ask the Markdown index for the full library more than once while updating the note list and source counts.
- Fix: Built one full-library note snapshot per refresh and reused it for All, Inbox, folder, tag, and source-count filtering. Direct launch now renders the library shell from a lightweight recent snapshot first, then refreshes from the shared full-library snapshot after the window is visible. Expanded tag coverage so a tagged note beyond the first visible page is still found.
- Lesson: Notes-grade scale comes from reusing lightweight local snapshots, not from adding a heavier data layer.

### 97. Larger Notes-like library proportions

- Problem: The visual QA side-by-side still made Mudsnote read as a compressed Notes clone: the main window, source column, note list, and toolbar search field were all narrower than the Apple Notes reference.
- Fix: Increased the default library window size and three-column widths, widened the source rows and toolbar search field, and clamped the presented size to the current screen's visible frame so smaller displays remain usable.
- Lesson: Notes parity depends on first-launch geometry as much as individual controls; the app should open into a real desktop editor scale, not a utility-sized library.

### 98. Stronger Notes-like list typography

- Problem: After the window proportions improved, the source list and note list still read too small and light next to Apple Notes, weakening hierarchy even when the three-column layout was correct.
- Fix: Centralized library typography metrics, increased source-list row height and font sizes, raised note-list title/snippet/meta sizes, and gave note rows slightly more vertical breathing room.
- Lesson: Visual parity needs typography contracts alongside layout contracts; otherwise the app can have the right columns but still feel scaled down.

### 99. Notes-like toolbar and editor rhythm

- Problem: The side-by-side visual QA still showed the library toolbar search and editor top spacing as compressed compared with Apple Notes.
- Fix: Centralized toolbar search and editor spacing metrics, widened/tallened the toolbar search field, increased its text size, and opened up the editor top inset plus date/title/title-body spacing.
- Lesson: Toolbar balance and editor rhythm should be controlled by shared layout metrics so visual QA can tune the Notes surface without scattering magic numbers.

### 100. Copy Markdown content from library

- Problem: The Notes-like export/share surface still only exposed file-oriented actions such as Finder reveal, path copy, and exporting a separate Markdown file.
- Fix: Added `复制 Markdown 内容` to the library more menu and note context menu. It saves pending edits when needed, reads the selected Markdown file, and places the full note Markdown on the pasteboard. Trash scope keeps it disabled.
- Lesson: Richer sharing can stay lightweight by adding local Markdown destinations before introducing heavier share/export infrastructure.

### 101. System share from library

- Problem: The Notes-like toolbar showed a share-style icon, but it still launched only a save-panel export instead of offering the system share sheet Apple Notes users expect.
- Fix: Changed the toolbar share icon into a compact share/export menu with `分享...`, `复制 Markdown 内容`, and `导出 Markdown...`. The context menu and more-actions menu now expose the same system share action, and the share path saves pending edits before handing the current Markdown file to macOS sharing services.
- Lesson: Share parity can stay local-first: hand the existing Markdown file to system services instead of adding sync, accounts, or a proprietary export format.

### 102. Native menu toolbar entries

- Problem: The share/export and more-actions toolbar icons behaved like ordinary buttons that manually popped menus, which was less native than Apple Notes' menu-style toolbar controls.
- Fix: Switched both controls to `NSMenuToolbarItem`, kept their menus rebuilt with current selection/trash state, and added regression coverage that the default toolbar uses native menu toolbar items.
- Lesson: Notes-like polish should prefer AppKit's toolbar primitives when they fit; fewer custom popup paths make state and accessibility easier to keep aligned.

### 103. Multi-note file actions

- Problem: The Notes-like note list could share, copy, export, or delete only the currently loaded note, leaving multi-selected notes below Apple Notes' file-action workflow.
- Fix: Enabled multi-selection in the note list and extended file actions to the selected Markdown set. Sharing passes all selected files to macOS sharing services, path/content copy handles multiple notes, multi-export copies selected Markdown files into a chosen folder with conflict-safe names, and delete/trash works across the selected set.
- Lesson: Multi-note parity can stay lightweight by treating selected notes as plain files; no database or sync layer is needed for useful batch actions.

### 104. Selection-count action wording

- Problem: After adding multi-note actions, menus still used single-note labels like `分享...` and `移到文件夹`, and moving selected notes still only handled the loaded note.
- Fix: Added selection-count-aware labels for share, copy, export, Finder reveal, move, delete, restore, and permanent delete actions. The move-to-folder path now moves every selected Markdown note, while single-note-only open-in-separate-window is disabled for multi-selection.
- Lesson: Multi-selection parity requires the UI contract and the action contract to match; labels should tell the user exactly when an operation will affect several notes.

### 105. Multi-note drag-to-folder moves

- Problem: Dragging notes onto a source-list folder still processed only the first dragged Markdown file, so multi-selected note drags did not match the batch move behavior users expect from Apple Notes.
- Fix: Source-list folder drop targets now read all dragged file URLs, validate the full Markdown set, reject mixed invalid drops, and move every dragged note into the target folder through the existing local-first move path.
- Lesson: Drag parity should share the same batch action contract as menus; hover validation stays fast through the existing movable-path cache while the drop keeps real `.md` files as the source of truth.

### 106. Persistent lightweight search index

- Problem: The Notes-like library could prewarm a Markdown search index only in memory, so relaunching a large local library still had to parse every Markdown file again before search, tags, and All Notes felt fully warm.
- Fix: Added an App Support JSON cache for the lightweight search snapshot. The cache is used only when the root set and every Markdown file signature match, and corrupt or stale caches fall back to rebuilding from the real files.
- Lesson: Scale work should stay local-first and disposable; a cache can make relaunch faster without becoming a second source of truth.

### 107. Larger desktop Notes canvas

- Problem: Side-by-side visual QA still showed the main Notes-like library opening closer to a utility window than Apple Notes' broad desktop editing canvas, with source and note columns feeling compressed.
- Fix: Increased the default presented window target, widened the source and note columns, widened note-table sizing, and expanded the toolbar search field while preserving the existing screen-clamping behavior for smaller displays.
- Lesson: Notes parity needs the first opened window to feel like the primary workspace; column polish is hard to judge while the whole canvas is undersized.

### 108. Larger Notes-like list typography

- Problem: After the main canvas was widened, the source list and note list still looked scaled down compared with Apple Notes, making hierarchy and selected-note emphasis weaker than the reference.
- Fix: Increased source-row height, source/group/count font sizes, note-list header size, group row height, note row height, and note title/snippet/meta font sizes. Slightly expanded note-cell padding so larger text has room without clipping.
- Lesson: Visual parity needs typography and row-density tuning after canvas tuning; larger windows make undersized list text more obvious.

### 109. Editor search match highlights

- Problem: Search results highlighted matches in the note list, but opening a result did not show the matching text in the editor, so search-to-edit felt less like Apple Notes.
- Fix: Added disposable editor-side search highlights for the active query. Highlights are tagged with a private attribute, cleared when search is cleared, and suppressed from dirty/autosave handling so Markdown serialization stays unchanged.
- Lesson: Search polish should stay visual and reversible; retrieval metadata must not leak into the local Markdown source of truth.

### 110. Larger Notes-like editor typography

- Problem: After the library canvas and lists were enlarged, the right editor still read slightly undersized against the Apple Notes reference, especially the title/body relationship.
- Fix: Added explicit library-editor typography metrics and increased the editor date/status, title, body, bold, italic, and code font sizes without changing the quick-capture editor theme.
- Lesson: The Notes-like library editor needs its own typography contract; quick capture and desktop review/editing should not be forced to share the same scale.

### 111. Multi-note drag preview count

- Problem: Multi-selected notes could be dragged to folders, but the drag preview did not clearly communicate that several Markdown notes were moving together.
- Fix: Added a Notes-like piled drag preview for note-list drags with a count badge for multi-note selections. The dragged payload remains the real Markdown file URLs, so folder drops and external file workflows keep the same local-first contract.
- Lesson: Batch interactions need visible feedback as well as working commands; count badges reduce destructive-action ambiguity without adding app-private drag models.

### 112. Background library indexing status

- Problem: Direct launch intentionally shows a lightweight note-list snapshot before the full Markdown library scan completes, but the note-list count looked final while background indexing was still running.
- Fix: Added a temporary `正在索引...` note-list count state during deferred full-library hydration. The shell remains fast, the first note still opens without focusing search, and the label returns to the normal count after the background snapshot is applied.
- Lesson: Performance work needs visible progress state; keeping launch asynchronous should not make the library feel silently incomplete.

### 113. Recent-search scope and single-read indexing

- Problem: Search indexing read each Markdown file twice, and the `最近` scope reused full-library search so unopened filesystem notes could appear as recent results. The assembled app bundle was also not signed as a whole, causing strict verification to fail.
- Fix: Centralized parsing of already-read Markdown text, added a recent-file search path that filters before ranking and limiting, and signed the final app bundle by unique certificate hash with an ad-hoc fallback. Added regression coverage for unopened files in recent search.
- Lesson: Local-first performance and correctness share the same boundary: read each source file once, then apply explicit scope membership before ranking; verify the final installed bundle rather than only the executable.

### 114. Native editable Markdown tables

- Problem: Table insertion still exposed raw Markdown pipes and separator rows in the editor, so the visible result remained far from Apple Notes even though the saved format was portable.
- Fix: Rendered Markdown table blocks as native AppKit grids, kept lossless Markdown serialization, and moved Tab navigation plus row/column insert/delete actions onto explicit cell metadata. Empty cells remain editable and serializable, table-end structural newlines no longer leak into saved Markdown, and note-list previews show readable cell text instead of pipe syntax. Added installed-app editing, autosave, restart, and visual verification plus regression coverage.
- Lesson: Rich local-first editing should hide storage syntax without replacing it; native presentation and explicit interaction metadata can sit on top of plain Markdown as long as round-trip behavior remains the contract.

### 115. Native link management and clean previews

- Problem: Rich links could be inserted but not managed afterward, and note-list previews still exposed raw `[label](url)` plus other Markdown markers instead of Apple Notes-like readable text.
- Fix: Added native link context actions for open, edit address, copy, and remove in both library and floating editors, plus pure Command-click opening and undo-aware floating-editor updates. Link labels remain unchanged while standard Markdown URLs update on disk. Preview generation now strips link, emphasis, code, heading, checklist, and list syntax through cached lightweight regular expressions, with a disposable search-index schema bump so stale raw previews rebuild automatically.
- Lesson: Notes-like rich editing does not require a proprietary document model; keep semantic attributes in the editor, plain Markdown on disk, and derived list previews cheap and disposable.

### 116. Local Finder and image paste

- Problem: Pasting Finder files into the rich editor still followed AppKit's transient attachment path, so pasted content could appear in memory without being copied into the local note library or serialized as portable Markdown.
- Fix: Routed standard `Cmd+V` through the Markdown editor, normalized Finder file URLs and clipboard images into shared local attachment storage, inserted native image/file previews, and saved stable relative Markdown links. Internal `Attachments` directories are now excluded from source navigation and note indexing.
- Lesson: Paste behavior must be verified through the installed app's real keyboard path; parser-only tests cannot prove that AppKit command routing reaches the local-first persistence layer.

### 117. Portable HTML and RTF paste

- Problem: Copying formatted content from a browser, TextEdit, or another notes app collapsed to plain text, so headings, emphasis, links, and lists were lost before they reached the Markdown document.
- Fix: Added a lightweight AppKit-backed HTML/RTF normalizer that maps headings, bold, italic, underline, strikethrough, links, bullets, numbering, and fixed-width runs into the existing rich Markdown model. Exact `Cmd+V` routing now inserts safe paragraph boundaries beside existing text, and rich text wins over incidental image flavors without changing Finder-file or pure-image paste.
- Lesson: Rich paste should reuse the system document parser for input and the existing Markdown codec for output; installed-app verification must include insertion beside existing text, autosave, and restart reload.

### 118. Persistent sidebar disclosure state

- Problem: Folder and Tags disclosure choices reset whenever the Notes-like library window or app reopened, making repeated navigation less predictable than Apple Notes.
- Fix: Persisted expanded/collapsed folder paths and folder/tag section state in lightweight preferences, restored them before the source list is built, and kept stored paths synchronized through folder rename and delete lifecycles. Cleaned the content-state visual fixture so weekday metadata is not duplicated by fixture text.
- Lesson: Navigation state belongs in tiny durable preferences, not the note index; persistence should preserve the user's hierarchy without adding filesystem reads to launch or source navigation.

### 119. Persistent resizable Notes workspace

- Problem: Required width constraints locked the source and note columns to their startup sizes, so the three-pane workspace could not be adjusted like Apple Notes and source visibility reset with each new window.
- Fix: Replaced locked widths with constrained native split-view dividers, kept the editor as the window-resize absorption column, and persisted source width, note width, and source-list visibility in lightweight preferences. Drag updates are coalesced before writing preferences, while window close still persists immediately. Added cross-window regression coverage and installed-app restart verification.
- Lesson: Workspace geometry should remain native and user-controlled; small preferences can restore layout without adding note reads, indexing work, or a second document model.

### 120. Silent recovery from stale recent notes

- Problem: The lightweight launch snapshot could contain a recently opened Markdown path that had since been removed outside Mudsnote, causing direct launch to block on an `无法打开笔记` warning before the full library snapshot arrived.
- Fix: Missing-file failures during asynchronous initial hydration now remove only the stale recent reference, rebuild the current lightweight rows, and continue loading the next note. Other load failures still surface normally, and recent-list construction remains free of synchronous metadata reads.
- Lesson: Fast launch snapshots must tolerate stale derived state; repair the disposable reference on confirmed `ENOENT` instead of turning an expected external-file change into a modal startup failure.

### 121. Durable iOS pending capture recovery

- Problem: A non-empty iOS pending queue encoded dates as ISO-8601 but restored them with the default decoder, and replay after a successful write could append the same memo twice if queue cleanup had been interrupted.
- Fix: Matched the queue decoder to its persisted format, automatically replayed queued captures, made coordinated Markdown writes idempotent with hidden markers, preserved those markers through Inbox actions without exposing them in memo text, and added App Store privacy declarations plus regression coverage.
- Lesson: A capture is only durable when restart recovery is both readable and safe to repeat; recovery metadata must survive user actions while remaining invisible in portable Markdown rendering.

### 122. Coordinated iOS library snapshots and Inbox actions

- Problem: The iOS reader recursively scanned the same folder several times from its main-actor refresh path, reported only the 24 recent files as the total note count, and rewrote Inbox actions from a potentially stale UI snapshot that could discard external or iCloud appends.
- Fix: Added one file-store actor inventory for Inbox, exact Markdown counts, recent files, attachments, and conflicts, then made delete, pin, and tag coordinate a fresh read-modify-write against the current Inbox. Added large-library and external-append regression coverage.
- Lesson: Local-first UI state is a view of the filesystem, not an authority; inventory once off the UI actor and re-read coordinated content immediately before destructive mutations.

### 123. Bounded and type-safe iOS attachments

- Problem: Photo imports always used a `.jpg` suffix regardless of their real bytes, individual and combined attachments were unbounded, and repeated failed writes could grow the base64 pending queue without a cap.
- Fix: Detect image content with ImageIO and UTType, enforce attachment count and image/audio/draft size limits before persistence, preflight file sizes before loading imports, and cap pending queue items plus encoded attachment volume. Queue rejection now explicitly keeps the current draft open instead of implying that another pending item made it durable.
- Lesson: Attachment safety needs defense at import, draft preparation, and recovery persistence; a queued-state message is valid only when the current capture actually reached durable storage.

### 124. Recoverable iOS folder authorization

- Problem: A malformed bookmark surfaced an opaque Foundation error, and restored bookmarks were accepted without checking that the target still existed and was a directory, leaving moved, removed, or revoked folders stuck in an unclear failure state.
- Fix: Classify bookmark corruption, unavailable targets, and non-folder selections, validate reachability before accepting restored access, clear stale in-memory roots on failure, and provide both reselect and clear-old-authorization actions in the recovery screen.
- Lesson: A security-scoped bookmark is only a locator and permission hint; every launch must validate the current resource and keep an explicit path back to folder selection.

### 125. Honest iOS integration scope

- Problem: The main app compiled a `ShareExtensionReference` string describing a future extension even though no Share Extension target or usable share-sheet flow existed.
- Fix: Removed the dead placeholder and its Xcode project references; the first commercial scope now explicitly consists of the app, Quick Capture widget, deep links, and App Intents.
- Lesson: Release scope should describe shipped capabilities only; future integration notes belong in product planning, not in the production binary.

### 126. Bilingual iOS String Catalog

- Problem: The iOS app mixed hard-coded English and Chinese, while dynamic status, recovery, attachment, and transcription strings bypassed SwiftUI localization entirely.
- Fix: Added a shared English and Simplified Chinese String Catalog to both App and Widget targets, standardized source copy on English, localized dynamic strings with stable format keys, and added runtime bundle coverage for Chinese lookup and formatted limits.
- Lesson: Localization must include non-view state and error paths; translating only SwiftUI literals leaves the most important recovery messages inconsistent.

### 127. Scrollable accessibility onboarding

- Problem: At the largest accessibility Dynamic Type size, the fixed onboarding stack compressed its title, explanation, requirements, and button into truncated single-line fragments.
- Fix: Added a dedicated scrollable accessibility-size layout, preserved the standard centered composition at normal sizes, allowed requirement rows to grow vertically, and kept the primary folder action reachable.
- Lesson: A screen that technically uses semantic fonts can still fail Dynamic Type; verify the maximum category on the installed app and provide scroll rather than allowing layout compression.

### 123. Nonblocking uncached note selection

- Problem: Cache hits and adjacent prefetch made common navigation fast, but selecting an uncached Markdown note still called `String(contentsOf:)` on the main thread; a large file could freeze the Notes-like window and a slower earlier selection could race a later one.
- Fix: Visible-window cache misses now show a lightweight title/date shell, load Markdown in a cancellable user-initiated task, and apply results only when their generation and selected path are still current. Active selection cancels lower-priority adjacent prefetch, while hidden test windows and deterministic visual-QA selection retain synchronous behavior.
- Lesson: Notes-grade navigation needs latest-request-wins scheduling around the existing bounded cache; derived prefetch must never compete with or overwrite the user's active selection.

### 125. Nonblocking note-list thumbnail decoding

- Problem: The note list bounded image dimensions, reused cells, and cached decoded thumbnails, but the first cache miss still ran ImageIO decoding while AppKit configured the row. Opening or scrolling through image-heavy notes could therefore spend decode time on the main thread.
- Fix: Visible library windows now deduplicate thumbnail requests by standardized path, decode them on a utility task, preserve both positive and negative cache entries, and reload only rows still referencing the completed image. Closing the window cancels outstanding work, while hidden test windows retain deterministic synchronous loading.
- Lesson: A window's first layout can occur before `isVisible` becomes true, so presentation intent must be recorded before `showWindow`; visibility alone is not a reliable boundary for keeping first-frame I/O off the main thread.

### 126. Incremental Markdown search-index refresh

- Problem: The persistent search index skipped all Markdown reads only while every file signature matched. Editing one note invalidated that equality check and reparsed the entire library even though nearly every cached entry was still current.
- Fix: Index refresh now reuses unchanged entries from the same-root in-memory or disk snapshot by standardized path and modification-date-plus-size signature, reparsing only added or changed Markdown files while naturally dropping removed paths. Added regression coverage proving a one-file change in a three-note library performs one content read through both memory and relaunch-style disk refresh paths.
- Lesson: A disposable filesystem index should validate the whole namespace but rebuild only the changed records; snapshot invalidation does not need to imply full content rehydration.

### 127. Notes-like macOS menu commands and new-note state

- Problem: The desktop app had no deliberate native main-menu structure, the status-item menu misleadingly displayed `Command-N` for quick capture, and creating an unsaved blank library note could still show the no-selection overlay with disabled editing tools. Menu dismissal could also restore focus to the list instead of the new title.
- Fix: Added a compact native app/File/Edit/View/Window menu with responder-chain editing commands, `Command-N` library note creation, `Command-F` library search focus, sidebar toggling, settings, close, minimize, and zoom. New unsaved notes now have an explicit editing state, current-date header, hidden no-selection overlay, enabled tools, and next-run-loop title focus without opening the quick-capture window.
- Lesson: A blank document is not an empty selection. Native command routing and explicit document state must agree, or a visually correct editor still feels inert after a standard shortcut.

### 128. Stable full-library index for scoped search

- Problem: Searching inside a folder rebuilt the search index with that folder as the root and replaced the persisted full-library snapshot. Returning to All iCloud then rescanned the whole library. Inbox and tag search also applied their scope after the global result limit, so valid scoped matches could disappear behind higher-ranked notes elsewhere.
- Fix: Added directory, exact-tag, and Inbox search APIs that filter full-library index entries before ranking and limiting. Library scopes now use those APIs instead of alternate index roots or post-limit filtering, preserving the full snapshot in memory and on disk while returning the correct top results within each scope.
- Lesson: Search scope is a query predicate, not an index ownership boundary. Keep one authoritative local-library snapshot and apply scope before ranking so performance and result completeness reinforce each other.

### 129. One-validation active search sessions

- Problem: Even after preserving one full-library index, every debounced search-field query still enumerated the library and reread every file signature before scoring. Fast typing therefore repeated the same filesystem validation for each accepted character, and `Command-F` could lose search focus when menu tracking ended.
- Fix: Added immutable `NoteSearchSession` snapshots that validate the full index once, then serve all-notes, recent, directory, exact-tag, and Inbox queries entirely in memory across character changes and scope switches. The library releases the session when search clears and invalidates it after saves, deletes, restores, folder mutations, or moves. Search focus is reasserted on the next main-loop turn after native menu dismissal.
- Lesson: Search freshness and query evaluation have different lifetimes. Validate once at session entry, invalidate on authoritative mutations, and keep interactive ranking free of repeated filesystem work.

### 130. Event-driven external Markdown refresh

- Problem: Markdown files edited, created, moved, or deleted outside Mudsnote stayed invisible until the user changed source scope, cleared search, or restarted the app; an active search session could therefore remain stale.
- Fix: Added a recursive, coalesced FSEvents monitor for configured note roots. External Markdown changes now invalidate the active search session, refresh list metadata and source counts, and reload a clean selected note without polling. Mudsnote records its own save/move/delete paths briefly so autosave events do not cause a second editor reload or move the caret.
- Lesson: A local-first editor should react to filesystem events rather than poll, but it must distinguish its own writes from external ones or correctness work becomes an interaction regression.

### 131. Reference-scale Notes library

- Problem: The visual harness downscaled Mudsnote's `1420x860` window beside a `931x623pt` Apple Notes reference, making oversized columns, rows, and typography look deceptively close; at native point size the app still felt substantially larger than the earlier preferred version.
- Fix: Restored a compact `1080x720` default shell, rebalanced the source/list columns to `250/250pt`, reduced source and note rows to `36/76pt`, returned list and editor typography to native Notes-like sizes, narrowed editor/search insets, and retained the approved no-rim toolbar groups. Added a one-time layout-scale migration so stored `320/304` pane widths cannot re-expand the new shell.
- Lesson: Visual parity must compare both normalized screenshots and native point geometry. Scaling a larger implementation down for presentation can hide the exact size regression the user experiences.

### 132. Persistent Notes workspace frame

- Problem: Mudsnote remembered source/list divider widths but forced the main window back to the centered default size on every launch, unlike a normal Notes workspace.
- Fix: Persisted the library window position and size through the existing lightweight frame model, coalesced move/resize notifications before writing, restored the frame across launches, clamped stale frames back onto the nearest visible display with the current minimum size, and kept canonical visual QA isolated from personal window state.
- Lesson: Window geometry is part of desktop document state. Persist it cheaply, but keep deterministic visual tests and offscreen-display recovery as explicit boundaries.

### 133. Inline folder creation and quiet saves

- Problem: New Folder opened a modal prompt, and normal saves could unexpectedly reveal the Markdown file in Finder.
- Fix: Added `Shift-Command-N`, inserted an editable folder row directly in the source list with Return/Escape behavior, and removed automatic Finder reveal from saves and preferences while retaining the explicit Finder command.
- Lesson: Library organization should stay in context, and persistence should remain quiet unless the user explicitly requests a filesystem action.

### 134. Inline folder rename

- Problem: Folder creation was inline, but Rename Folder still opened a modal alert and broke the source-list workflow.
- Fix: Unified folder creation and rename under one inline edit state. Rename now replaces the original row in place, preserves hierarchy and parent capture, supports native IME input, commits with Return or focus loss, and cancels with Escape.
- Lesson: Create and rename are two operations on one list-editing primitive; sharing that primitive keeps focus, error recovery, and filesystem behavior consistent.

### 135. Quiet blank editor state

- Problem: The empty-note visual fixture still rendered a centered “Select or create a note” overlay even though a blank note was selected, unlike Apple Notes' quiet editor canvas.
- Fix: Removed the custom editor placeholder layer and its repeated state updates from note loading, typing, saving, navigation, and removal paths. Empty notes and no-selection states now keep the editor canvas blank.
- Lesson: A document editor does not need instructional copy in its primary canvas; removing non-native state is both more faithful and cheaper than maintaining visibility rules for it.

### 136. Source-list keyboard continuity

- Problem: Source rows changed scope with the mouse, but focus returned to the note table and Up/Down could not continue through folders like Apple Notes.
- Fix: Added a focusable source-button responder that routes both raw arrow events and AppKit `moveUp:`/`moveDown:` commands through one visible-row navigation path. Source actions now reclaim focus after their scope reload completes without drawing an extra focus ring.
- Lesson: Desktop list navigation should be owned by the action's final responder state, not by mouse-event timing; one command boundary keeps accessibility, keyboard, and pointer activation consistent.

### 137. Source hierarchy keyboard navigation

- Problem: Up/Down moved across visible source rows, but nested folders still required disclosure-button clicks and offered no Apple Notes-style hierarchy navigation.
- Fix: Added Left/Right responder commands that reuse the persisted folder disclosure model. Right expands a collapsed folder, then enters its first child; Left returns to the parent or collapses an expanded folder while restoring focus by URL after row reconstruction.
- Lesson: Hierarchy navigation should operate on the authoritative folder rows and reacquire rendered controls after mutation; retaining a view across a disclosure rebuild is both fragile and unnecessary.

### 138. Notes-style paragraph format menu

- Problem: The `Aa` menu exposed only H1 and treated an already active heading as a toggle back to body, so it was neither a complete nor stateful paragraph-style chooser.
- Fix: Added H1, H2, H3, Body, checklist, bullet, and numbered paragraph styles alongside inline formatting, grouped them like a native format menu, displayed the active style, and made menu paragraph commands idempotent while preserving toggle semantics for dedicated toolbar actions.
- Lesson: A style chooser and a shortcut toggle are different commands. Sharing rendering primitives is useful, but their interaction semantics must remain explicit.

### 139. Native inline folder field editor

- Problem: The inline folder row used a standalone `NSTextView`, so it never participated in AppKit's shared field-editor lifecycle and first-input replacement could race with focus, especially when an input method began marked-text composition.
- Fix: Replaced it with a single-line `NSTextField`, select the default name only after its window field editor exists, and moved Return, Escape, and focus-loss handling onto `NSTextFieldDelegate`.
- Lesson: Native single-line renaming should use the platform field-editor contract; input methods reveal responder timing bugs but are not the source of them.

### 140. Notes-style link sheet

- Problem: Link insertion and editing used blocking `NSAlert.runModal()` prompts with only a URL field, unlike Notes' window-attached Link To and Name workflow.
- Fix: Added a shared two-field link sheet for library and floating editors, destination-gated confirmation, Return/Escape handling, selected-text name defaults, editable link labels, and focus restoration after dismissal.
- Lesson: Reference-app interaction should be measured directly. Notes uses a window-modal sheet rather than a popover, and preserving that distinction keeps other note windows responsive.

### 141. Notes-style list sorting options

- Problem: The list-options menu led with a disabled display-mode row, ordered grouping before sorting, and omitted Notes' creation-date sort; visible row dates were always edit dates.
- Fix: Matched the core Notes menu hierarchy with Sort By first and Group By Date second, added persistent creation-date sorting and grouping, and made row dates follow the active date basis.
- Lesson: A sort mode is also a presentation contract. Group headers and row metadata must use the same date, and creation metadata should ride the existing indexed file-attribute read instead of adding another scan.

### 142. Native macOS 26 chrome and complete table edge

- Problem: Toolbar groups still simulated material with flat CALayer fills, the source sidebar read as part of the flat split background, and a 100% native text-table width clipped its trailing border.
- Fix: Replaced custom toolbar capsules and circular controls with `NSGlassEffectView`, presented the source list as an independent dark sidebar-material surface with a native rounded boundary, preserved the collapsed list-first layout, and reserved a fractional table-layout inset so the right stroke remains drawable.
- Lesson: Native material should own its rendering instead of being approximated by static alpha fills. Full-width AppKit text blocks also need a small paint allowance because their border is drawn at the layout boundary.

### 143. Full-height native sidebar region

- Problem: The rounded sidebar began below the titlebar, leaving traffic lights and source toolbar icons on the shared window background instead of inside the independent Notes-style region.
- Fix: Migrated the three-pane root to `NSSplitViewController`, represented the source pane with a full-height `NSSplitViewItem.sidebar`, the note list with a content-list item, and constrained source rows to the sidebar safe area. Collapse now uses the native split item while preserving stored widths and tracking separators.
- Lesson: A full-height sidebar is a window-structure decision, not a corner-radius adjustment. The titlebar participates only when AppKit owns the sidebar item and the window uses full-size content layout.

## Maintenance Rule

For every future Mudsnote fix:

1. Add a new numbered iteration.
2. Record the visible problem, the concrete fix, and the lesson.
3. If the issue remains partially unresolved, add it to the open-issue section instead of hiding it.

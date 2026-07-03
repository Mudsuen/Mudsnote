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

## Maintenance Rule

For every future Mudsnote fix:

1. Add a new numbered iteration.
2. Record the visible problem, the concrete fix, and the lesson.
3. If the issue remains partially unresolved, add it to the open-issue section instead of hiding it.

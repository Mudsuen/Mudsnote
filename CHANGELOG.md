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

### 253. Corrected iOS folder, capture, and preview behavior
- Problem: A heading disclosure affordance was added without product intent, the folder drawer lost its hierarchy, its selection semantics and top material landed on the wrong surfaces, new captures exposed internal IDs and timestamps, and native preview selection handles disappeared.
- Fix: Headings remain presentation-only; the recursive folder drawer is restored while folder taps filter the existing home timeline. The top chrome keeps the adaptive canvas color and uses the native soft scroll-edge blur through the former 128-point header boundary, so content progressively loses focus without a white opacity gradient or an extra compositing layer; only the active surface renders that blur. The drawer keeps one Folders title, centers it within the revealed panel, and moves Settings into the Library card. Independent captures use readable collision-safe names and clean Markdown without hidden write markers or timestamp headings, and iOS new notes no longer offer a per-note destination: saves always use the default folder from Settings. Unchanged autosaved new notes still finalize on edit exit, native selection spans rendered paragraphs and list markers, and appearance can follow the system or stay explicitly light or dark.
- Lesson: Navigation structure, content projection, storage metadata, and selection interaction are separate contracts; changing one must not silently reshape or expose another.

### 252. Unified macOS Quick Capture editor
- Problem: Quick Capture split a note into separate title and body fields, while its visually raised tag button synchronously scanned the note library and could stall the entire panel.
- Fix: Quick Capture now opens directly in one native editor, derives the saved title from the first sentence while preserving that sentence in the body, and losslessly folds legacy title/body drafts into the unified content. The tag button and its blocking entry point are removed; Inbox, cancel, and save share one 28-point footer centerline with restrained opacity/scale press feedback.
- Lesson: Capture should keep one uninterrupted writing surface, and a secondary action that requires library-scale work should not occupy the critical save path when inline Markdown already provides the same semantics.

### 251. Cancelable bounded macOS library search
- Problem: Canceling a cold or warm search stopped result publication but did not stop the detached index work, so old queries could keep scanning, parsing, and holding the shared build lock while the latest query waited; matching also built snippets and sorted every hit before applying the visible limit.
- Fix: Search cancellation now propagates through lock acquisition, directory enumeration, index refresh, file reads, matching, and scoped queries. Ranking retains only the exact top results, snippets are built only for those results, trash search parses each candidate once, unresolved iCloud items and malformed or oversized Markdown fail softly, and the persistent JSON cache has a hard size ceiling.
- Lesson: Latest-query-wins requires canceling the underlying synchronous work, not only rejecting stale completion callbacks, and every cache or result limit must bound the work performed before the limit is applied.

### 250. Independent iOS capture, playable audio, and unified black glass
- Problem: Quick capture destinations were existing Markdown files, so choosing one appended into user content and `Inbox.md` absorbed new notes; successful writes could remain absent from the home projection. Audio attachments lacked an explicit non-overwriting local save, while the gray-blue visual shell and parallax drawer conflicted with the intended native glass hierarchy.
- Fix: Capture now chooses a folder and creates a uniquely named independent note, migrates recovered legacy file targets to their parent folder, invalidates file-store caches, and advances the library revision after every applied snapshot. Audio attachments play in-app with visible failures and save into the Files-visible `Saved Audio` directory using collision-safe names. The iOS shell now uses a true-black canvas, native glass cards and editor toolbar, consistent scale press feedback, full-width finger-tracked drawer translation, vertical-scroll-compatible gesture arbitration, landscape support, and completion-only haptics.
- Lesson: A destination picker must model the ownership unit it creates, durable writes and UI projections need one revision contract, and glass, gesture, and feedback behavior should be shared system-wide rather than patched per control.

### 249. Unified iOS quick capture and reversible folder gestures
- Problem: Quick Note had regressed to a second editor while Quick Recording used the capture composer, the latest drawer changes weakened diagonal swipe recognition and made closing look like an overlay fade, and recording controls retained opaque emphasis without complete state feedback.
- Fix: Both bottom-bar entries now open the same capture composer and record button; Quick Recording alone auto-starts audio. The verified document date-and-time presentation remains tied to the file timestamp and scrolls with the body. Folder gestures once again move the home surface in opposite finger-tracked directions, settle with the validated spring, and emit a light haptic only after a current completed transition. Voice emphasis and audio status surfaces are transparent, with 44-point entry targets and explicit recording or permission-failure accessibility values.
- Lesson: Entry points may select different initial state without owning different UI, and gesture feedback must be derived from the rendered transition rather than pre-empting it.

### 248. Direct iOS voice capture and responsive library shell
- Problem: Quick Capture had no direct voice entry, recording and transcription could outlive a dismissed sheet, the folder drawer displaced the note timeline, and cold folder preparation plus duplicate scene refreshes delayed interaction.
- Fix: The Notes-style bottom bar now keeps Search, Voice, and New Note as separate actions; voice entry opens an explicit recording state machine that preserves audio before optional transcription and invalidates stale sessions. The folder directory is now an overlay drawer with deliberate axis locking, immediate commit haptics, RTL and Reduce Motion behavior, while folder preparation runs on the file-store actor and scene refreshes coalesce behind the initial index.
- Lesson: Capture must make the durable attachment independent from best-effort transcription, and navigation or launch work should preserve one responsive visual surface while asynchronous state catches up.

### 247. Conflict-safe note and recovery writes
- Problem: A macOS autosave could replace an externally edited note, unreadable files could be rewritten from an empty fallback, and iOS recovery could discard staged data or quarantine a healthy queue after transient I/O failures.
- Fix: macOS saves now compare the exact loaded source inside file coordination and preserve local edits as a named conflict copy; in-place updates fail closed on unreadable or missing sources. iOS queue loading now shares the coordinated mutation path and quarantines only validated corruption, while interrupted permanent-delete recovery refuses different-content collisions.
- Lesson: Recovery code must distinguish confirmed corruption from temporary access failure, and concurrent writers must preserve both versions whenever source identity changes.

### 246. Stable iOS Notes interactions
- Problem: The directory drawer hitched at the end of its spring, library setup created an undeletable Daily note without user input, and the reader timestamp stayed pinned while note content scrolled.
- Fix: Drawer presentation now follows one continuous reveal model and emits haptics only after the visual animation is removed; the Daily product feature, automatic folder/file creation, capture destination, shortcut, special presentation, and protection rules are removed while any existing `Daily/` content remains untouched as ordinary user files; reader metadata now scrolls with the note.
- Lesson: Optional capture concepts must not enter the library contract without explicit product intent, and animation completion feedback must follow the rendered transition rather than its logical state change.

### 245. Scan-free macOS folder deletion
- Problem: Deleting a folder synchronously enumerated every Markdown file after moving it to trash, then descendant and root-change file events could repeat folder and library refresh work.
- Fix: Folder deletion now records one directory-level restore mapping, projects known notes from the in-memory snapshot, and suppresses expected descendant and root-change events while preserving unconditional rescans for dropped or invalid event streams.
- Lesson: A whole-directory move should preserve recovery at directory granularity and reconcile from existing projections instead of replaying the same mutation through filesystem monitoring.

### 244. Incremental macOS editor refresh
- Problem: Recent search-link and background-save changes could hold an index lock across filesystem I/O, rescan the whole library after one edit, hash the full note around every save, rebuild the full note list, and repeatedly inspect an unbounded paragraph while typing.
- Fix: Search-index state updates now use a short non-I/O lock, clean readers bypass full validation, saved paths refresh incrementally, and routine iCloud-backed saves remove the obsolete revision/conflict layer. Existing-note saves replace only affected list rows, refresh only current outgoing links and structurally changed source counts, while automatic links run at token boundaries over bounded fragments and source navigation relies on file events instead of unconditional full-library rescans.
- Lesson: Background work still causes visible stalls when its coordination lock, completion reconciliation, or per-keystroke preprocessing scales with the whole library or document.

### 243. Serialized background library autosave
- Problem: Library autosave hashed the current disk revision and performed transactional note writes on the main thread, so large notes or slow volumes could pause editing.
- Fix: The main thread now captures one stable Markdown snapshot, while revision validation and disk persistence run on a serial utility queue; explicit save, navigation, and close drain completed writes before continuing, and newer editor revisions remain dirty.
- Lesson: Background autosave needs a completion barrier and revision-aware UI reconciliation, not only an asynchronous write call.

### 242. Explicit Inbox semantics and event-driven search refresh
- Problem: Notes whose titles merely contained “Inbox” polluted Inbox results and counts, while equal-size external rewrites with restored timestamps could reuse stale search entries.
- Fix: Inbox membership now uses only the configured Inbox directory or an exact `Inbox.md` filename; filesystem events mark changed paths dirty (or force a full refresh after dropped events), and body occurrence scoring no longer allocates split arrays.
- Lesson: Classification needs an explicit identity contract, and a cache must accept authoritative change events instead of trusting lossy metadata signatures.

### 241. Safe cross-directory attachment relocation
- Problem: Moving one note to another directory left its relative image and file references pointing at the old folder, so previews and attachment actions silently broke.
- Fix: Cross-directory note updates and library moves now copy referenced files from the source `Attachments` tree, preserve its subdirectory structure, resolve filename collisions, rewrite Markdown paths, retain shared source files, and clean copied files if the note commit fails.
- Lesson: A note and its relative attachments form one relocation transaction, but source attachments cannot be deleted until sharing is proven absent.

### 240. Lossless managed Front Matter updates
- Problem: Saving a note rebuilt YAML Front Matter from only `tags`, deleting unknown keys, nested values, comments, and ordering.
- Fix: Existing Front Matter is now retained line-for-line outside the managed `tags` block; block and inline tag forms are read, while tag edits replace or remove only that field.
- Lesson: A Markdown editor that owns one metadata key must treat every other Front Matter byte as user data, not as disposable serialization detail.

### 239. Transactional extension-preserving note updates
- Problem: Renaming or moving an existing note moved the source before writing new content, so a write failure could leave a partial commit; managed `.markdown` and `.txt` files also silently became `.md`.
- Fix: Updates now preserve the source extension, fully stage content in the destination directory, commit the destination before removing the source, and remove the committed destination again if the final source removal fails.
- Lesson: A filesystem rename plus content rewrite is one transaction: validate and stage all fallible content work before changing the source-of-truth path.

### 238. Visible and recoverable library save status
- Problem: Successful saves collapsed back to a bare modification date, while autosave failures relied on a short label and beep without a discoverable recovery path.
- Fix: The editor status now distinguishes saving, saved, conflict, and failure states with semantic color, exposes the same value to accessibility, announces consequential transitions, and points conflict or failure states to Command-S recovery.
- Lesson: Autosave is trustworthy only when users can distinguish progress from completion and can discover how to recover without leaving the editor.

### 237. Coalesced background draft persistence
- Problem: Quick Capture and floating-note autosave encoded JSON and performed atomic disk writes on the main thread after every debounce interval.
- Fix: Draft autosave now serializes disk operations on a utility queue, replaces queued stale snapshots with the newest revision, and synchronously drains the queue before close or termination writes the latest editor state.
- Lesson: Background autosave needs both latest-wins coalescing and a synchronous final barrier; moving writes alone can let an older task overwrite the close-time snapshot.

### 236. Indexed and batched thumbnail refreshes
- Problem: Every completed library thumbnail decode scanned all list rows and gallery items, then reloaded the UI once per image.
- Fix: List and gallery projections now maintain thumbnail-path reverse indexes, and decode completions coalesce their indexed row and item refreshes into one main-queue batch.
- Lesson: Background decoding still needs an indexed, frame-batched completion path or large libraries pay repeated main-thread traversal and layout costs.

### 235. Centralized Simplified Chinese library vocabulary
- Problem: The first copy pass left date groups such as Pinned, Today, and Previous 7 Days in English and kept related Chinese strings scattered across controllers.
- Fix: A focused library vocabulary now supplies navigation, search, counts, empty states, date groups, and placeholders; list and editor dates use an explicit Simplified Chinese locale and format.
- Lesson: A localization pass is complete only when generated grouping and formatter output use the same locale as static controls.

### 234. Revision-aware rich-image thumbnail cache
- Problem: Rich-editor images were decoded off the main thread but every attachment and reopened window still repeated the same ImageIO work.
- Fix: The bounded background decoder now reuses downsampled images by standardized path, modification time, file size, and target pixel budget, while file revisions automatically select a fresh cache entry.
- Lesson: Moving expensive work off the main thread fixes responsiveness; revision-aware bounded reuse is still required to fix repeated CPU and memory cost.

### 233. Undoable and keyboard-accessible image sizing
- Problem: Image-edge dragging persisted only at mouse-up but still could not be undone as one action, and image sizing had no discoverable keyboard or VoiceOver alternative.
- Fix: Each completed drag now registers one Undo/Redo operation, image context menus expose fit, percentage, original-size, and reset commands, and focused images provide accessibility actions plus a spoken width value.
- Lesson: A pointer gesture is incomplete until the same state change is reversible and available through the responder chain and accessibility APIs.

### 232. Guarded draft close and application termination
- Problem: Quick Capture and floating-note windows attempted a final draft write only after closing had already committed, swallowed failures with a beep, and application termination did not aggregate draft persistence results.
- Fix: Draft persistence now reports errors, clears dirty state only after success, blocks window close and app termination when a draft cannot be saved, preserves the editor, shows an actionable error, and prevents floating-note transitions after a failed draft flush.
- Lesson: Every editable window needs a preflight persistence boundary; cleanup callbacks are too late to protect in-memory work.

### 231. Consistent Chinese library states
- Problem: The macOS library mixed English source names, search controls, counters, empty states, date labels, and note placeholders into an otherwise Chinese interface.
- Fix: User-visible library navigation and transient states now use one Chinese vocabulary across the sidebar, toolbar search, list and gallery projections, Recently Deleted, accessibility labels, and result counters.
- Lesson: Localization consistency includes loading, empty, accessibility, and metadata text—not only primary buttons and menus.

### 230. Non-blocking rich-editor image decoding
- Problem: Rendering a note decoded every local image synchronously on the main thread, so opening a note with large or multiple images could stall editing and window interaction.
- Fix: The rich editor now reads only lightweight image dimensions while building the document, displays a correctly sized placeholder, and decodes a bounded thumbnail off the main thread when the attachment is first drawn.
- Lesson: Rich document construction should establish layout from metadata and defer expensive media decoding until display, with the decoded pixel budget capped to the UI's actual needs.

### 229. Lossless Markdown tables and parenthesized links
- Problem: Opening and saving a supported Markdown table could split escaped pipes into extra columns and discard column alignment, while links or local attachments with balanced parentheses were truncated at the first closing parenthesis.
- Fix: Table parsing now tokenizes escaped pipes and backslashes, stores each separator alignment with the native table cells, and restores it during serialization. Inline links, images, and file attachments now locate their destination with escape-aware balanced-parenthesis parsing.
- Lesson: A rich Markdown view must round-trip every syntax form it claims to support; parsing and serialization need the same escaping and delimiter model.

### 228. Transactional window-position reset
- Problem: “重置窗口位置” erased stored layouts immediately even though the settings window presented Save and Cancel, so cancelling still lost the user's window arrangement.
- Fix: Reset is now staged as a pending preference, the button confirms “保存后重置”, Save applies it after validated settings, and Cancel clears the intent without touching stored frames.
- Lesson: Every action inside a Save/Cancel settings window must share the same commit boundary unless it is explicitly presented and confirmed as an immediate operation.

### 227. Debounced background macOS search
- Problem: The global search window and floating-note browser rebuilt and ranked the full search set synchronously on the main thread after every keystroke, causing input stalls and repeated filesystem signature validation in large libraries.
- Fix: Both search surfaces now share a 150 ms debounced, cancellable background search controller that reuses one search session, ignores stale generations, and publishes only the latest results on the main actor. Result limits remain bounded, selection is preserved, and the UI exposes an in-progress state.
- Lesson: Search typing should schedule immutable query work rather than perform it; generation-checked background results keep interaction responsive without allowing an older query to overwrite newer input.

### 226. Complete large-library snapshots
- Problem: The macOS library discarded every note after the 10,000th indexed entry before building source counts and list projections, making older notes and their folder or tag counts silently unreachable.
- Fix: The library snapshot now retains all already-indexed note results for accurate counts and global top-240 projections, while the rendered list remains bounded and virtualized. A 10,001-note regression covers oldest-note title reachability and exact folder and tag counts.
- Lesson: A bounded visible projection must not be implemented by truncating its source of truth; retain the full lightweight index and bound only the rows prepared for presentation.

### 225. Resilient macOS library file monitoring
- Problem: The live library monitor recognized only `.md` files even though the store also loads `.markdown` and `.txt`, and dropped or invalidated FSEvents could be ignored unless they were also marked as directory events.
- Fix: The monitor now recognizes every supported note extension, treats must-scan, user-dropped, kernel-dropped, wrapped-ID, and root-change flags as unconditional full-rescan signals, and never suppresses those recovery events as internal writes.
- Lesson: Incremental filesystem monitoring needs an explicit loss-recovery path; overflow signals describe an invalid event history, not an ordinary item change that can be filtered by path.

### 224. Complete Recently Deleted search
- Problem: Recently Deleted applied its 240-result limit before checking titles, bodies, and tags, so an older matching note could appear to be missing even though it was still recoverable.
- Fix: Trash search now scans candidates in their existing order until it collects the requested number of actual matches, preserves corrupt-file title fallback, and stops promptly when the result limit is reached or the background task is cancelled.
- Lesson: Recovery search must limit matched results rather than the input prefix; correctness matters most when users are trying to locate data they may otherwise assume is lost.

### 223. Keyboard-first floating note search
- Problem: The floating note browser required pointer interaction to choose a result, lost its selection when refreshed, and requested an unbounded candidate list even though only a handful of rows are visible.
- Fix: Search now selects and visibly identifies the first result, supports Up/Down navigation, Return to open, and Escape to close while focus stays in the search field, preserves the selected note across refreshes, exposes selection to accessibility, and bounds search candidates to 100 while retaining all already-open windows.
- Lesson: Compact search panels need one stable selection model shared by keyboard, pointer, refresh, and accessibility; bounding invisible candidates reduces work without hiding active state.

### 222. Reliable external Markdown opening and attachment management
- Problem: Opening a Markdown file outside the configured library during initial library hydration could leave the editor showing an empty loading shell, while attachments were stored beside notes but had no library-wide view for finding missing links or unused files.
- Fix: External Markdown opening now cancels stale initial loading and applies the requested document directly. A new attachment manager scans configured library folders, groups files as referenced, unreferenced, or missing, shows size and reference counts, supports Quick Look, Finder reveal, and opening a referencing note, and only allows confirmed deletion of existing unreferenced files by moving them to the Trash.
- Lesson: Explicit file-open requests must outrank background hydration, and attachment cleanup needs reference-aware inventory plus recoverable deletion rather than implicit filesystem removal.

### 221. Conflict-safe macOS library saves
- Problem: An external editor or synced device could change the open Markdown file after Mudsnote loaded it, while autosave, note switching, or window closing could still overwrite that disk version or leave the list selection out of sync with the editor.
- Fix: The macOS library now records a content revision for the loaded file, refuses to overwrite a changed or unverifiable disk version, keeps local edits and the original selection on cancellation, blocks closing after unresolved save failures, and offers native choices to reload the disk version or preserve local work as a conflict copy.
- Lesson: A file-backed editor needs an explicit compare-before-write and leave-document contract; filesystem event suppression alone cannot prove that a later write is safe.

### 220. Live and stable macOS image resizing
- Problem: Dragging an inserted image edge selected the attachment, persisted every intermediate width, and let AppKit repeatedly restore the text cursor during layout, so the image lagged behind the pointer while the cursor and selection visuals flickered.
- Fix: Image resizing now redraws each drag position synchronously, keeps the horizontal resize cursor for the complete gesture, avoids selecting the attachment, and persists only the final width on mouse-up.
- Lesson: Interactive resizing needs separate transient and durable state; the drag loop should own rendering and cursor feedback while persistence waits for gesture completion.

### 219. Direct edge resizing for inserted macOS images
- Problem: Images inserted into macOS notes rendered at one fixed fitted size, so reviewing a detail or reclaiming editor space required changing the source image instead of adjusting its presentation.
- Fix: Hovering either vertical image edge now exposes horizontal resizing, and dragging that edge resizes the image proportionally within safe bounds. The chosen width survives reopening the note without rewriting its Markdown or original attachment file.
- Lesson: Local presentation preferences can stay platform-specific while the portable Markdown and attachment bytes remain the durable cross-platform note contract.

### 218. Direct macOS folder actions and stable note snapshots
- Problem: Folder context menus could rename or delete nested folders but not move them, deletion required an extra confirmation despite remaining recoverable from Recently Deleted, and a transient filesystem scan could briefly replace an existing note list with `0 notes`.
- Fix: Nested-folder context menus now offer valid destination folders while excluding the folder itself, its descendants, and the current parent. Folder deletion runs immediately and retains the existing recoverable trash behavior. Note snapshot refreshes confirm any disk scan that unexpectedly drops known notes before publishing it to the sidebar and list.
- Lesson: Filesystem-backed navigation should reuse one move contract across drag and menus, and a single lossy scan must not become visible state when cloud synchronization or atomic replacement can make directory enumeration momentarily incomplete.

### 217. Finger-tracking iOS folder drawer
- Problem: Opening or closing the folder drawer required a noticeable initial drag distance, and its first revealed frame also had to construct the drawer hierarchy, making the motion feel detached from the finger.
- Fix: The edge gesture now mounts and starts tracking as soon as the finger touches down, the open drawer recognizes closing movement after 6 points, drag offsets apply with animations disabled, and the drawer unmounts only after a cancelled or completed close settles.
- Lesson: An interactive drawer should reserve animation for release settling; gesture frames need a just-in-time warm hierarchy without leaving an offscreen scroll view attached to the navigation container.

### 216. Consistent light iOS drawer completion feedback
- Problem: Tapping outside the open folder drawer animated it closed without tactile confirmation, while swipe transitions used a stronger impact than the intended light completion cue.
- Fix: Swipe transitions now use a light UIKit impact, and outside-tap dismissal prepares the same feedback before closing but fires it only after the close animation completes.
- Lesson: Every successful drawer transition should share one feedback timing contract regardless of whether it starts from a drag or a backdrop tap.

### 215. Hidden empty backlink section
- Problem: Notes without incoming or outgoing links still reserved editor space for an empty 双链关系 section.
- Fix: The backlink section now disappears completely when both relation groups are empty and returns automatically when either group contains a note.
- Lesson: Relationship UI should consume editor space only when it has navigable information to show.

### 214. In-app local Markdown links and visible backlinks
- Problem: Command-clicking a Markdown link to a local file could reinterpret its filesystem path as a web address and open a browser, while the library offered no way to see which notes linked to or from the current note.
- Fix: Local `file://`, absolute, and relative Markdown destinations now resolve against the current note and open inside the Mudsnote library. The editor also shows a compact 双链关系 section with incoming and outgoing linked notes, including an overflow menu for larger graphs.
- Lesson: Local link navigation and backlink indexing must share one path resolver so the relationship shown in the UI always matches the destination opened by the editor.

### 213. Smooth iOS folder drawer haptic timing
- Problem: Triggering the physical impact in the same main-thread callback that committed the folder drawer spring could delay its first animation frame and make the open or close motion feel uneven.
- Fix: Drawer state changes now run their spring independently and fire the prepared physical impact from the animation completion, while cancelled swipes reset without feedback.
- Lesson: UIKit haptic delivery should not share the animation-start frame with a SwiftUI state transition when the motion itself is the primary feedback.

### 212. Reversible iOS folder drawer gesture
- Problem: The iOS folder drawer could open from the left edge, but its scroll and row-drag gestures could prevent the reverse left swipe from closing it, and successful drawer transitions had no tactile confirmation.
- Fix: The open drawer now gives its horizontal close gesture priority over its contents, accepts the same gesture from the backdrop, and uses a prewarmed UIKit impact generator for one physical medium haptic only after a swipe actually changes the drawer between open and closed.
- Lesson: A reversible drawer gesture must own horizontal intent across interactive descendants while reserving feedback for completed state transitions.

### 211. Reliable macOS preview, links, transient panels, and inactive chrome
- Problem: Moving an outside preview into the library could retain its missing original-path projection, typed web URLs were not reliably decorated after the live edit callback, the floating-window manager could reopen instead of dismissing, and the source scroller plus text-based `Aa` control did not match adjacent native inactive chrome.
- Fix: External projections now prune missing paths and leave preview state when moved under a registered root. Automatic-link decoration runs after AppKit commits text changes. The floating manager toggles from its anchor and monitors outside clicks while respecting that anchor. The source scroller no longer overlaps the split divider, and `Aa` explicitly follows key-window focus tinting.
- Lesson: Temporary projections and panels need lifecycle reconciliation against real filesystem and event state; native image controls and text controls also require separate inactive-state treatment even when they share one toolbar.

### 210. Explicit macOS library and preview folders
- Problem: The macOS source list recreated a synthetic “All iCloud” folder whenever more than one library root existed or an outside Markdown file was previewed, obscuring which folders were actually registered.
- Fix: The source list now contains only registered library folders and the real parent folders of outside files currently projected for preview. Opening an outside file selects that parent folder directly, while temporary preview folders expose only a safe Finder reveal action.
- Lesson: A folder source list should represent concrete filesystem ownership; aggregate scopes can remain search behavior without masquerading as another directory.

### 209. Consistent macOS library dragging and editor commands
- Problem: New notes did not enter the list until their first save, folder and note drops shared misleading between-row feedback, external items could not be dragged into the library, and the main and floating editors exposed different selection, slash-command, indentation, link, and popup-dismissal behavior.
- Fix: New macOS notes now persist and animate into the list immediately. Folder rows can be reordered or moved under another folder, external Markdown and folders can be copied or registered by drag, and note drops are constrained to real folder targets. Both editors now share multi-line Tab/Shift-Tab indentation, automatic plain-link detection with Command-click opening, and selection formatting; the library editor also exposes formatting slash commands, while the floating-note manager closes when it loses focus. The existing setting for descendant-inclusive versus direct-folder-only notes remains the single source of folder-scope behavior.
- Lesson: Shared text views still drift when controllers install different capabilities, and drag feedback is only useful when every shown insertion target maps to a durable filesystem or ordering operation.

### 208. User-owned multi-window floating notes
- Problem: The floating-note manager was sized around a five-result browser, showed a count, info icon, and global close action, replaced the current editor when choosing another note, and reused one saved frame so multiple windows could overlap exactly; an unnamed floating window also had no independent management identity.
- Fix: The compact manager now lists every open floating window by stable window ID with its own close button, uses search only to explicitly add more notes, removes the count and window cap, and lets every floating window open the same shared state. New windows prefer a separate on-screen frame, and the panel uses a narrower adaptive height with scrolling for larger sets.
- Lesson: Multi-window management must model windows rather than search results or file paths; creation, activation, placement, and removal should remain explicit user actions backed by one shared owner.

### 207. Smoother note changes and folder-scoped browsing
- Problem: Creating or deleting a macOS note changed the list abruptly, the floating-note formatting highlight touched the footer edge, Shift-Return still looked like a separate paragraph, and folder selection always included every descendant note.
- Fix: Note insertions and deletions now use bounded native list transitions with a reduced-motion fallback, floating-note toolbar highlights sit inside the footer, and Shift-Return round-trips as a Markdown hard line break rendered within one short-spaced paragraph. Settings now offers either descendant-inclusive browsing or notes stored directly in the selected folder, with matching list, search, and folder counts.
- Lesson: Local-first UI polish must survive persistence and every projection: motion needs stable row identities, soft line layout needs a portable Markdown representation, and folder scope must agree across browsing, search, and counts.

### 206. Arrow cursor through the complete format-button click
- Problem: The selection toolbar declared an arrow cursor while hovering, but applying a format returned first-responder handling to the text editor during the button's mouse-down lifecycle, so the pointer still changed to an I-beam after the action.
- Fix: Format buttons now restore the arrow after dispatching their command and again after the real mouse-down completes. A deferred guard reapplies it after toolbar-state refresh only when the pointer is still inside that button, while cursor-update and mouse-move events keep the same ownership.
- Lesson: A cursor rect is not enough when a control action changes the first responder; cursor ownership must survive the complete click and deferred refresh lifecycle without overriding the destination after the pointer leaves.

### 205. Clean formatting removal and stable selection-toolbar cursor
- Problem: Removing paragraph selection formatting could leave a thin blue underline behind, and applying an option from the floating selection toolbar changed the pointer under that toolbar from the normal arrow to an I-beam.
- Fix: Underline and strikethrough removal now clears their companion color attributes, refreshes typing attributes, and invalidates the affected glyph display. The selection toolbar updates its existing buttons in place and explicitly owns an arrow cursor instead of recreating the hovered button over the text editor.
- Lesson: Removing rich-text decoration requires clearing the complete attribute family and repainting its glyph range; transient controls should preserve their identity and cursor region while refreshing applied state.

### 204. Editable links from the link button
- Problem: Pressing the library editor's Link button while the selection was already inside a link opened an empty Add Link sheet, forcing the destination to be entered again and risking a duplicate link.
- Fix: The Link button now recognizes a caret or selection contained within one existing link, opens the Edit Link sheet with its current destination and name, and updates that link in place on confirmation. Unlinked selections retain the existing Add Link behavior.
- Lesson: Insert-format commands should inspect the semantic content at the current selection and become edit commands when that content already exists.

### 203. Reliable post-merge verification
- Problem: GitHub does not start a new `push` workflow for a merge performed by the repository `GITHUB_TOKEN`, so automatic PRs could pass merge-candidate CI without actually exercising the documented post-merge `main` check.
- Fix: The trusted auto-merge workflow now passes the PR Manifest platform into an explicit `ci.yml` dispatch on `main` immediately after Squash Merge. The merge candidate still receives the single `full` pass; post-merge runs the affected platform's lighter `pr` smoke. The shared Devflow template has contract tests for the ordering and inputs.
- Lesson: Post-merge verification must be explicit and scoped; relying on token side effects can skip it, while blindly repeating the full matrix wastes time.

### 202. Automatic evidence-backed delivery
- Problem: Draft-by-default delivery and moving per-platform baseline SHAs kept accepted work outside `main`, then added repeated context loading, Git archaeology, overlap decisions, and duplicate validation to compensate.
- Fix: Replaced daily baseline markers with latest `origin/main`, Ready PRs carrying a Devflow v2 evidence manifest, one full merge-candidate CI pass, default-branch event-driven Squash Merge for reversible product work, explicit hard stops for external/control-plane risk, and a tested Revert PR command. Legacy PRs remain manual.
- Lesson: Importance should control reporting, not approval. Stable automation comes from objective acceptance, a current merge candidate, independent policy checks, and a real rollback path—not from another moving acceptance marker.

### 201. Guarded platform verified baselines
- Problem: An accepted macOS or iOS UI could remain in an unmerged Draft PR while the next task started mechanically from `main`, allowing internally green CI to ship a visually older baseline and forcing expensive Git archaeology, conflict repair, and repeated validation.
- Fix: Added independent machine-readable macOS and iOS verified baselines. Platform Devflow tasks now declare `--track macos` or `--track ios`, prove the matching baseline is an ancestor, and stop when another open PR touches that platform's configured high-coupling files unless the stacked/combined baseline is explicitly reviewed. Repository verification validates both contracts.
- Lesson: Git synchronization and product acceptance are different facts. A new task must prove both that its branch is current and that it contains the latest accepted product state before implementation begins.
- Superseded by iteration 202: the fixed marker files and `--track` startup gate were removed after the complete workflow review.

### 200. Clear library settings, local Codex, and persistent formatting controls
- Problem: Settings conflated the default new-note destination with vaguely named “managed folders”, the AI pane still required a separate local-model service, the selection-format panel lacked hover/applied feedback and disappeared after every action, and rich-format/undo shortcuts stopped reaching the library editor.
- Fix: Settings now separates a directly changeable default folder from registered library folders and explains that registration never moves files. AI commands use the signed-in local Codex runtime through ephemeral read-only executions, with automatic detection and optional executable selection; the former local-model provider and its URL/model controls are removed. Selection buttons show hover and applied backgrounds, refresh in place after formatting, and retain editor focus. The editor now handles rich-format and undo/redo key equivalents directly while still dismissing the panel for ordinary editing.
- Lesson: Preferences should describe durable user choices, not implementation plumbing; transient editor chrome must preserve both responder ownership and command continuity, while local runtime integration should inherit an existing authenticated tool with the narrowest filesystem permissions.

### 199. Stable caret across autosave and file refresh
- Problem: After autosave cleared the dirty flag, a delayed cache validation or file-system event could reload the selected note through the blank loading shell, repainting the page and resetting the caret to the beginning.
- Fix: Selected-note refreshes now load without clearing the editor, preserve the current selection, and skip text-storage replacement when disk and editor Markdown are equivalent. Every local edit advances a content revision so asynchronous results started before that edit are discarded even after autosave. Tests cover external refresh selection preservation and the autosave-versus-stale-load race.
- Lesson: Dirty state is a save-state signal, not a sufficient concurrency token; asynchronous editor loads need a monotonic local-edit generation and must avoid no-op document replacement.

### 198. Non-blocking selection formatting panel
- Problem: The attempted menu-event replay did not intercept AppKit's tracking loop; pressing Delete while the automatic menu was open selected “Underline” through menu type-ahead instead of deleting text.
- Fix: Replaced the automatically shown tracking menu with a nonactivating icon panel while keeping the editor as first responder. Keyboard input now closes the panel before normal editor handling, so Delete removes the selection without activating a formatting item. Color and conversion choices remain available as explicit submenus.
- Lesson: An automatic editing affordance cannot use a modal menu-tracking loop when the first keystroke must remain owned by the text editor.

### 197. Undo in the concise editor context menu
- Problem: Formatting was undoable from the keyboard, but the intentionally reduced right-click menu did not expose Undo.
- Fix: Added an icon-backed Undo item using the standard macOS responder chain and Command-Z equivalent, ahead of Translate and the editing commands.
- Lesson: A compact editing menu should still expose recovery as a first-class action, especially when nearby formatting commands can change attributed content.

### 196. Selection menu yields to normal editing
- Problem: The automatic formatting menu could keep AppKit menu tracking active after selecting text, forcing users to dismiss it before Backspace, typing, navigation, or keyboard editing shortcuts worked.
- Fix: Keyboard events now cancel selection-menu tracking and are replayed directly to the editor after it regains first-responder status; Escape dismisses without editing.
- Lesson: A selection affordance must remain transient and subordinate to the text editor, including preserving the first editing keystroke that dismisses it.

### 195. Undoable formatting and Markdown source toggle
- Problem: Command-Z did not reverse formatting applied by the selection menu or editor shortcuts, selection/search repaint made the page and caret flash more often, and attachment insertion occupied a primary toolbar slot while Markdown source was inaccessible.
- Fix: Library formatting now records undo/redo snapshots with selection restoration. Selection menus open only for newly changed selections, and search-highlight repaint is debounced and coalesced. The right-click menu gains an icon-backed Insert submenu for tables, links, and attachments, while the former attachment toolbar button toggles between rendered content and editable Markdown source.
- Lesson: Rich-text mutations need to participate explicitly in the editor undo chain, and transient presentation work should be scheduled away from each keystroke; primary toolbar space is better used for switching editing representations than duplicating contextual insertion commands.

### 194. Focused macOS editor context menus and stable editing paint
- Problem: Right-clicking blank space after text on a non-final line could highlight the whole line, the native text menu was crowded with unrelated system commands, selected text lacked direct everyday formatting and paragraph conversion actions, and active-search editing could visibly flash while highlights were removed and reapplied.
- Fix: Added trailing-line whitespace hit testing that preserves the current selection and reduced the right-click menu to Translate, Cut, Copy, and Paste. Mouse selection now opens a separate icon-backed shortcut menu for bold, italic, underline, strikethrough, portable yellow highlight, and conversion to body/headings/lists/checklists. Search-highlight updates run as one text-storage transaction and preserve document highlights.
- Lesson: Rich-editor context menus should distinguish text hits from nearby layout whitespace, while transient presentation attributes must be updated atomically and kept separate from persisted document formatting.

### 193. Immediate iOS deletion and complete rendered Markdown
- Problem: A deleted note remained visible until a complete library rescan finished, long-press Copy in the half/full-screen reader did not show the native selected range, and block Markdown such as checkboxes and code fences was flattened into ordinary text even though gallery cards rendered checklist state correctly.
- Fix: Successful trash operations now remove affected notes from the in-memory list, folder, count, tag, conflict, and search projections before the background filesystem refresh. Both reader detents now share native text highlights, handles, and Copy behavior, plus semantic rendering for headings, checked and unchecked tasks, unordered and ordered lists, quotes, dividers, fenced code, tables, and existing inline styles.
- Lesson: A filesystem-backed app still needs immediate successful-operation projections, and a read-only Markdown surface must preserve block semantics as well as inline attribution.

### 192. Unified black Notes-style app icons
- Problem: The macOS and iPhone apps used different dark note-card icons, so the product identity was inconsistent and did not match the requested Notes-like visual language.
- Fix: Rebuilt both icon families around one original black-header note motif: a near-black top band, warm white paper, and restrained gray rules. The macOS asset keeps platform-appropriate transparent padding and rounding, while the iPhone asset uses a full-bleed composition for the system mask; both remain reproducibly generated at every declared size.
- Lesson: Cross-platform branding should share a recognizable motif while respecting each platform's icon mask and optical scale; source-backed generators keep the small sizes and packaged artifacts aligned.

### 191. Faster iOS shell and native Notes home controls
- Problem: Cold launch held the entire interface behind a progress screen until every Markdown file was indexed, the home timeline did not expose the Notes-style view controls, and its drawer's always-mounted scroll view prevented the system navigation bar from collapsing the large title like Apple Notes.
- Fix: Folder access and pending-write recovery now reveal the home shell before the library actor completes its full scan, App Shortcut metadata refresh is deferred beyond the first visible frame, and the timeline displays an in-place loading state. The closed drawer no longer contributes a competing scroll view, so iOS 26 owns the large-title and note-count transition through `navigationSubtitle` plus the native hard scroll-edge effect. The home also persists card/list mode and uses a system `UIMenu` with selection, sort and group subtitles, date grouping, and the attachment destination.
- Lesson: Perceived launch performance comes from separating safe navigation readiness from expensive indexing, and navigation chrome stays most faithful when the system sees one unambiguous primary scroll view instead of a parallel offscreen scroller.

### 190. Concise iOS delete wording
- Problem: Destructive menus and confirmations described ordinary deletion as "Move to Recently Deleted," exposing storage mechanics instead of the user action.
- Fix: Note, multi-note, folder-note, and conflict-copy actions now use Delete wording throughout menus, confirmations, errors, and success feedback while retaining the recoverable Recently Deleted behavior.
- Lesson: A recoverable delete should be labeled by the user's intent; restoration details belong in the confirmation explanation and Recently Deleted destination.

### 189. Quiet iOS autosave feedback
- Problem: Every background autosave reused the explicit completion state, replacing the editor checkmark with a spinner and cycling the status label through Saving and Saved even though editing continued.
- Fix: Background autosave now keeps the stable checkmark and Saved label while preserving write serialization and failure reporting. Visible progress remains reserved for explicit completion saves, and a recovered failure may still return the status to Saved.
- Lesson: Durable background work should not borrow transient command feedback; autosave needs stable chrome unless the user must act on a failure.

### 188. Fixed reader metadata and opaque card-stream headers
- Problem: The swipe directory exposed an inert pull-to-refresh gesture, folder counts shifted horizontally depending on whether a row had a disclosure control, the reader timestamp scrolled away with the note, and home cards remained visible through the margins above pinned date headers.
- Fix: Removed refresh from the directory/home container, standardized a monospaced count column plus fixed trailing accessory column, moved read-only metadata outside the content scroll view, and extended each pinned time header across the full viewport while making the navigation-bar background opaque.
- Lesson: Persistent metadata and pinned grouping chrome must live outside scrolling/translucent content, and hierarchical rows need stable trailing layout slots regardless of disclosure state.

### 187. Leaner swipe directory with named utility section
- Problem: The directory duplicated its swipe gesture with a top-left sidebar button, exposed the backing folder name as a heading, mixed utility destinations with normal folders, and rebuilt the complete chronological projection throughout an interactive drag.
- Fix: Removed the sidebar button and backing-folder label, added a fixed Folders heading with a compact Settings button, and moved Attachments plus Recently Deleted into a separate Library section. The drawer keeps its backdrop mounted, uses an opaque composited surface with a tighter spring, scopes close gestures to the drawer, lazily builds its vertical content, and caches both the time-sorted home projection and smart-folder counts by library revision instead of rescanning notes on animation frames.
- Lesson: Smooth navigation depends as much on stable view identity and bounded recomputation as on the spring curve; navigation hierarchy and maintenance destinations should also remain visually distinct.

### 186. Scroll-only reader content with selectable read-only text
- Problem: Vertical gestures inside a half-height note could resize the sheet, tapping an expanded note silently entered editing, and the note-wide custom context menu prevented the native text copy menu from appearing.
- Fix: Reader sheets now prioritize content scrolling at both detents, leaving detent changes to the native top drag indicator. Half and full readers remain read-only unless opened through an explicit Edit action. Rendered Markdown enables native text selection and copying, while note-level actions move to the date label's context menu.
- Lesson: Reading, resizing, selection, and editing need separate gesture targets; overloading the content surface makes each interaction unpredictable.

### 185. Independently expandable directory hierarchy
- Problem: The swipe-out directory exposed only top-level folders, and its single row chevron made entering a folder and inspecting its descendants the same action.
- Fix: Folder rows now keep the main row as navigation while reserving the right-side chevron for animated inline expansion and collapse. Expanded descendants render recursively with increasing indentation, counts, lifecycle actions, and the same independent behavior at every depth.
- Lesson: Hierarchical navigation needs two explicit targets: the label enters the selected scope, while the disclosure control changes only the visible tree structure.

### 184. Chronological card home with swipe-out directory
- Problem: Launching into a folder index made note discovery one navigation step slower and treated the directory as the primary surface rather than the notes themselves.
- Fix: iOS now opens directly into a two-column card stream that mixes Markdown files and individual Inbox captures in descending timestamp order without duplicating the aggregate `Inbox.md`. A rightward drag reveals the complete folder directory from the left; the reverse drag or backdrop tap closes it, while the sidebar button provides an explicit equivalent action.
- Lesson: In a note-first mobile library, chronology is the default working surface and hierarchy is progressive navigation that should remain one gesture away.

### 183. Detailed card-style iOS note rows
- Problem: iOS note rows compressed the body preview beside the timestamp into a single line, making it difficult to recognize a note without opening it.
- Fix: List cards now allow two-line titles and show up to three lines of body text. Checklist notes instead expose their first two tasks, while open-task and attachment indicators remain visible in the metadata row. Folder-scoped lists continue to omit their redundant folder name.
- Lesson: A notes list should carry enough document shape to support recognition; time and status are metadata, while the content preview deserves its own vertical space.

### 182. Tap outside a half-sheet note to close it
- Problem: A note opened at the medium reading detent left the upper background visible, but tapping that empty region did nothing.
- Fix: While the reader is at the medium detent, its presentation background is interactive and a dedicated backdrop tap dismisses the note. The backdrop action is disabled once the reader expands or enters editing.
- Lesson: A partially presented reader should treat the exposed backdrop as an explicit, predictable dismissal surface.

### 181. Stable first autosave for new notes
- Problem: Typing the first paragraph of a new note triggered autosave, which immediately renamed `Untitled Note.md` from its content. Because the file path also identified the presented sheet, the rename recreated the editor; subsequent edits then saved from a stale document version and produced a conflict error.
- Fix: Background autosave now writes new-note content in place while preserving both the temporary path and `isNew` state. Filename finalization waits for the explicit editing confirmation, and a path-changing final save no longer replaces the identity of the currently presented sheet.
- Lesson: A document's persistent filename may change, but transient presentation identity must remain stable for the entire editing session.

### 180. New notes save to folders, not existing documents
- Problem: The New Note command opened the quick-capture composer, whose target menu appends content to an existing document. Presenting that menu as the note location made individual Markdown files appear selectable where only a save folder was expected.
- Fix: New Note now creates a standalone Markdown document directly in the current folder and immediately opens its editor. From the library root it creates at the library root; from a folder or folder-scoped note list it uses that folder. The existing quick-capture target behavior remains isolated from document creation.
- Lesson: An append destination and a new-document save location are different concepts and must not share the same entry point or picker.

### 179. Half-sheet reading, direct editing, and recoverable saves
- Problem: Opening a note jumped straight into a full-screen reader that could be edited immediately, list rows had no direct edit action, and choosing to keep a draft after an external-version conflict retained the stale save baseline so later save attempts could never succeed.
- Fix: A normal row tap now presents a medium read-only sheet with a visible drag handle; expanding it to the large detent unlocks tap-to-edit. Long press exposes Edit and opens directly in the large editor. Conflict recovery now preserves the current draft while rebasing its expected version on the latest saved note, allowing the next autosave or confirmation to complete safely.
- Lesson: Read and edit are distinct presentation intents, and conflict recovery must update both the visible draft and the version precondition used by the next write.

### 178. Animated folder editing and unified Notes-style rows
- Problem: Entering folder management replaced Edit with a static Done label, merged Inbox content still exposed two visibly different row designs, and folder note lists used plain list sections while redundantly repeating the current folder beneath every note.
- Fix: Edit now transitions in place to a checkmark with a native blur-replace animation. Markdown files and Inbox quick notes share the same title, timestamp, preview, attachment, and grouped-card row language. Folder and Inbox lists use date-grouped inset cards with Notes-style headers and separators, while folder-scoped rows omit their already-known folder location.
- Lesson: Merging data sources is incomplete until their presentation model is also unified; contextual metadata should disappear when navigation already communicates it.

### 177. One merged Inbox and monochrome folder hierarchy
- Problem: The library still exposed Daily and All Notes as synthetic destinations, while Inbox.md quick notes and Markdown files inside an existing Inbox folder appeared as two separate roots. Filled yellow folder symbols also made the hierarchy feel inconsistent with the quieter Inbox treatment.
- Fix: The home now contains only the merged 000-inbox and real non-Inbox top-level folders. Opening 000-inbox shows both quick notes from Inbox.md and Markdown notes stored anywhere under the top-level Inbox folder without moving either source. Daily and All Notes are removed from the home hierarchy, and folder symbols use monochrome outline variants with neutral black-and-white styling.
- Lesson: A folder-first library should consolidate equivalent sources at the presentation boundary while preserving the files on disk, and hierarchy icons should share one restrained visual language.

### 176. Unified library hierarchy and native glass editing bar
- Problem: The iPhone home split the authorized library's fixed note entries and real top-level folders into separate `mudsbuild` and `Folders` cards, open-note reading still carried a bottom action group, note rows could require tapping directly on their text, and the editor accessory was only a material strip rather than native Liquid Glass.
- Fix: The home now presents `000-inbox`, Daily, All Notes, and every real first-level folder in one library card, with attachments, Recently Deleted, and Settings in a separate utility card. Common folder names receive semantic SF Symbols. Reading mode is fully chrome-free while long press preserves its document actions, list and search rows expose their entire width as a hit target, and iOS 26 renders the keyboard editing controls over a system glass capsule with a material fallback on older systems.
- Lesson: A local-first library should mirror its real root hierarchy in one visual group; utility destinations and transient editing tools need their own clearly separated system surfaces.

### 175. Quiet note chrome and Notes-style editing tools
- Problem: Reader and editor actions crowded the top of an open note, while the editing controls used individually boxed custom buttons that did not match Apple Notes and disappeared when moved into a system bottom bar behind the keyboard.
- Fix: Open notes now keep their top edge free of buttons in both reading and editing states. Reader actions stay in the native glass bottom group, and the editor uses a compact borderless input-accessory row above the keyboard for attachments, audio, formatting, checklists, undo, redo, and save.
- Lesson: Note editing controls belong with the keyboard, while document chrome should stay quiet; system bottom bars are suitable for reading controls but cannot replace a keyboard-visible editing accessory.

### 174. Restore the accepted native Notes command row
- Problem: A later toolbar revision reintroduced a custom search field and voice action, regressing the previously accepted Apple Notes-like bottom silhouette.
- Fix: iOS 26 again uses the system Search toolbar item with a fixed native gap before the independent New Note control, matching the earlier `Adopt native Notes toolbar grouping` implementation; older iOS keeps the existing fallback.
- Lesson: When a visual baseline has already been approved, restore that exact system composition instead of approximating it with another custom glass arrangement.

### 173. Native iOS 26 note navigation and reader controls
- Problem: Folder actions drew their own card shapes inside the system toolbar, note readers opened as half-height sheets without an explicit return action, and reading mode had no bottom command bar.
- Fix: Folder, list, and reader actions now let the iOS toolbar provide native Liquid Glass grouping and press feedback. Readers open at full height with Back, Share, and More controls, plus a working bottom group for checklist, attachments, formatting, and composing a new note.
- Lesson: On iOS 26, toolbar placement should describe control relationships while the system owns their glass shape and interaction response; drawing circles and capsules inside toolbar labels produces nested chrome and weaker navigation cues.

### 172. Stable iPhone input-method composition
- Problem: The rich Markdown editor reapplied attributes and published SwiftUI state for every provisional marked-text change, interrupting Chinese and other composition keyboards while typing.
- Fix: The UIKit editor now leaves marked text under input-method ownership, defers SwiftUI synchronization and Markdown styling until the composition commits, and verifies that autosave keeps the keyboard active for continued editing.
- Lesson: A rich-text bridge must treat marked text as provisional UIKit state; rewriting text storage during composition can terminate the input session even when the visible string looks valid.
### 171. Search-first iPhone widget actions
- Problem: The existing iPhone widget compressed text, audio, and image capture into a small surface even though a small WidgetKit family cannot reliably expose multiple independent tap targets, and it offered no direct path into note search.
- Fix: The small widget is now a focused Quick Note launcher with clearer hierarchy. A separate medium Mudsnote Actions widget adds a full-width Search Notes row above equal Voice input and Quick Note actions. Search uses a new `mudsnote://search` route that survives cold launch and authorized-folder loading, then focuses the native library search field exactly once; capture actions retain the existing durable text/audio routes.
- Lesson: Widget families should match their real interaction capacity: one decisive action in a small widget, multiple explicit links in a medium widget, and deep links that carry intent through app bootstrap instead of stopping at a generic home screen.

### 170. Unified native iPhone note entry and gesture-driven editing
- Problem: New Note and Quick Note exposed competing entry points, the capture commands consumed two visual rows, the library search bar was custom-built, and a checklist gesture prevented normal taps from moving the editor caret. Open notes also duplicated the sheet drag gesture with explicit share and full-screen controls.
- Fix: New Note now opens the durable capture composer and dismisses after submission; the lightning entry is gone. Eight compact capture actions fit one borderless row, library search uses the native bottom toolbar, and the black New Note symbol remains visually primary. Open notes use the native sheet grabber to move between half and full height, omit note-level share/full-screen buttons, default the caret to the end, and reserve the checklist recognizer exclusively for checklist markers so ordinary taps move the caret normally.
- Lesson: A Notes-style iPhone flow is clearest when system containers own search and sheet movement, while custom gestures are narrowly gated so they never compete with native text selection.

### 169. Notes-style folder nesting by drag on iPhone
- Problem: Folder management could create, rename, move, and delete folders, but nesting still required opening a menu; Apple Notes lets users directly drag one folder onto another.
- Fix: Edit mode now exposes a dedicated drag handle beside each real folder. Dragging a handle onto another folder shows a yellow drop highlight, rejects self/descendant cycles, and routes the accepted move through the existing atomic folder lifecycle before refreshing counts and showing confirmation. Normal browsing retains its original navigation, swipe-delete, and long-press menu behavior.
- Lesson: Native drag-and-drop should be scoped to a mode with explicit affordances when the same row already owns navigation and a context menu; this preserves familiar gestures while making hierarchy editing discoverable.

### 168. Notes-style swipe-to-move on iPhone
- Problem: Note rows exposed Delete after a left swipe, but Move remained hidden in the long-press menu, making a common Apple Notes organization flow slower and harder to discover.
- Fix: Added Move beside Delete in the trailing swipe actions and a native half-sheet destination picker that moves the note atomically to the top level or another folder, refreshes the list in place, and preserves the existing pin, rename, batch, and opened-note lifecycle actions.
- Lesson: High-frequency lifecycle actions should be reachable from the list gesture users already know; reusing the existing atomic move operation keeps the new surface consistent without duplicating data logic.

### 167. Notes-style attachment presentation on iPhone
- Problem: Opened iPhone notes always rendered attachments at their largest presentation, consuming most of a half-sheet and offering no Apple Notes-style per-attachment or per-note density control.
- Fix: Added persistent Small, Large, and Plain Link choices to every attachment context menu plus Set All to Small/Large in Note Options. Preferences follow note, folder, and attachment renames/moves, clear on permanent deletion, preserve existing attachment actions, and never rewrite portable Markdown.
- Lesson: Attachment density is view state rather than document content; keeping it in a lifecycle-aware preference store preserves Markdown portability while making half-sheet reading and editing materially faster.

### 166. Main-window Markdown routing and quieter quick capture
- Problem: Finder-opened Markdown files still appeared in the compact quick-entry editor, and quick capture ended with two wide dialog-style text buttons whose accent treatment overwhelmed the lightweight panel.
- Fix: External `.md` and `.markdown` files now open as selected rows in the three-pane library, remain visible across background snapshot refreshes, preserve pending edits in the previously selected note, and save back to their original paths. Quick capture keeps its destination shelf but replaces the wide Cancel/Save pills with compact native `xmark` and `checkmark` actions using transparent idle states and hover feedback.
- Lesson: File opening belongs to the app's primary workspace; fast capture should reserve visual weight for content and reveal completion controls through familiar symbols and interaction state.

### 165. Native Markdown document opening
- Problem: The packaged app did not declare Markdown document support or handle Launch Services open-file events, so Finder could not deliver `.md` files to Mudsnote.
- Fix: Registered `.md` and `.markdown` as editable document types, added cold- and warm-launch AppKit file-event handling, and added native File > Open and Command-S actions. External documents now save in place without title-based renaming or a save-location prompt.
- Lesson: Library-note updates and external-document saves need separate path semantics; title-based filenames are appropriate inside the managed library but unsafe for files opened from Finder.

### 164. Native list and gallery modes
- Problem: The macOS library could only browse notes in the three-pane list, while Apple Notes also provides a wide visual gallery for scanning note previews.
- Fix: Added a persistent native `NSCollectionView` gallery behind View > Show as Gallery (`Command-2`) and Show as List (`Command-1`). Gallery mode collapses the note-list split item, reuses the loaded 240-note projection and thumbnail cache, preserves multi-selection and context actions, opens cards back into the same editor, and returns to list mode for New Note. Hidden gallery state keeps only its lightweight projection and never instantiates preview cells or triggers thumbnail work. The installed app was checked against Apple's official gallery reference and the first compressed-card layout found by real-app QA was corrected.
- Lesson: A native collection view still needs explicit internal width constraints; item-size configuration alone does not prevent stack views from compressing preview content to its intrinsic minimum.

### 163. Guard expanded source-action icon scale
- Problem: A runtime screenshot showed Add Folder and Sidebar Toggle at the generic toolbar-symbol scale even though the source-action constant was already calibrated separately.
- Fix: Added a regression against the images installed on the actual expanded toolbar controls: Add Folder must retain a `20x15pt` configured canvas and Sidebar Toggle an `18x14pt` canvas. Repackaged the current source into `/Applications/Mudsnote.app` so the installed artifact uses the dedicated `13pt` native SF Symbol configuration instead of a stale generic build.
- Lesson: A layout constant does not prove the image that AppKit ultimately installs on a toolbar button; test the configured runtime control and keep the packaged app synchronized with the verified source.

### 162. Correct full-library custom sorting
- Problem: Title and creation-date sorting only reordered the 240 most recently edited notes, so a globally first title, newest creation date, or older pinned note could remain outside the visible result window.
- Fix: Added a bounded-memory, chunked top-K projection over the complete selected scope. Sorting and grouping changes now reproject from the loaded snapshot, preserve date-group and pinned ordering, and retain the fast early-stop path for default edit-date navigation. Native source cells now expose `AXPress`, and the installed-app smoke uses that current semantic while waiting within a fixed window for autosave instead of racing its `800ms` debounce.
- Lesson: A visible-result limit must be applied after the active global ordering, not before it; bounded top-K selection provides correct semantics without materializing or fully sorting all 10,000 records.

### 161. Bounded source-scope projection
- Problem: Inbox, folder, and tag navigation filtered the complete 10,000-note snapshot into a temporary array before keeping only the first 240 visible notes, creating avoidable main-thread scanning and allocation.
- Fix: Added a shared bounded projection that preserves snapshot order, stops as soon as the visible limit is reached, and allocates only the result capacity. A regression proves 240 alternating matches visit 479 of 10,000 inputs instead of all 10,000.
- Lesson: Snapshot-first navigation also needs bounded in-memory work; removing filesystem I/O is not enough if a UI action still materializes every matching record.

### 160. Reference-aligned source row highlights
- Problem: Source-row selection and hover reused the scroll content insets, shifting their rounded surface `4pt` right and shrinking a `32pt` row to a `30pt` highlight even though the icon and label content was already aligned.
- Fix: Added independent `10/10/0pt` highlight insets for `LibrarySourceOutlineRowView`, moving selection and hover left without changing outline indentation, content insets, row content, or scroll geometry.
- Lesson: Scroll content padding and row highlight geometry are separate contracts; sharing constants can compound native outline insets and hide a systematic offset.

### 159. Reference-sized toolbar and source icons
- Problem: After the expanded source actions were corrected, New Note remained slightly undersized, grouped editor symbols were slightly oversized, `Aa` was visibly too small, and source-row symbols were still downscaled by an undersized image slot.
- Fix: Gave New Note its own `13pt` symbol configuration, changed grouped symbols to `13pt`, restored native `Aa` to `17pt`, and enlarged source-row image slots to preserve the existing `15pt` system-symbol canvas while keeping label origins aligned.
- Lesson: AppKit symbol point size, image canvas, image-view bounds, and visible glyph boundary are separate measurements; tune each control family independently from equal-scale rendered evidence.

### 158. Reference-sized source toolbar symbols
- Problem: Expanded Add Folder and Sidebar Toggle used the correct native SF Symbols, but shared the generic `19pt` toolbar configuration and rendered visibly larger than Apple Notes.
- Fix: Added a dedicated `13pt` source-action symbol configuration and applied it consistently during toolbar creation, state refresh, and sidebar visibility transitions without changing button frames or collapsed glass controls.
- Lesson: Native controls still need per-symbol optical sizing; validate the rendered glyph boundary rather than the nominal `NSImage.size` canvas.

### 157. Native account and tag disclosure
- Problem: After the source list moved to `NSOutlineView`, `iCloud` and `Tags` were still flat heading rows, so they lacked Apple Notes' native expandable-parent semantics, system disclosure actions, and hierarchical indentation.
- Fix: Made both headings real outline parents, nested All iCloud, folders, Recently Deleted, and tags beneath them, persisted expand/collapse through AppKit notifications, and kept collapsed groups in the model so row virtualization and snapshots remain stable. Collapsed groups now defer unnecessary folder/tag loading, and source selection is restored when a group reopens.
- Lesson: Native controls only deliver their full behavioral and accessibility value when the data model uses their real hierarchy; visually grouping flat rows preserves avoidable custom state machinery.

### 156. Native source outline navigation
- Problem: The source sidebar visually approximated Apple Notes but still rebuilt a custom stack of buttons, so disclosure, keyboard traversal, scrolling, row reuse, inline editing, and accessibility behavior had to be maintained independently from AppKit.
- Fix: Replaced the custom source-button stack with a native `NSOutlineView` source list, preserving Mudsnote's folder/tag/trash scopes while moving hierarchy disclosure, keyboard navigation, field-editor-backed rename/create, row reuse, context menus, and drag/drop onto public AppKit primitives. Folder lifecycle projections remain snapshot-first and deferred scans stay off the main actor.
- Lesson: Apple Notes' private implementation is unavailable, but matching its public AppKit architecture removes custom interaction code and improves large-library behavior more reliably than pixel-only styling.

### 155. State-matched collapsed Notes geometry
- Problem: Collapsed visual QA still compared against an expanded Notes screenshot, hiding that the note list was about `20pt` too wide, the sidebar toggle was oversized, the library title sat too far right, and the titlebar bottom edge was missing.
- Fix: Added the supplied collapsed Notes reference and same-region capture path, tightened the default/minimum note column from `220pt` to `200pt` with a versioned migration, added native pane separators, switched the collapsed toggle to a fixed `30pt` macOS 26 glass circle, and reclaimed `24pt` of reserved toolbar space for the collapsed title while preserving expanded geometry.
- Lesson: Responsive shell states need their own point-scale references; an expanded full-window comparison cannot validate collapsed toolbar ownership or pane boundaries.

### 154. Snapshot-first library navigation
- Problem: When the library snapshot was still empty, source navigation and several post-mutation refreshes could synchronously enumerate up to 10,000 Markdown files on the main thread, making ordinary browsing vulnerable to large-library stalls.
- Fix: Made UI reloads consume only an explicit or in-memory snapshot and schedule cancellable background validation for disk reconciliation. Save, move, trash, restore, folder rename, and folder deletion now update snapshot paths, metadata, and thumbnail references immediately so lifecycle actions remain consistent without rescanning.
- Lesson: A cache-first navigation path is only truly nonblocking when every mutation maintains that cache atomically; a hidden empty-cache fallback can reintroduce the entire filesystem cost.

### 153. Scan-free drag targeting
- Problem: The first drag-to-folder hit test synchronously indexed up to 10,000 Markdown files on the main thread to build a movable-path cache, so a pointer interaction could stall on a large library.
- Fix: Replaced the scan and its invalidation machinery with constant-size configured-root containment checks while retaining extension, existence, same-folder, trash, external-file, and attachment-directory guards.
- Lesson: Drag validation belongs on cheap path metadata already in memory; interaction hit testing must never trigger a library-wide index pass.

### 152. Notes-like group breathing room
- Problem: Group titles aligned with Apple Notes, but their first note began about `6pt` too close to the heading, making `Today` and recency sections look compressed.
- Fix: Increased group rows from `48pt` to `54pt` while increasing the title bottom inset from `6pt` to `12pt`, preserving the title baseline and assigning all added space below it.
- Lesson: Section rhythm should move content independently from labels; paired height/inset changes make that intent measurable and regression-testable.

### 151. Reference-aligned editor origin
- Problem: After correcting reference backing scale and pane proportions, the editor date still began about `6pt` above Apple Notes and the title remained another `3–4pt` too close to it.
- Fix: Moved the safe-area editor origin from `12pt` to `18pt` and refined date-to-title spacing from `30pt` to `34pt` using the state-matched content comparison.
- Lesson: Editor rhythm should be calibrated as two independent measurements: the pane's safe-area origin and the spacing between semantic rows.

### 150. Compact Notes pane proportions
- Problem: Corrected point-scale comparisons showed the default source and note-list panes were still `250/250pt`, visibly wider than Apple Notes' roughly `212/200pt` columns and especially oversized after source collapse.
- Fix: Tightened both defaults to a conservative `220/220pt`, resized their internal row/table geometry, and added a versioned migration that replaces only untouched `250pt` defaults while preserving manually resized panes.
- Lesson: Reference-scale shell fidelity depends on pane proportions, but layout migrations must distinguish obsolete defaults from deliberate user geometry.

### 149. State-accurate toolbar geometry
- Problem: The empty-state Apple Notes reference lost its Retina DPI metadata, so visual QA rendered it at half scale; the New Note button also remained on the list side of the tracked editor divider, widening and crowding both expanded and collapsed headers.
- Fix: Added explicit `2x` metrics for the checked-in Retina references, deterministic expanded/collapsed fixture state, and moved New Note across the tracked divider into the editor-side toolbar region.
- Lesson: Window chrome must be compared in points from trustworthy backing-scale metadata, and toolbar ownership is defined by split-view separators rather than item proximity alone.

### 148. State-matched editor visual QA
- Problem: The content fixture silently compared against the empty Apple Notes reference, making the editor title rhythm appear tighter than the actual content state.
- Fix: Routed empty and content fixtures to their matching checked-in references and restored the content date-to-title spacing to `30pt` based on the true content comparison.
- Lesson: Visual geometry changes require state-matched references; an empty-state screenshot cannot validate content rhythm.

### 147. Unoccluded first note row
- Problem: Selecting the first note let the floating recency header cover its title and preview, making an empty note appear as a gold row containing only its folder; disabling the float then exposed that the list itself entered the full-size titlebar.
- Fix: Disabled floating table group rows and anchored the note-list stack to its pane safe area, preserving the toolbar title/count while keeping `Today` and the complete first note row below it.
- Lesson: Full-size titlebars require explicit safe-area boundaries in every pane, and floating table groups are unsafe when selection-driven scrolling can place content beneath them.

### 146. Immediate native toolbar menus
- Problem: Toolbar menus were anchored correctly but still waited for a normal button mouse-up, unlike the immediate menu-tracking rhythm in Apple Notes.
- Fix: Added a dedicated menu-trigger button that highlights on mouse-down, enters menu tracking immediately, and clears highlight only after the menu closes; applied it only to list options and `Aa`.
- Lesson: Menu fidelity is behavioral, not only positional; command buttons and menu triggers should remain distinct control types even when their icons share the same toolbar surface.

### 145. Quiet saves and native sidebar collapse
- Problem: Autosave replaced the editor date with transient save copy, sidebar collapse snapped without matching the Notes collapsed toolbar, the right-side share/more group was unnecessary, and toolbar menus used inconsistent fallback anchors.
- Fix: Kept the displayed date stable while editing and refreshed it from the saved file timestamp, added a native 0.22s sidebar collapse with state-specific toolbar controls, removed the share/more group, unified toolbar menu anchoring, darkened the rounded sidebar material, and routed visual QA to a physical external display when available.
- Lesson: A Notes-like shell depends as much on state transitions and quiet feedback as static geometry; toolbar composition should change with pane visibility instead of merely hiding pane content.

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

### 156. Quiet save timestamps and native collapse/menu behavior

- Problem: Draft saves reused the editor status area for transient save messages, the sidebar chrome changed outside the collapse transaction, the unused list ellipsis remained visible, and menu buttons opened during mouse-down with a left-biased anchor.
- Fix: Kept save progress out of editor status text while retaining post-save file timestamps in the library, synchronized sidebar chrome and title movement with the native split collapse animation, removed the ellipsis from the default toolbar, and restored normal AppKit click-release menu activation with a centered lower-edge anchor.
- Lesson: Persistence feedback should not displace document metadata, and titlebar state changes need to participate in the same animation and event lifecycle as the pane they represent.

### 157. Background Recently Deleted snapshots

- Problem: Opening Recently Deleted parsed trashed Markdown synchronously, and source-count refreshes separately walked the trash directory on the main thread.
- Fix: Added a bounded in-memory trash snapshot, hydrated and validated it alongside the normal library snapshot off the main actor, and updated it atomically during trash, restore, and permanent-delete commands.
- Lesson: Every navigation scope must obey the same snapshot-first contract; a single exceptional filesystem-backed scope can still make the whole sidebar feel blocked.

### 158. Snapshot-first trash keyboard search

- Problem: Typing in Recently Deleted searched asynchronously, but keyboard commands that flushed the debounce could synchronously reopen and parse every trashed Markdown file.
- Fix: Keyboard flushes now filter the in-memory trash snapshot immediately by title, preview, and tags, then launch the existing detached full-text search to replace that provisional result.
- Lesson: A debounced background search still needs a nonblocking flush path; keyboard immediacy and complete eventual results are separate phases.

### 159. Snapshot-first initial keyboard search

- Problem: Pressing Return or an arrow key before the first search debounce completed could synchronously create and validate the full search session on the main thread.
- Fix: When no reusable search session exists, keyboard flushes now filter the loaded scope snapshot immediately and schedule detached indexed search; established sessions continue using their complete in-memory ranking synchronously.
- Lesson: The first interaction needs a cache-backed fast path even when steady-state search is already optimized.

### 160. Native View-menu list options

- Problem: Removing the unnecessary toolbar ellipsis also removed the only visible route to note sorting and date grouping, leaving tested commands unreachable to users.
- Fix: Added Sort By and Group By Date to the native View menu, routed them through the active library controller, and used AppKit menu validation to keep checkmarks synchronized with persisted or live window state.
- Lesson: Removing chrome must not orphan useful commands; macOS menus are the correct low-noise home for secondary list presentation options.
- Follow-up: Folder deletion now remaps every contained note into the trash snapshot immediately, preserving Recently Deleted counts under the snapshot-first architecture.

### 161. Reference-scale default library window

- Problem: The default `1080x720pt` workspace remained materially larger than the supplied Apple Notes reference at roughly `931x623pt`, matching the reported oversized-window regression.
- Fix: Tightened the default library window to `940x630pt` and the safe minimum to `904x560pt`, retained the `220/200pt` source/list proportions, and migrated only frames that exactly matched either previous default while preserving their center.
- Lesson: Matching control metrics inside an oversized shell is not enough; default window geometry is a first-order fidelity signal, but migration must not overwrite intentional user resizing.

### 162. Immediate list metadata after autosave

- Problem: Successful autosave refreshed the editor timestamp and source snapshot, but the visible note row kept its old title, preview, and date until another navigation or filesystem refresh.
- Fix: After save, project the current scope directly from the updated in-memory snapshot, rebuild sorting/grouping while preserving selection, refresh counts, and use detached search refresh when a query is active.
- Lesson: Snapshot correctness must reach every visible projection immediately; persisting data without updating the list makes autosave appear unreliable even when the file is correct.

### 163. Background source-count aggregation after save

- Problem: Immediate list projection after autosave also rebuilt folder, tag, and Inbox counts for up to 10,000 notes on the main actor.
- Fix: Kept note rows immediate, moved source-count index aggregation to a cancellable utility task, and published counts only when its generation and folder-path snapshot still match the current window.
- Lesson: A fast visible projection can still hide an expensive secondary projection; list metadata and aggregate navigation counts need separate scheduling budgets.

### 164. Single native sidebar edge

- Problem: The rounded source sidebar drew its own `1pt` outline on top of the native sidebar item's boundary, leaving doubled traces along the top and left edges.
- Fix: Removed the custom layer border while retaining the `24pt` clipping radius, darkened sidebar material, and AppKit-owned pane separation.
- Lesson: A native full-height sidebar should have one edge owner; custom material may shape and tint the surface without redrawing AppKit's structural boundary.

### 165. Notes-matched list insets

- Problem: In the collapsed state, note-group titles and row text began too far left while the selected background used a looser leading edge than Apple Notes, making the `200pt` list pane feel visually off-center.
- Fix: Matched the state-specific reference with a `20pt` group-title inset, `15pt` selected-row leading inset, `40pt` note-content baseline, and quieter bounded separators while preserving the established pane width and scrollbar clearance.
- Lesson: Once shell proportions are stable, list fidelity depends on independently measuring headings, selection shapes, text baselines, and separators rather than shifting the entire table as one block.

### 166. Shared editor reading edge

- Problem: The editor title and body appeared several points farther from the pane divider than Apple Notes because the `24pt` outer inset and the text view's additional `4pt` container inset accumulated only for body text.
- Fix: Tightened the shared editor inset to `22pt` and the body text-container inset to `2pt`, placing the title near `23pt` and body near `24pt` while preserving the previously calibrated vertical rhythm and full-width date centering.
- Lesson: Rich editor alignment must account for both view geometry and TextKit padding; matching only the outer stack leaves title and body on visibly different reading edges.

### 167. Reference-width source sidebar

- Problem: The expanded source sidebar remained `220pt` wide while the Apple Notes reference measured about `212pt`, leaving the entire left region and its selected rows visibly oversized.
- Fix: Tightened the default/minimum source pane to `212pt`, its inset rows to `184pt`, and the consistent minimum window width to `896pt`. Added a version-6 migration that replaces only exact stored `220/200pt` pane defaults while preserving custom widths.
- Lesson: Pane fidelity needs both a measured default and a conservative migration; changing constants without migrating untouched persisted geometry leaves existing users on the obsolete layout.

### 168. Reference-height editor title

- Problem: The editor title still sat visibly too low because the date row retained `34pt` of additional spacing, a value derived from a privacy-blurred comparison that obscured the actual title edge.
- Fix: Used the supplied clear Apple Notes crop to reduce date-to-title spacing to `8pt`, moving title and body up `26pt` while leaving the centered date and toolbar unchanged. The resulting title top is within roughly `3pt` of the clear reference.
- Lesson: Blurred content can validate broad structure but not text baselines; visible typography must be calibrated from an unblurred state-matched reference.

### 169. Compact source-list rhythm

- Problem: Source rows remained `36pt` high with `1pt` inner and `6pt` cross-stack spacing, producing `37–42pt` center distances while Apple Notes uses roughly `32–33pt`.
- Fix: Reduced source rows to `32pt`, removed incidental inner/cross-stack gaps, and retained only deliberate `4pt` spacing after the iCloud heading plus `6pt` before Tags. Added a root-stack identity and tests for the exact spacing contract.
- Lesson: Sidebar density should come from a zero-gap row rhythm with explicit semantic group breaks, not uniform stack spacing that silently compounds across nested stacks.

### 170. Reference-height note groups

- Problem: Date-group rows still occupied `54pt`, placing group headings about `12pt` and the first note card about `9pt` below their Apple Notes positions in both expanded and collapsed states.
- Fix: Reduced group rows to `45pt` and increased the title bottom inset to `15pt`, independently aligning the heading baseline and following card while preserving their breathing room.
- Lesson: A section header's row height controls following content while its internal bottom inset controls the label; both must be measured separately to align the complete list rhythm.

### 171. Notes-ordered toolbar spacing

- Problem: A flexible spacer sat directly after New Note, pushing the editor tools toward Search and leaving roughly twice the Apple Notes gap between the primary action and formatting group.
- Fix: Reordered the native toolbar to New Note, fixed space, editor tools, flexible space, then Search. Added an exact default-order regression contract while keeping share and ellipsis controls absent.
- Lesson: Toolbar spacing semantics matter as much as item dimensions; fixed space expresses local grouping, while flexible space belongs between command clusters that should occupy opposite sides.

### 172. Reference-width toolbar search

- Problem: The toolbar search field occupied `210pt` inside a `230pt` wrapper, roughly `50–70pt` wider than the Apple Notes reference and needlessly compressing the toolbar's central breathing room.
- Fix: Reduced the native search field to `160pt` and its wrapper to `180pt` while preserving the `32/36pt` field/wrapper heights, search behavior, focus handling, and responsive toolbar layout.
- Lesson: Search prominence should come from placement and native affordance rather than excess width; horizontal and vertical control metrics need independent tuning.

### 173. Higher editor content origin

- Problem: The editor title still read lower than the supplied clear Apple Notes reference even after the date-to-title gap was corrected.
- Fix: Reduced the editor stack's safe-area top inset from `18pt` to `12pt`, moving the date, title, and body upward together while preserving their calibrated internal spacing and reading edge.
- Lesson: Once internal title rhythm is correct, vertical alignment should be adjusted at the shared content origin so date, title, body, and caret remain coherent.

### 174. Reference-aligned source toolbar

- Problem: In the expanded library, Add Folder and Sidebar Toggle sat roughly `11–15pt` left of their Apple Notes positions; adding a separate spacer item caused toolbar overflow.
- Fix: Replaced the native Add Folder item body with a `68pt` wrapper whose `30pt` button is trailing-aligned, shifting both source controls into the measured reference positions without adding another toolbar item. Tightened the five-button editor-tools group from `184pt` to `155pt` with `31pt` button tracks, matching the reference and preserving toolbar capacity.
- Lesson: Pane-local alignment should be expressed inside an existing toolbar item when possible; adding invisible toolbar items changes overflow behavior even when their apparent width is reclaimed elsewhere.

### 175. Reference-aligned collapsed toolbar

- Problem: In the collapsed library reference, Sidebar Toggle remained about `4pt` left of Apple Notes and the list title about `2.5pt` left, despite the expanded toolbar being aligned.
- Fix: Kept the expanded toggle unchanged, wrapped only the collapsed `30pt` glass control in a trailing-aligned `34pt` item, and calibrated the existing collapsed list-title offset to `-58pt`. The compact comparison now places both controls within roughly `2–2.5pt` of the reference.
- Lesson: Expanded and collapsed toolbar states have different AppKit item geometry; small state-specific wrappers are safer than changing shared item widths or introducing zero-width spacers.

### 176. Rendered-width source sidebar

- Problem: The logical `212pt` source-column default rendered roughly `10pt` wider than Apple Notes once AppKit's native sidebar geometry was included, and its `184pt` rows remained about `4pt` wider than the reference.
- Fix: Set the logical source default/minimum to `205pt`, source rows to `180pt`, and the trailing source inset to `11pt`. Added layout-scale migration version 7, which replaces only exact stored `212/200pt` defaults while preserving custom pane widths.
- Lesson: Native sidebar fidelity must be measured from the rendered divider rather than assuming the split-item width constant equals the visible outer width.

### 177. Stable editor title rhythm

- Problem: The editor title could render too far below the date because the vertical stack's default gravity-area distribution was free to place surplus height between arranged views.
- Fix: Set the editor stack distribution explicitly to `.fill`, keeping the date and title at their measured `20pt + 8pt` rhythm while the body container absorbs remaining height.
- Lesson: Notes-like top alignment needs an explicit stack distribution; spacing constants alone do not prevent AppKit from reallocating flexible space.

### 178. Immediate source snapshot validation

- Problem: Source navigation painted its cached snapshot immediately but imposed an additional fixed `80ms` wait before validating the filesystem. Under concurrent I/O this amplified tail latency and made the background-refresh regression intermittently exceed its deadline.
- Fix: Replace the fixed delay with one cooperative `Task.yield()`. Existing cancellation and generation guards still coalesce obsolete validations, while the current validation starts as soon as the executor can schedule it.
- Lesson: Generation-based cancellation is the correct coalescing boundary here; a fixed debounce adds latency without improving correctness.

### 179. Notes-library accessibility semantics

- Problem: Toolbar icons had accessibility labels, but the three-pane workspace did not consistently name its source pane, note list, search scope, title, body, and modification date. Source counts were also exposed as separate text elements, producing repetitive VoiceOver navigation.
- Fix: Added stable accessibility labels to the core library controls, merged each source count into its source button's accessibility value, and removed the duplicate visual count label from the accessibility tree.
- Lesson: A native-feeling Notes clone needs a concise semantic hierarchy as well as matching pixels; decorative metadata should not become separate navigation stops when it belongs to an actionable row.

### 180. Stateful folder disclosure names

- Problem: Folder disclosure arrows exposed only the generic description "展开或折叠文件夹", so VoiceOver users could not tell which folder or action an arrow represented.
- Fix: Each disclosure button now names its concrete folder and current action, for example "展开 Projects" or "折叠 Projects"; rebuilt rows naturally refresh the name with disclosure state.
- Lesson: Hierarchy controls need object-specific, stateful actions rather than generic icon descriptions.

### 181. Installed Notes-library smoke harness

- Problem: The roadmap required installed-app workflow evidence, but macOS verification relied on unit tests, packaging, and visual capture; there was no repeatable isolated smoke for the real Notes window.
- Fix: Added `scripts/library_smoke.sh`. It launches `/Applications/Mudsnote.app` with an isolated temporary store, creates a note through `Command-N`, edits title/body through Accessibility values, verifies exact autosaved Markdown, and confirms toolbar search filters an unrelated fixture note.
- Lesson: Installed UI smoke must avoid the active input method and user data. `AXValue` provides deterministic text entry under Chinese input methods, while isolated store arguments keep the real library untouched.

### 182. Native delete and restore menu workflow

- Problem: Delete and restore worked through row/context actions, but the main File menu did not expose those core note lifecycle commands, and the installed-app smoke stopped before trash behavior.
- Fix: Added context-validated "移到最近删除" and "恢复笔记" File-menu commands without adding toolbar chrome. Extended `library_smoke.sh` to select the search result, delete it through the installed app menu, verify the isolated Trash file, enter Recently Deleted, restore through the menu, and verify the original path returns.
- Lesson: Core lifecycle commands belong in the native menu as well as context menus; they improve keyboard/menu discoverability and provide a stable end-to-end verification path.

### 183. Native move-to-folder menu workflow

- Problem: Moving notes was available through contextual actions, but the main File menu lacked the command and the installed-app smoke did not prove the move lifecycle.
- Fix: Added a state-validated "移到文件夹" File submenu that dynamically reuses the library controller's current folder targets. Extended `library_smoke.sh` to move the restored smoke note into an isolated folder and verify the exact filesystem transition.
- Lesson: Dynamic native menus should reuse the same target objects and handlers as contextual actions so availability, hierarchy, and behavior cannot drift between entry points.

### 184. Higher editor content baseline

- Problem: The clear Apple Notes crop still placed the editor title slightly higher than Mudsnote after the earlier safe-area adjustment.
- Fix: Reduced the editor stack's safe-area top inset from `12pt` to `6pt`, moving the date, title, and body upward together while preserving the calibrated date-to-title and title-to-body spacing.
- Lesson: Once internal editor rhythm is stable, residual vertical mismatch should be corrected at the shared content origin rather than by distorting the spacing between text elements.

### 185. Installed attachment lifecycle smoke

- Problem: Attachment insertion and rendering had strong unit coverage, but the packaged-app smoke did not prove that a real Finder file could pass through paste, local storage, Markdown serialization, UI rendering, and app relaunch.
- Fix: Extended `library_smoke.sh` to paste a PDF into the moved smoke note, verify the copied `Attachments/yyyy/mm` file and portable relative Markdown link, assert the rendered editor object and note-list attachment indicator through Accessibility, relaunch `/Applications/Mudsnote.app`, and assert the saved attachment renders again.
- Lesson: Installed attachment evidence must cover both durable filesystem state and observable native UI state; either side alone can miss a broken serialization or rendering boundary.

### 186. Snapshot-backed folder disclosure and collapsed-toolbar repair

- Problem: Expanding or collapsing a source folder synchronously rebuilt the hierarchy with recursive `contentsOfDirectory` calls on the main thread. The required collapsed-state visual check also exposed the note-list title overlapping the sidebar button because the old `-58pt` offset no longer matched the current toolbar geometry.
- Fix: Split the folder hierarchy into a complete background-loaded tree snapshot and an in-memory visible-row projection, so disclosure changes no longer touch the filesystem. Added a regression test that proves disclosure uses the loaded snapshot until an explicit refresh. Recalibrated the collapsed title offset to `-7pt` and added a geometric non-overlap assertion.
- Lesson: Navigation disclosure should be a pure projection of loaded state, and compact-toolbar alignment needs intersection assertions in addition to fixed-value checks and screenshots.

### 187. State-matched compact typography and higher editor title

- Problem: Collapsed QA selected a different note/date grouping from the Apple Notes reference, so typography evidence was not trustworthy. The compact title and group labels remained oversized, list previews could clip without an ellipsis, and the editor title still sat slightly low relative to its date.
- Fix: Added a deterministic collapsed-reference fixture, tightened the collapsed title offset and compact header/group typography, preserved tail truncation in highlighted attributed strings, and reduced date-to-title spacing from `8pt` to `4pt` without moving the date row.
- Lesson: Visual parity needs deterministic content state as well as matching window geometry; semantic row spacing should be adjusted independently when only one element needs to move.

### 188. Reference-scaled source typography

- Problem: Source-list labels, section headings, and folder symbols remained visibly larger and heavier than Apple Notes even though the pane width and `32pt` row rhythm were already aligned.
- Fix: Used Vision OCR on equal-scale screenshots to measure the mismatch, then reduced source labels to `13.5pt` regular, section headings to `12pt`, and symbols to `15pt` while preserving row geometry and counts.
- Lesson: Typography should be calibrated independently from container geometry; equal row heights can still look oversized when text width and weight are off by more than ten percent.

### 189. Scroll-safe hover and bounded note cards

- Problem: Scrolling under a stationary pointer could leave every traversed note row painted with the hover background, and long selected-note titles could draw beyond the gold card's right edge.
- Fix: Made the table own one weak hovered-row reference, reconcile it from the current pointer and visible table rect on every clip-view scroll, and clear the prior row before activating another. Reduced text compression resistance and reserved a tested `10pt` text inset inside the selected-card trailing edge so long titles and previews truncate in bounds.
- Lesson: Tracking-area enter/exit events are not a sufficient state model during scrolling; reusable rows need table-owned pointer reconciliation, and text geometry must be constrained against the visible selection surface rather than only the cell edge.

### 190. Nonblocking cached-note validation

- Problem: Returning to an already cached note still synchronously read its filesystem modification date on the main thread before painting the editor. Slow or contended storage could therefore stall keyboard navigation even though the note content and rendered body were already in memory.
- Fix: Cache hits now paint immediately, then validate the file modification date and reload stale Markdown in a detached utility task. Selection generation, selected-path, cancellation, and dirty-editor guards prevent delayed validation from overwriting a newer note or unsaved edits.
- Lesson: A memory-cache hit is only interaction-safe when every freshness check on that path is asynchronous; stale-result protection must cover validation and reload as one operation.

### 191. Reference-aligned note-card width

- Problem: Equal-scale expanded and collapsed comparisons showed that unthumbnailed note rows kept their text stack near intrinsic width instead of filling the card. Dates, previews, and folder names therefore truncated despite available space, while the selected card began about `5pt` too far right and extended too close to the scrollbar.
- Fix: Made the horizontal row stack use fill distribution with a low-hugging text column, then aligned the selected surface to `10pt` leading and `31pt` trailing insets. Shifted note text and separators `5pt` left and retained a measured `10pt` text-to-selection trailing gap after AppKit stack adjustment. Added a real-layout width and clipping regression.
- Lesson: Compression resistance prevents overflow, but it does not make a short intrinsic-width stack consume free space; Notes parity needs both expansion policy and independently measured card/text boundaries.

### 192. State-matched editor content origin

- Problem: The deterministic collapsed fixture showed the same `感悟` title about `25px` high and `12px` left of Apple Notes at `2x`, despite older clear-crop calibrations suggesting the shared editor origin was already aligned.
- Fix: Re-measured the current installed app against the state-matched `304x292pt` reference, then moved the editor stack top inset from `6pt` to `18pt` and its horizontal inset from `22pt` to `28pt`. The resulting title bounds are `x=459–546, y=196–238px` versus Apple Notes' `x=459–543, y=197–238px`, while the internal date/title/body spacing remains unchanged.
- Lesson: Shared editor origin changes must be driven by current, deterministic state-matched captures; older crops with different window state can accumulate apparently reasonable adjustments into a visible overcorrection.

### 193. Pixel-matched list section rhythm

- Problem: Direct inspection of the original `2x` collapsed captures showed that the previous scaled montage misrepresented list geometry: the selected card was actually `5pt` too far left, its top edge extended `2pt` too high, and later group titles sat about `13pt` too high inside otherwise correctly sized rows. The three metadata lines were also vertically compressed.
- Fix: Measured original pixels instead of the presentation montage, restored the `15pt` card and `40pt` text starts, set the trailing card inset to `22pt`, and used asymmetric `6/4pt` top/bottom selection insets. Later group labels now use a `2pt` bottom inset while the first remains `15pt`; note metadata uses `2.5pt` row spacing with `4.5/7.5pt` content insets. Apple Notes and Mudsnote now share the exact selected-card bounds `30,214–355,349px` at `2x`, and the later group title begins at the same `y=418px`.
- Lesson: Measure geometry in the original backing-scale images, not a rescaled comparison canvas. First and subsequent section headings can require different placement even when their row heights are identical.

### 194. Reference-content-normalized Notes geometry

- Problem: The checked-in Apple Notes references contained a uniform `5pt` black screenshot margin, while Mudsnote captures contained only window content. Comparing those different origins produced systematic `5pt` offsets and left long list titles too close to the selected card's right edge.
- Fix: Normalize built-in references before comparison and record the crop metadata. Adopt the resulting `921x613pt` canonical window, `200/200pt` source/list widths, corrected collapsed list/editor origins, bounded note text geometry, and tighter toolbar wrappers. Layout migration version 8 updates exact previous defaults while preserving customized frames and pane widths.
- Verification: Full `swift test`, installed-app smoke, code-signature validation, and expanded, collapsed, and content-state visual comparisons passed. The normalized expanded dividers align at `x=416/816px` and the collapsed selected card aligns at `20,204–345,339px` at `2x`.
- Lesson: Compare window content to window content. Capture margins must be normalized before any pixel-derived layout constant is accepted.

### 195. Reference-aligned collapsed toolbar title

- Problem: After reference-margin normalization, the collapsed `All iCloud` title remained about `10px` left of Apple Notes at `2x`, making the gap from the sidebar button visibly too tight even though the rest of the collapsed layout was aligned.
- Fix: Changed only the collapsed title leading offset from `-16pt` to `-11.5pt`; expanded geometry remains unchanged. The `-11pt` and `-12pt` probes landed `2.2px` right and `1.7px` left of the reference, so the final constraint uses the Retina half-point between them.
- Verification: Vision OCR measured the pre-fix title origins at `x=309.7px` for Apple Notes and `x=300.0px` for Mudsnote; the final `-11.5pt` capture measures `x=309.9px`, a `0.2px` difference. The full Swift test suite, installed-app smoke, code-signature check, and toolbar-state regression passed.
- Lesson: Normalize the reference first, then remeasure each independent toolbar relationship; a global origin correction does not imply every local constraint should move by the same amount.

### 196. Reference-aligned expanded toolbar title

- Problem: The expanded top `All iCloud` title started `24.1px` left of Apple Notes at `2x`, even though the list's `Today` heading and pane divider already matched. Reusing a zero leading offset in the expanded state made the toolbar title visibly detach from the list's native header relationship.
- Fix: Added an independent `12pt` expanded title offset while retaining the measured `-11.5pt` collapsed offset. The visibility transition now restores the correct state-specific value instead of returning to zero.
- Verification: Normalized pre-fix OCR measured `x=455.0px` for Apple Notes and `x=430.9px` for Mudsnote; final expanded Mudsnote measures `x=454.9px`. The collapsed regression remains `x=309.9px` versus `x=309.7px`. The state-transition regression, full tests, installed smoke, packaging, and signature verification passed.
- Lesson: A toolbar item can occupy different AppKit tracks as neighboring items appear or disappear; expanded and collapsed title origins must be calibrated and restored independently.

### 197. Reference-aligned editor date baseline

- Problem: The centered editor date began `13.5px` below Apple Notes in both normalized empty and content captures, while the collapsed editor title was already within `2px` vertically. Moving the whole editor stack would have regressed the title and body.
- Fix: Reduced the editor top inset from `13pt` to `6.25pt` and increased date-to-title spacing from `4pt` to `10.75pt`. Their invariant `17pt` sum moves only the date row upward by `6.75pt` while preserving the title/body origin.
- Verification: Final empty and content OCR both measure the Mudsnote date at `y=123.0px`, exactly matching Apple Notes. The collapsed editor title remains `y=184px` versus `y=186px`. Full tests, installed smoke, packaging, and signature validation passed.
- Lesson: When one row in a vertical stack is misaligned but downstream content is correct, preserve the cumulative downstream offset and redistribute spacing before moving the entire stack.

### 198. Reference-aligned editor date center

- Problem: With the date baseline fixed, Apple Notes centered the date near `x=1311.9px` in both normalized empty and content references, while Mudsnote remained around `x=1328–1329px` because it centered over the entire editor pane.
- Fix: Added an independent `-8.5pt` horizontal center offset to the date label, matching the visible editor region without moving title/body content or changing pane geometry.
- Verification: Final empty-state OCR centers Apple Notes and Mudsnote at `x=1311.9px`; content-state Mudsnote centers at `x=1310.6px`, within `1.3px` of the `x=1311.9px` reference. The `y=123px` baseline and collapsed title remain unchanged. Full tests, installed smoke, packaging, and signature validation passed.
- Lesson: Perceived centering in a scrollable editor may use the unobstructed content region rather than the full pane bounds; calibrate the status row independently when the content origin is already correct.

### 199. Native toolbar interaction feedback

- Problem: The compact toolbar matched the Notes silhouette at rest, but borderless buttons inside static glass did not expose macOS hover or pressed feedback; replacing the group with a stock toolbar item group made every segment about `44pt` and visibly oversized.
- Fix: Kept the measured `155x32pt` native `NSGlassEffectView` group and five `31pt` tracks, changed its command buttons to AppKit `.toolbar` buttons with `showsBorderOnlyWhileMouseInside`, and changed New Note plus the collapsed sidebar control to native macOS 26 `.glass` buttons. Expanded Add Folder and Sidebar Toggle now use the same system hover-only toolbar treatment.
- Verification: Full tests, installed-app library smoke, packaging, and signature validation passed. The packaged content-state comparison is `/tmp/mudsnote-visual-qa-199-native-hover/apple-notes-vs-mudsnote.png`; real pointer captures `/tmp/mudsnote-native-button-hover.png` and `/tmp/mudsnote-native-button-rest.png` differ, proving the native hover state is rendered while the resting group remains compact.
- Lesson: AppKit's fully automatic toolbar group prioritizes standard hit targets over reference geometry. Composing public `NSGlassEffectView` and `NSButton` controls preserves native animation while allowing a reference-sized command group.

### 200. Reference-aligned compact glass buttons

- Problem: The editor command cluster began too close to the editor divider, and the compact `.glass` buttons rendered their SF Symbols at roughly half the Apple Notes reference size because AppKit reduced the standard symbol canvas inside the `30pt` bezel.
- Fix: Added a `44pt` layout slot that keeps the native New Note button `30pt` wide while moving its center to the reference offset, then gave compact glass controls a dedicated `12pt` SF Symbol configuration with unscaled native drawing. The expanded toolbar, search field, pane dividers, and expanded sidebar controls remain unchanged.
- Verification: Expanded and collapsed packaged-app comparisons are `/tmp/mudsnote-visual-qa-200-final-expanded/apple-notes-vs-mudsnote.png` and `/tmp/mudsnote-visual-qa-200-final-collapsed/apple-notes-vs-mudsnote.png`. Full tests, installed-app library smoke, packaging, and strict signature validation passed.
- Lesson: A system symbol's configured point size is not its final `NSImage.size`; compact native bezels need a symbol configuration based on the resulting image canvas, not the nominal point value alone.

### 201. Reference-aligned editor tool capsule

- Problem: The editor-tools capsule began about `7pt` left of the normalized Notes reference, its generic `19pt` SF Symbols crowded the five compact tracks, `Aa` was rendered into a bitmap, and AppKit drew an extra item-level outline around the shifted glass surface.
- Fix: Added a transparent `162pt` toolbar slot with the existing `155x32pt` native glass capsule trailing-aligned, introduced an editor-only `14pt` SF Symbol configuration, replaced the bitmap `Aa` with a native `13pt` regular text button, and disabled the outer `NSToolbarItem` border so only the glass material draws the capsule.
- Verification: The final packaged comparison is `/tmp/mudsnote-visual-qa-201-editor-tools-final/apple-notes-vs-mudsnote.png`; its toolbar crop shows reference-aligned capsule bounds and one outline. Full tests, installed-app library smoke, packaging, and strict signature validation passed.
- Lesson: Use a transparent layout slot to position a native material without changing its geometry, and explicitly suppress item chrome when the contained AppKit view already owns the visible surface.

### 202. Linear post-save snapshot update

- Problem: Every autosave removed the edited note from the up-to-`10,000`-entry library snapshot, appended its replacement, then sorted the entire array on the main thread. The first linear prototype still spent about `60ms` standardizing every URL in the removal loop.
- Fix: Added a pure ordered-snapshot upsert that removes matching raw paths, finds the modified-date insertion point with binary search, inserts once, and trims once. URL normalization now happens at the save boundary, with raw and normalized old/new paths supplied to the hot loop.
- Verification: Ordering, rename replacement, duplicate prevention, capacity, autosave, and date-group sorting tests pass. A debug-build `10,000`-entry update stays below the `50ms` regression gate across three consecutive runs. Full tests, packaging, installed-app smoke, strict signature verification, and collapsed-state visual QA passed.
- Lesson: Moving from sort to insertion is not enough when per-element normalization dominates; canonicalize identifiers at mutation boundaries and keep the array loop allocation-light.

### 203. Snapshot-backed rich Markdown serialization

- Problem: Autosave serialized the whole attributed document on the main thread, and every formatting run fetched and bridged the full Swift `String` to `NSString` again before extracting its substring. Dense formatting therefore repeated whole-document work thousands of times.
- Fix: Added one serialization-scoped context that snapshots the source `NSString` once and caches `NSFontManager` traits by font identity. Lines, tables, and inline runs share that context while preserving the existing synchronous save ordering and exact Markdown output.
- Verification: A 5,000-run alternating-format document improved from about `41ms` to stable `27ms` debug runs, remains below a `50ms` regression gate, and compares against the complete expected Markdown. Full tests, packaging, installed-app smoke, strict signature verification, and content-state visual QA passed.
- Lesson: Cache immutable document-wide values at the serialization boundary; repeated Swift/Foundation bridging inside a per-run loop can dominate more than the formatting logic itself.

### 204. Incremental folder-tree lifecycle projection

- Problem: Creating, renaming, or deleting a folder recursively rescanned the complete source directory tree on the main thread before repainting the sidebar. Large hierarchies could therefore stall a direct user command, and an older deferred scan could overwrite a newer local mutation.
- Fix: Added a bounded in-memory folder-tree projection for sorted insertion, subtree path remapping, and subtree removal. Lifecycle commands now update that snapshot immediately, while a generation guard rejects stale deferred scans and the filesystem monitor remains responsible for external changes.
- Verification: Snapshot-isolation tests prove local lifecycle changes do not synchronously absorb an unrelated external directory. A 10,000-row insertion test improved from about `126ms` total test time to stable `38–40ms` runs and passes a `<50ms` operation gate. Full tests, packaging, installed-app smoke, strict signature verification, and expanded visual QA passed.
- Lesson: A loaded navigation hierarchy should be mutated as application state; recursive filesystem discovery belongs to cancellable background validation, not the command path.

### 215. Registered macOS library folders

- Problem: The macOS source pane could create and delete subfolders but did not expose the existing multi-root storage model as a safe library workflow. Extra top-level roots were treated like ordinary folders, so deleting one could affect its contents, no folder context menu revealed its Finder location, and a recently opened external `.hermes/SOUL.md` file could become the automatic launch selection even though `.hermes` was not registered.
- Fix: Added `File > 将文件夹添加到资料库…` and the same action on the library group context menu. Registered top-level folders now expose `在 Finder 中显示` and `从资料库移除`; removal clears only Mudsnote registration and library UI metadata while preserving every file. Nested managed folders retain rename and destructive delete actions. Registration rejects duplicate and parent/child-overlapping roots and refreshes the source tree, note snapshot, tags, search session, and filesystem monitor. The launch shell, full All Notes snapshot, tags, and library search now use configured roots instead of expanding every recent external file's parent directory.
- Lesson: A registered source and a managed child folder have different ownership semantics. Removing a source must never be implemented by reusing filesystem deletion, and recent external documents must not leak across launches into the library's automatic selection.

### 216. Quiet native inline folder naming

- Problem: The temporary `新建文件夹` row drew a bright blue rounded rectangle around the entire text field. Inside the compact dark source list this looked like a separate form control, crowded the selected text, and broke the native sidebar rhythm.
- Fix: Kept the shared AppKit field editor and full-name selection behavior, but removed the custom background and accent border, retained a borderless no-focus-ring field, and reduced its layout height from `24pt` to the native single-line `20pt` alignment.
- Lesson: Field-editor behavior and custom field chrome are independent. Preserve AppKit input and IME semantics while letting the source row provide the visual container.

### 217. Real-folder single-library sidebar

- Problem: A single configured library still appeared twice as the synthetic `All iCloud` aggregate and a default root forcibly titled `Notes`. After registering `Mudsbuild`, the sidebar therefore implied that both rows were required folders and obscured which physical directory quick capture actually used.
- Fix: Source roots now keep their real filesystem names. When exactly one top-level library is configured, that root becomes the selected library scope and the redundant aggregate row is omitted; `All iCloud` returns only when multiple top-level roots need a combined view or an explicitly opened external document is being projected.
- Lesson: Aggregate navigation is useful only when there is something to aggregate. A single-folder library should expose one truthful source identity instead of a synthetic total plus a renamed duplicate.

### 218. Immediate source-selection color

- Problem: Clicking another source row updated AppKit's selection immediately, but the custom yellow title color still followed the previous logical scope until a synchronous dirty-note save completed. The visible selection therefore appeared to lag behind the click.
- Fix: Source-cell presentation now derives its selected state from the outline view's current selected row and refreshes before save/navigation work begins. The logical scope still changes only after the current note saves successfully, and a failed save restores the previous selection.
- Lesson: Interaction feedback should follow the control's immediate selection state, while model navigation can retain its transactional save boundary. Visual acknowledgement must not wait behind synchronous persistence.

### 219. Mouse-up source navigation

- Problem: Removing the save delay made the next source turn yellow on mouse-down, before the user released the click. The response was fast but felt like the row had already moved underneath a still-held pointer.
- Fix: Primary mouse selection is now visually and logically deferred between mouse-down and mouse-up. The previous source stays yellow while pressed; releasing commits the new row, updates yellow styling, saves if necessary, and navigates. Keyboard source navigation remains immediate.
- Lesson: Fast feedback still needs the correct gesture boundary. List selection by pointer should commit on release, while keyboard selection should not inherit mouse-specific deferral.

### 220. AppKit-owned mouse-up commit

- Problem: The first mouse-up implementation waited for an overridden `mouseUp`, but `NSOutlineView.mouseDown` owns the complete tracking loop and consumes the release event before returning. The deferral flag therefore stayed active and real pointer clicks stopped navigating even though the isolated state test passed.
- Fix: The source outline now finishes and commits deferred selection immediately after `super.mouseDown` returns, which is AppKit's actual click-release boundary. The regression also asserts that the deferral state is cleared after commit.
- Lesson: AppKit controls may track press, drag, and release synchronously inside `mouseDown`; interaction tests must exercise the framework's real event boundary instead of assuming a separate `mouseUp` override will run.

### 221. Atomic source highlight and text color

- Problem: AppKit moved the native row selection background on mouse-down while the custom yellow title correctly waited for release, briefly splitting one selected state across two rows.
- Fix: Source rows now draw their selection background from the same visual-selection predicate as title, symbol, and count colors. During a held click the old row retains all selected styling; on release the background and foreground styling move together to the committed row.
- Lesson: A custom list selection must have one presentation source of truth. Mixing AppKit's pending row background with model-backed foreground colors creates contradictory feedback even when navigation timing is correct.

### 222. Immediate pointer visuals with release navigation

- Problem: Iteration 221 incorrectly delayed the existing AppKit row highlight until release. The intended behavior was to preserve the original mouse-down highlight and make only the custom foreground colors catch up to it immediately.
- Fix: Restored native row-selection drawing and made title, symbol, and count colors follow the outline's selected row even while logical navigation is deferred. Mouse-down now moves the complete visual selection; mouse-up still performs save-backed source navigation.
- Lesson: Visual selection timing and navigation timing are separate contracts. AppKit can acknowledge a pressed row immediately while expensive or transactional content changes wait for the completed click.

### 223. Synchronous pressed-row foreground repaint

- Problem: The pressed row's foreground values changed during mouse-down, but AppKit's synchronous outline tracking prevented the normal deferred display pass until release, so the yellow text still appeared late on screen.
- Fix: Pointer-deferral selection changes now force the containing window to display its freshly configured title, symbol, and count colors before returning to AppKit's tracking loop. Navigation remains release-bound.
- Lesson: Mutating view properties inside a synchronous event-tracking loop is not proof that pixels changed; immediate press feedback may require an explicit display pass before the loop resumes.

### 224. Pre-tracking pressed-row color preview

- Problem: Even a forced display from the outline selection notification remained too late in the real AppKit event path: the native highlight appeared inside `super.mouseDown`, while the custom foreground did not become visible until that tracking call returned on release.
- Fix: Before entering `super.mouseDown`, the outline now resolves the selectable row under the pointer, publishes it as the temporary visual selection, refreshes the title/symbol/count colors, and completes a display pass. AppKit then applies its original highlight behavior; release clears the preview and commits navigation. Disclosure-button presses do not create a row-color preview.
- Lesson: When a framework owns a blocking interaction loop, truly immediate custom feedback must be prepared before entering that loop rather than reacting to notifications emitted from within it.

### 225. Platform-scoped installed-artifact ownership

- Problem: An iOS-only worktree ran the macOS packaging script after its shared tests, replacing `/Applications/Mudsnote.app` with that branch's older macOS sources and making completed mac work appear to regress.
- Fix: Project instructions now prohibit macOS packaging from iOS-only tasks. `package_app.sh` also detects branches whose changes are confined to iOS and documentation, refusing to overwrite the shared installed app unless an explicit exception is supplied.
- Lesson: Git worktrees isolate source and build directories, not global deployment destinations. Parallel platform work needs ownership checks around `/Applications`, devices, servers, and every other shared live artifact.

### 226. Independent macOS and iOS delivery lanes

- Problem: A single `verify pr|full|live` entrypoint mixed macOS SwiftPM tests, iOS metadata checks, and macOS installation. Even after guarding `/Applications`, task intent and verification ownership remained ambiguous.
- Fix: Verification now has explicit `macos`, `ios`, and `both` scopes with independent PR, full, and live implementations. Devflow's one-argument PR/full calls safely detect the changed platform; live verification never infers an installation target. iOS live installs only to the connected phone, macOS live installs only to `/Applications`, and dual live requires an explicit `both` command.
- Lesson: Platform separation must cover validation and deployment entrypoints, not only source directories. Compatibility automation may infer read-only checks, but every live target must be named explicitly.

### 227. Scroll-safe source-list hover

- Problem: Source folder and tag rows each retained their own hover state. Scrolling beneath a stationary pointer could skip tracking-area exit events and leave several gray hover highlights painted at once.
- Fix: The source outline now owns one weak hovered row and reconciles it from the current pointer and visible rectangle whenever its clip view scrolls, matching the established note-list fix.
- Lesson: Hover in a reusable scrolling list is collection state, not independent row state; the container must clear the previous owner and recompute it after scrolling.

### 228. Title Return continues into the note body

- Problem: Pressing Return while editing a macOS library note title fell through to `NSTextField`'s default end-editing behavior, which left the title selected instead of continuing to the body.
- Fix: The title-field delegate now consumes Return after native IME handling, focuses the rich Markdown body, and places the insertion point at its first line without changing either field. Added direct AppKit regression coverage and an installed-app keyboard assertion to the library smoke.
- Lesson: A visually continuous title/body editor built from separate native controls needs an explicit Return transition; relying on single-line field-editor defaults breaks the expected Notes-style writing flow.

### 229. Main-editor commands and Inbox-first floating windows

- Problem: Slash commands could miss real keyboard input in the main editor, the selection toolbar was detached from the pointer and hid highlighting behind a second-level menu, and the floating-window manager could not create a fresh window or choose the expected Inbox destination.
- Fix: Main-editor slash suggestions now refresh after the text view finishes inserting text. The selection panel centers on the pointer, exposes highlight directly, and uses `Aa` for format conversion. Floating-window management adds a dedicated new-window action, with new floating notes preferring an existing `Inbox` or numbered Inbox folder and falling back to the default library's `Inbox`.
- Lesson: Editor affordances must be driven by post-input state, and creation commands should resolve their storage destination through one explicit policy shared by every entry point.

### 230. Pointer-centered selection toolbar without vertical drift

- Problem: Centering the selection toolbar on the pointer changed both axes, moving it away from its established position beneath the selected text.
- Fix: The toolbar now follows only the pointer's horizontal center while retaining the original selection-based vertical origin below the text.
- Lesson: Pointer-centered placement can be axis-specific; preserve the stable axis when only click reachability on the other axis needs improvement.

### 231. Customizable editor menus

- Problem: The editor's right-click menu and selection floating toolbar always showed a fixed command set, even when a writing workflow used only a small subset.
- Fix: The macOS Editor settings pane now independently selects visible right-click commands and selection-toolbar buttons. Existing commands remain enabled by default, choices persist, and library and floating editors read the saved configuration when constructing each menu.
- Lesson: Customization should filter one canonical command model at presentation time so behavior, shortcuts, and undo remain unchanged.

### 232. Compact floating-window management

- Problem: The floating-window manager was wider and taller than the floating note itself, and each open window used a loose two-line layout that made a short list feel oversized.
- Fix: The macOS manager now fits the 300-point floating-note width, uses a dense 36-point single-line row for each window, and tightens its title, search field, padding, icons, and corner radii. Rows fill the available width, while the vertical scroller appears only when more than five results require it.
- Lesson: A transient manager should inherit the scale of its owning window; compact one-line rows preserve scanability without turning a lightweight control into a second full-size surface.

### 233. Contained and motionless short floating-window lists

- Problem: The compact floating-window manager could still sit partly outside a resized note window, its red current-window dot repeated context the panel already implied, and a one-row list reacted to scrolling even though it had nowhere to go.
- Fix: The macOS manager now clamps its complete frame to the parent note window, removes the redundant current-window marker and selection plumbing, and enables both the vertical scroller and elastic scrolling only when the result count exceeds five rows. Returning to a short list also resets the scroll position.
- Lesson: A child panel should be constrained by its owning surface rather than only the screen, and a list without overflow should have neither a visible scrollbar nor invisible bounce behavior.

## Maintenance Rule

For every future Mudsnote fix:

1. Add a new numbered iteration.
2. Record the visible problem, the concrete fix, and the lesson.
3. If the issue remains partially unresolved, add it to the open-issue section instead of hiding it.

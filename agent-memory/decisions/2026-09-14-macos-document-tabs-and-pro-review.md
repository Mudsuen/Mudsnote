# Mac document tabs and sidebar review

User request: review/rebuild with GPT Pro, correct sidebar/file/search semantics, support multiple notes and right-click new tabs, preserve backdrop color with blur, and improve interaction reliability. Scope is macOS.

## Decision

Keep NoteStore and the existing rich Markdown editor. A stable LibraryDocumentTab identity owns the document buffer, undo manager, revision, disk baseline and save/close state. One visible editor restores that state on activation. A background save carries the document identity as well as generation and revision; it may finish after the visible slot has changed. Retain unsaved replaced sessions until saved, and reopen failed ones. Close/quit refuses to discard failed writes.

Sidebar collapse controls the actual split item. File and Search are sidebar modes; source management stays a separate named menu. Plus creates an empty tab; new-note creation is separate. Context actions capture URL targets and do not load a note just to show a menu. Trash edit permission follows the document URL rather than the sidebar filter.

Use a full-strength underWindowBackground effect behind the window with transparent content. Desktop comparison rejected clear glass and a faded-effect experiment because background text competed with the editor. The final effect preserves recognizable hue transitions with opaque text; visual taste still needs user feedback.

## Review evidence

- Baseline submitted: d8158b47e5c2fc635555f33da2c2c1b10fb9faa0, bounded implementation attachment and two reference images.
- Selection: Latest and Pro, verified separately; one send.
- Conversation: https://chatgpt.com/c/6aa794d3-1ecc-83ea-af64-1a54e29e1943
- Completed response SHA-256: 8cfc01ca44cd9fdd9e6417f0fb147fce308f40ece4b11a7c438a83f0432a47cd.
- Local evidence: task visualization pro-review-2026-09-14/20260914T063046Z-e5aecdd1; status complete.

Adopted: distinct controls, persistent sidebar search, stable save identity, per-document undo/read-only, captured menu targets, empty-tab semantics, background opening and status-layout decoupling. The external reference implementation's claimed Linux tests are not part of our test count. Kept the user's explicit horizontal folder shortcuts. Session restoration, pinned/reorderable tabs and crash journaling remain separate extensions.

Validation and real-window observations are recorded in design-qa.md. Shared installed macOS app and iOS are untouched; deliver through the existing draft PR.

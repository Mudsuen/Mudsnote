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

## Maintenance Rule

For every future Mudsnote fix:

1. Add a new numbered iteration.
2. Record the visible problem, the concrete fix, and the lesson.
3. If the issue remains partially unresolved, add it to the open-issue section instead of hiding it.

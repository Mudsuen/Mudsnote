# macOS continuous material and compact navigation

The user rejected the previous nearly opaque pane tint and requested Board's
floating-window material, an icon row for first-level folders, icon-only search,
and less unused space at the top and bottom.

Current Board reference: NativeWindowMaterial uses active NSVisualEffectView
popover material, behind the window. Its floating surface keeps content opacity
independent of the material. A real floating window was captured before editing.

Mudsnote now uses that native material in both panes and the shared navigation
row. Pane tint is only 4.5% black for navigation and 1.5% white for the document;
Reduce Transparency retains an opaque semantic fallback. Text remains opaque.

The 40-point top row shares the traffic-light area. The library root and its
immediate child folders, plus separately registered roots, appear as icons with
full-name tooltips and accessibility labels. Nested folders and tags remain in
the existing picker. Overflow stays in one horizontal scroll area; focused
buttons reveal themselves. Search opens a native popover and retains existing
current/all scope filtering, result navigation, Return, and Escape behavior.

Dates move to note information in the quick menu. A short footer retains links,
word count, and save failures without reserving blank space inside NSTextView.
The note list loses separators and heavy selection fill; ordinary rows remain
transparent. The slash-suggestion overlay remains owned by the root content view.

Verification uses the independent preview and synthetic Notes directory under
the task's visualization directory. No iOS or shared installed app changes.

Final verification: `./scripts/verify macos full` passed 315 regular tests
and eight Release performance tests (exit 0). The added regression exercises
30 folder icons, overflow, selection, and search dismissal. The icon scroll
width is a low-priority preference so overflow cannot expand the window.
Search uses a semitransient popover to keep keyboard input stable.

Real-window review covered dark/light appearance, folder selection, search
input and Return/Escape. Screenshots and review are persisted in the task's
visualization material-review directory. Native window dragging was attempted
but frame movement was not observed, so it is not a passed interaction check.

Follow-up: the user supplied Obsidian header structure and rejected excessive
transparency during preview. The latest version uses one root sidebar effect
at full opacity; child panes supply only tint. Do not fade the effect itself,
which exposes distracting background detail. Navigation aligns with the list,
the document title chip aligns with the editor, and folder shortcuts remain in
a compact row above the list. This supersedes the layered popover description.

Final follow-up verification: 315 tests passed with `./scripts/verify macos pr`
(19.374s); actual folder/title synchronization and search dismissal checked.

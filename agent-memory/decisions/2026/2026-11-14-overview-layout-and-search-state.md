# Separate content changes from viewport movement

Scope: macOS library navigation and overview, November 14, 2026.

The live review reproduced a hidden search field receiving the search command,
offscreen overview branches, invisible blank topics and a selected note outside
the visible list. Search visibility had separate implementations in the button,
shortcut and history paths. The overview rebuilt breadcrumbs, its ownership tree
and text measurements during viewport rebasing and preview animation.

Search presentation now has one controller entry point. Page history includes
the search scope and focused overview root. Escape clears a query before
dismissing the search field; native cancel keeps the field available for reuse.
Selection is revealed after deliberate navigation, not background refreshes.
Save-driven renames remap the selected path before rebuilding rows, preserving
selection for both explicit saves and background autosaves. The save refresh
also reuses the row builder's scope projection instead of computing it twice.

`OverviewContentIndex` owns lookup dictionaries and the ownership tree.
`LibraryOverviewView+Layout` owns geometry caching and presentation. The cache
key includes viewport size, content revision, root, structure, presentation,
folds, expanded cards and the embedded editor. Content and preview changes
invalidate measurements; pan translation and active selection do not.
Breadcrumbs retain their views until path, labels, available width or appearance
changes. Outline guide extents use a bottom-up pass instead of repeated subtree
walks. The existing bounded three-viewport canvas and world coordinates remain.

Blank-topic fallbacks are display values. Editing and persistence still use raw
text, so the review never rewrites personal overview metadata to insert labels.
Regression coverage checks search focus in all navigation modes, history scope,
topic Back/Forward, fit bounds, and zero geometry rebuilds across 80 large pans.

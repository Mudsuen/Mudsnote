# Pre-tracking source color preview

## Contract

- Yellow source foreground must appear on mouse-down with the native row highlight.
- Note-list navigation remains committed on mouse-up.

## Implementation

`LibrarySourceOutlineView.mouseDown` resolves the selectable row under the pointer before `super.mouseDown`, exposes it through `primaryMouseVisualSelectionRow`, and synchronously refreshes the visible source cells. The preview is cleared after AppKit's tracking loop returns.

Disclosure-button hits retain the existing selection preview so expand/collapse does not falsely recolor a folder.

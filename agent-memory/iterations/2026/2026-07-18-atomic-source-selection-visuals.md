# Atomic source selection visuals

## Contract

- Selected background and yellow foreground styling must always identify the same source.
- A held primary click retains both on the previous source.
- Mouse release moves both to the committed source together.

## Implementation

`LibrarySourceOutlineRowView` draws its background from the controller's visual-selection predicate instead of AppKit's pending `isSelected` state. Cells use the same predicate for title, icon, and count styling.

## Regression

The pointer-deferral test asserts both row-view background state and cell foreground color before and after commit.

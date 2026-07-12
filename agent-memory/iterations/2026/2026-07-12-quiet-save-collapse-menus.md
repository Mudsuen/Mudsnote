# Quiet save timestamps, collapse, and menus

## Decision

- Library autosave leaves the displayed file time unchanged while editing and refreshes it only after a successful file write.
- Floating draft autosave does not replace the status text with save-progress or save-completion labels.
- Source visibility chrome is updated as one state with the native split-item collapse animation.
- The nonessential list ellipsis is not part of the default toolbar.
- Menu-backed toolbar buttons use normal AppKit click-release activation and a centered lower-edge anchor.

## Verification boundary

- Keep list sorting/grouping commands available through the application menu and tested menu builder even though the toolbar ellipsis is absent.

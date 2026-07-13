# Design QA: expanded source toolbar icons

## Evidence

- Reference: `/tmp/mudsnote-source-action-icons-final-207/apple-notes-reference-normalized.png` (`921x613pt`, `1842x1226px`)
- Current: `/tmp/mudsnote-source-action-icons-final-207/mudsnote-library.png` (`921x613pt`, `1842x1226px`)
- Combined comparison: `/tmp/mudsnote-source-action-icons-final-207/apple-notes-vs-mudsnote.png`
- State: dark appearance, expanded source sidebar, pointer outside the toolbar, content note selected

## Review

- P0: none
- P1: none
- P2: none
- Add Folder uses the same `folder.badge.plus` system symbol as the reference and measures `44x30px`, versus Apple Notes' `44x31px` visible boundary.
- Sidebar Toggle uses the same `sidebar.left` system symbol as the reference and measures `38x30px`, exactly matching Apple Notes.
- Native `.toolbar` hover/pressed drawing, `30pt` hit areas, toolbar positions, and collapsed `.glass` control remain unchanged.
- Intentional differences outside this check: local fixture content, omitted Call Recordings source, and non-identical colors.

## Remaining P3

- Folder height differs by one Retina pixel, below the threshold for another point-size change.

final result: passed

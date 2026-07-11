# Design QA: compact Apple Notes scale

## Evidence

- Reference: `docs/visual-qa/apple-notes-content-reference.png` (`931x623pt`, `1862x1246px`)
- Current: `docs/visual-qa/compact-scale-current.png` (`1080x720pt`, `2160x1440px`)
- Combined comparison: `docs/visual-qa/compact-scale-comparison.png`
- State: dark appearance, three panes visible, content note selected, no focused search field or editor caret

## Review

- P0: none
- P1: none
- P2: none
- Window aspect ratio, source/list/editor proportions, row density, type scale, and toolbar geometry are visibly aligned at normalized height.
- Toolbar groups remain complete and do not overflow at `1080x720`.
- `Recently Deleted`, source counts, note metadata, and editor content remain inside their containers.
- Intentional differences: no Call Recordings source, local Markdown fixture content, and non-identical colors.

## Remaining P3

- Continue per-symbol toolbar optical tuning only when a same-state comparison shows a concrete mismatch.
- Complex long-form editor content can receive a separate content-rhythm pass without changing the accepted shell scale.

final result: passed

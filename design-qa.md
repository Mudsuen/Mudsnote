# Design QA: native toolbar and source icon audit

## Evidence

- Expanded reference/current: `/tmp/mudsnote-all-icons-probe-208/apple-notes-reference-normalized.png` and `/tmp/mudsnote-all-icons-probe-208/mudsnote-library.png`
- Expanded comparison: `/tmp/mudsnote-all-icons-probe-208/apple-notes-vs-mudsnote.png`
- Collapsed comparison: `/tmp/mudsnote-editor-toolbar-icons-collapsed-208/apple-notes-vs-mudsnote.png`
- Real-pointer Aa hover: `/tmp/mudsnote-window-hover-crop-208.png`
- State: dark appearance, canonical `921x613pt`, `2x`, content note selected, pointer outside static comparison

## Review

- P0: none
- P1: none
- P2: none
- New Note matches Apple Notes at `32x32px`.
- Checklist is `36x33px` versus `37x33px`; Table matches at `39x30px`; Attachment matches at `31x35px`.
- Native Aa is `37x25px` versus `39x24px` and remains fully contained by its real hover highlight.
- Search remains the native `NSSearchField`; its icon is within `2px` of the reference and was not overridden.
- Source folder/trash symbols preserve reference-aligned trailing edges and title origins. The folder width differs by `3px`, but enlarging it would move the already aligned text.
- Collapsed sidebar glass geometry and symbol scale remain unchanged.

## Remaining P3

- The extra local-first Link command has no equivalent in the captured Apple Notes toolbar; its `13pt` symbol follows the aligned editor-tool family.

final result: passed

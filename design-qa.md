# Floating Window Manager Design QA

**Comparison target**

- Source visual truth: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/codex-clipboard-9d53c08d-ad54-42b9-8bf2-fbd092ead49b.png` for the manager state and `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/codex-clipboard-b6899829-4dbb-43a7-9df5-1a1b77a33aa0.png` for the compact-row direction.
- Rendered implementation: `/tmp/mudsnote-floating-manager-compact-final.png`.
- Full-view comparison: `/tmp/mudsnote-manager-full-comparison-final.png`.
- Focused row comparison: `/tmp/mudsnote-manager-row-comparison-final.png`.
- Viewport: native macOS floating note at 300 x 314 points with its borderless manager at 300 x 116 points.
- Pixels and density: source manager 690 x 352 pixels, row reference 552 x 106 pixels, implementation capture 692 x 628 pixels including the parent window. The implementation panel was compared at its 602 x 232 pixel crop, corresponding to approximately 301 x 116 points at 2x. The focused comparison normalized both row crops to 61 pixels high.
- State: dark appearance, one current unsaved floating note, manager open, search empty and focused.

**Full-view comparison evidence**

- The implementation preserves the source manager's title, new-window action, search field, divider, current-window marker, title, subtitle, and close action.
- The intended change is visible: the manager contracts from the source's approximately 345-point width and loose two-line result to the floating note's 300-point width and a single 36-point row.
- Typography uses native system fonts with reduced sizes and weights; spacing, radii, and control dimensions follow the denser row reference. Colors continue to use the app's existing vibrancy-aware panel tokens.
- Copy remains app-native and unchanged in meaning. No raster imagery, custom logos, or non-standard image assets are present; SF Symbols remain sharp at native density.

**Focused region comparison evidence**

- The focused row comparison confirms a continuous rounded row, one-line title and subtitle, compact marker, and trailing action aligned on the same center line as the reference.
- The implementation intentionally retains the app's red current-window marker and close symbol instead of copying the reference row's pin/archive actions.

**Findings**

- No actionable P0, P1, or P2 mismatch remains.
- P3: the semantic close symbol is visually stronger than the reference's secondary actions, but it remains within a 24-point target and uses the secondary text token; this is acceptable for the destructive per-window action.

**Comparison history**

1. Initial comparison: the one-row manager still showed a vertical scroller and the table column did not fill the available list width (P2).
2. First fix: made the single note column autoresize to the scroll viewport and enabled the vertical scroller only when more than five rows exist. The follow-up layout assertion showed that AppKit's inset table style still reserved approximately 16 points at each side (P2).
3. Second fix: explicitly selected the plain table style so the compact row can use the scroll viewport's full width.
4. Post-fix evidence: `/tmp/mudsnote-floating-manager-compact-final.png`, `/tmp/mudsnote-manager-full-comparison-final.png`, and `/tmp/mudsnote-manager-row-comparison-final.png` show the row reaching the intended 8-point panel margins with no unnecessary scroller.

**Implementation checklist**

- [x] Match the floating note's 300-point width.
- [x] Use compact single-line result rows.
- [x] Preserve new, search, activate, add, and close behavior.
- [x] Keep overflow scrolling for lists longer than five rows.
- [x] Verify the native rendered state against both supplied references.

final result: passed

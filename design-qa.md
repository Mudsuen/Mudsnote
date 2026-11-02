# Native workspace shell design QA

Source visual truth: `/tmp/codex-clipboard-78864bd5-3b52-4aa0-a302-c0cc2643b836.png`.
Current-app reference: `/tmp/codex-clipboard-2b8d2426-5f22-41af-9fa1-a7d2b4ae4ea0.png`.
Both are private user screenshots, local only; do not commit their pixels.

Source: 1958 x 1456 pixels at 2x, equivalent to 979 x 728 points.
Target: native AppKit, dark appearance; preserve note semantics rather than chat content.

## Findings awaiting rendered comparison
- P1: ordinary-window content must not require horizontal scrolling.
- P1: sidebar/toolbar navigation must not duplicate large actions or show a misleading blank document on the overview.
- P2: list typography and density must match the compact reference.
- P2: independent rail must retain hover, selected, tooltip and focus feedback when the list collapses.

## Required evidence
Capture at 896 x 580, 979 x 728, and 1200 x 800 points. Normalize @2x captures and reference into one full-view comparison and focused chrome/list comparisons. Use synthetic notes only.
Check fonts/typography, spacing/layout rhythm, colors/tokens, image quality, and app-specific copy.
Check navigation back/forward boundaries, ordinary versus overview creation, inline save, list selection, sidebar collapse, pointer feedback and window drag.

Verification policy: `./scripts/verify macos ui`, not the full suite. Release must record the actual scoped command and retain signature, provenance, hash and rollback gates.

final result: blocked

# 2026-07-11 reference-scale library

## Request

Continue Apple Notes UI parity after the user said the newer Mudsnote window and controls had become too large and an earlier compact version looked closer.

## Evidence

- Recovered the original content-state Apple Notes screenshot at `1862x1246px`, which is `931x623pt` at 2x backing scale.
- The prior visual harness compared it with a `1420x860pt` Mudsnote window by drawing each at a different scale. That normalized image hid the native-point-size difference.
- Historical `2c9c648^` used the earlier compact `1160x764` shell, `220pt` source column, small list fonts, and `68pt` note rows before the later scale expansion.

## Implementation

- Set the final reference-scale default window to `1080x720`, with a near-identical `1.5` aspect ratio to the Apple Notes reference.
- Set default source/list columns to `250/250pt`, preserving native draggable splitters and a `480pt` minimum editor.
- Reduced source rows to `36pt`, note groups to `48pt`, note rows to `76pt`, and restored compact source/list typography.
- Reduced editor title/body to `30/15pt`, code to `14pt`, horizontal inset to `24pt`, and tightened line/paragraph rhythm.
- Kept the approved no-rim toolbar groups (`184x32` editor tools, `72x32` file actions, `30x30` circular actions) and narrowed search to `210pt`.
- Added a one-time layout scale migration that clears only legacy stored source/list widths, then preserves all future user resizing.

## Verification

- Focused layout, split persistence, and migration tests passed.
- Full Swift suite: 128 tests passed.
- Production package installed at `/Applications/Mudsnote.app`.
- Final visual metadata recorded `1080x720pt`, 2x backing scale, direct-window capture, requested content fixture, and Mudsnote frontmost before capture.
- Installed direct-launch smoke showed one `Mudsnote 笔记` window at `1080x720`, exact `250/250` splitters, and all eight toolbar items present.
- Strict deep code-signature verification passed for `/Applications/Mudsnote.app`.
- Stored evidence:
  - `docs/visual-qa/apple-notes-content-reference.png`
  - `docs/visual-qa/compact-scale-current.png`
  - `docs/visual-qa/compact-scale-comparison.png`
- `design-qa.md` result: passed with no P0/P1/P2 findings.

## Decision

- Native point geometry is authoritative for scale decisions; normalized comparisons are necessary but not sufficient.
- Keep the compact toolbar geometry while using the smaller shell and text/list metrics.
- Exact color matching remains intentionally out of scope per user direction.

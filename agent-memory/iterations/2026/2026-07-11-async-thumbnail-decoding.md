# 2026-07-11 Asynchronous thumbnail decoding

## Baseline

- Started from macOS iteration commit `24e2114` (`Load uncached notes off main thread`).
- The note list already reused cells, limited ImageIO decoding to `88px`, and cached successful and failed thumbnail lookups.

## Problem

- A first-time thumbnail cache miss still decoded synchronously from `tableView(_:viewFor:)`.
- The first row layout happens during `showWindow`, before `window.isVisible` reports true, so visibility could not reliably choose the asynchronous path.

## Implementation

- Record presentation intent before showing the library window.
- Deduplicate in-flight thumbnail requests by standardized file path.
- Decode `CGImage` values in utility-priority detached tasks and construct/cache `NSImage` values on the main actor.
- Preserve positive and negative cache behavior, reload only rows that still reference the completed thumbnail, and cancel outstanding tasks when the window closes.
- Keep hidden-window unit tests synchronous so existing deterministic thumbnail assertions remain valid.

## Verification

- Focused thumbnail tests: 2 passed.
- Full Swift test suite: 119 passed.
- `git diff --check`: passed before packaging.
- Production package installed at `/Applications/Mudsnote.app`; strict deep code-sign verification passed.
- Installed visual QA: `/tmp/mudsnote-async-thumbnails-visual-20260711/apple-notes-vs-mudsnote.png`; the image-backed `gptest` row rendered its thumbnail with the compact Notes-like layout intact.
- A gated decoder regression test proved the first visible request returns a placeholder without blocking and repeated cell requests produce one decode.

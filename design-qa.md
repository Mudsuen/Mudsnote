# Live Mubu overview recreation — candidate, 2026-11-04

## Confirmed scope

Only the overview mind map and outline are being recreated. Preserve the existing
library rail, search entry and note-list presentation, including the requested
icon-only compose action. Canonical Markdown editing still uses the shared editor.

## Source and capture evidence

- Source visual truth: the user's authenticated, currently open Mubu page, then a
  disposable neutral document created for interaction tests. Private document URLs,
  business text and reference images are not committed to this repository.
- Source viewport: 1615 × 919 CSS pixels, devicePixelRatio 2; browser captures are
  emitted at CSS-pixel scale. Text and node geometry were read from actual DOM
  elements, editable canvas overlays and computed styles. No private JS state was read.
- Native preview requested: 1633 × 963 AppKit points (2× density), so its content
  area can be compared after excluding native titlebar and the existing sidebar.
- Native implementation screenshot: unavailable. The computer-use tool reported
  the Mac was locked and required the owner's manual unlock. A build or a test
  result is not treated as evidence of rendered fidelity.
- Temporary preview and source-session pointers are under
  `/tmp/mudsnote-live-reference-20261104`, outside Git.

## Five required fidelity surfaces

- Typography: live outline title 34/54.4 and topics 16/25.6 plus six points of row
  padding; map root Helvetica Neue Medium 24/38, first level 16/26 and deeper levels
  14/22. Source Sans Pro Regular/Semibold are bundled for the outline rather than
  relying on a system-font substitution. Long titles and descriptions wrap.
- Layout: 28-point outline nesting, 31-point text inset, 6-point center dots with
  an 18-point collapsed outer dot; 48-point header, 91 × 26 mode switch; floating
  60 × 168 map panel. Map uses gray rounded elbow branches, first-level pills and
  plain deeper topics. Left/right and right-only structures are implemented.
- Colors: outline light white/#2e2e2e and dark #1c1c1e/#d4d4d4; bullets #949494;
  guides black/10% or #373c43. Ink uses white paper/black root; Focus uses dark
  paper/light root. The app appearance and map palette are independent settings.
- Assets: standard SF Symbols for functional controls; live vector/text rendering
  for topics and branches. Fonts are unmodified Adobe OTFs with the bundled OFL
  license and pinned-source/hash record. No private source screenshots are assets.
- Copy/content: comparison content is neutral and disposable. Existing areas,
  note identity and principles survive. In Mudsnote, structural topics can nest;
  linked notes remain document leaves and expose their existing rich editor.
  No nonfunctional account, collaboration or publishing controls were added.

## Interaction evidence and implementation

The reference was exercised through five levels, not inferred from screenshots:
outline Enter/Tab/Shift-Tab; map Enter/Tab; selection/double-click editing; subtree
folding; dot drill-down and breadcrumbs; parent drag; subtree deletion; undo/redo;
descriptions; light/dark/system appearance; neutral light/dark map palette; zoom
slider and center-root. Map paste can create topics, distinct from normal typing.

The candidate implements inline structural-topic editing with IME completion,
context actions, distinct map/outline keyboard rules, hover fold/More/child actions,
focus breadcrumbs, drag with cycle rejection, metadata undo/redo, independent
appearance preferences, map panning and zoom controls. Linked-note editing reuses
the normal save/conflict path and restores editor appearance when leaving overview.

## Verification and findings

- Affected check: `./scripts/verify macos ui` passed all 22 tests on the final
  source, including bundled font names, five-level moves/focus/undo, IME completion,
  independent modes, long-label layout, descriptions and canonical-note preservation.
- Merged installer/update checks pass all 18 Python tests; packaging syntax
  validation passes. The combined candidate passes deep/strict signature checks,
  team `3JA29GL46S`, and the installed app's designated requirement. Both fonts,
  license and `macos_update_check.py` match their source bytes; CoreText loads both
  fonts from the actual bundle. No installation or private publication occurred.
- Recovery tests cover legacy overview rewrites and malformed canonical metadata;
  recovery data is retained without silently replacing user state.
- Integrated remote `524302f` (startup update checks and prior navigation/sidebar
  fixes) into the candidate. The packaging merge retains both fonts/license and
  `macos_update_check.py`.
- Merged `./scripts/verify macos pr`: all 18 Python tests pass; the latest Swift
  run executes 406 tests with one remaining `isKeyWindow` failure in
  `floatingBrowseButtonDispatchesCompleteClicksToBrowserPanel`. That same failure
  reproduces on unchanged `524302f` on this locked Mac. The assertion is retained.
- A hidden-search TagInput focus failure also reproduces on unchanged `524302f`.
  Its setup now shows the window and clicks the actual Search entry, exercising
  the real blur path; the merged full run confirms that test passes.
- Real-window focus and visual gates remain pending manual unlock; these baseline
  reproductions do not justify skipping native acceptance.
- [P1] Native visual and interactive comparison is blocked by the Mac lock screen.
  No final fidelity claim or installation is permitted before that comparison.
- [P2] Verify actual native control alignment, hover-to-gutter transitions, wrapped
  labels, theme contrast, selected/editing states and scaled drag targets after
  unlock. These are pending checks, not claimed defects or accepted differences.

## Remaining checklist

1. Unlock and compare native/source at the same viewport/state in both modes.
2. Exercise native five-level edits, folds, drag/drop, focus, undo and linked saves.
3. Fix observed P0/P1/P2 differences and recapture.
4. Trash the disposable source document and restore the original source tab.
5. Reverify the exact final candidate after visual fixes, then deliver the main
   commit to the coordinating Mac mini chat. That chat owns installation and
   private distribution; this chat does not operate the Mini app.

final result: blocked

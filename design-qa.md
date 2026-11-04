# Live Mubu overview recreation — accepted, 2026-11-04

## Confirmed scope and visual targets

Recreate only the overview mind map and outline from the user's live Mubu page.
Keep the existing library rail, search and note-list layout, including icon-only
compose. A later GPT chrome screenshot supplies the thin icon treatment for
existing navigation/search/compose controls. No account or notification controls
are invented. Canonical Markdown editing retains the shared editor and save path.

## Capture and comparison evidence

- Reference: authenticated live Mubu DOM/CSS and a neutral temporary document;
  no private JavaScript state was read. Source interactions were exercised through
  five levels. Private URLs, business text and screenshots are not committed.
- Initial source measurement: 1615x919 CSS pixels, DPR 2. Final comparison:
  1082x716 CSS-pixel source viewport and 1100x760-point native window captured at
  2x. Excluding the source sidebar and the native sidebar/titlebar yields matched
  content areas of approximately 811x716 points. Captures were inspected in the
  computer-use session in light/dark outline and Ink/Focus map states.
- The owner unlocked the MBP; the earlier native-capture gate is resolved.
  The isolated preview uses disposable notes, support directory and defaults.
  Native capture/session pointers remain under the temporary reference directory,
  outside Git. The original source document was not edited.
- The temporary Mubu document was moved to recoverable Trash and its presence
  there verified. Follow System appearance, the original document and the normal
  browser viewport were restored.

## Fidelity surfaces

- Typography: bundled Source Sans Pro Regular/Semibold for 34/54.4 outline title
  and 16/25.6 topics, with six points row padding. Map uses Helvetica Neue Medium
  24/38 root, 16/26 first level and 14/22 deeper levels. Actual single-line map
  node heights are 62/50/44 points; wrapped labels use measured line counts.
- Layout: outline 28-point nesting, 31-point text inset, six-point dots and
  18-point collapsed outer dots. Wrapper capped at 872 points with 105-point
  horizontal inset. Header 48, mode switch 91x26, map panel 60x168. Root/first-level
  pills and rounded elbow branches match the live neutral reference.
- Colors: light outline white/#2e2e2e; dark #1c1c1e/#d4d4d4; dots #949494;
  guides black at 10% or #373c43. Ink and Focus map palettes are independent of
  light/dark/system overview appearance. Floating map controls remain white.
- Assets: light-weight SF Symbols replace hand-drawn rail glyphs. Existing
  navigation controls have no surrounding native capsule. Bundled Adobe OTFs are
  unmodified with the pinned source/hash record and OFL license. No private
  reference image is included in app assets.
- Content: neutral hierarchy and descriptions were compared. Mudsnote preserves
  its note identity/membership model: structural topics can nest, while linked
  notes use the existing Markdown editor and remain files when removed from the
  overview. Free-position content stays reachable in outline mode.

## Actual interaction acceptance

Reference and native checks cover five-level Enter/Tab/outdent editing, separate
map/outline keyboard rules, selection and inline editing, descriptions, folded
subtrees, dot drill-down and breadcrumbs. A native parent was dragged to another
parent with its descendant hierarchy intact; folding and structural undo/redo
were verified. Native Command-Z and Command-Shift-Z restore/reapply deletion.
Cycle rejection and linked-file preservation are covered by affected tests.

Blank-map right click exposes New Note, New Topic, Link Existing Note, Center and
Fit All. A note was created there, edited, saved, renamed, freely dragged and
recovered after restart at its persisted world position. A new topic immediately
received typing focus. Repeated blank-space pans move beyond multiple screens;
return-to-center preserves content. Zoom, slider, palette and structure controls
were exercised. Automated panning crosses over 100 viewport widths without
increasing the backing-view size or changing persisted note data.

## Findings resolved

- Single-line node heights were doubled by rounded text bounding boxes.
- Native text-field cell padding clipped the final label character.
- Breadcrumb stack sizing clipped labels.
- Light guide opacity was replaced by an opaque stroke.
- Right-click menus dismissed early and menu restoration stole input focus.
- Shared-editor commit cleared overview focus, disabling structural shortcuts.
- Dragging used the first dragged event as its grab origin. Internal tracking now
  retains the original grab point, shows a drop indicator and supports Escape.
- Dark-map zoom controls needed an explicit white content surface for contrast.

## Verification and delivery boundary

- `./scripts/verify macos pr`: 408 Swift tests and 18 Python updater/installer
  tests pass. The formerly blocked floating-window key-state assertion passes
  after unlock. The shown-search test uses the real visible search entry.
- Final `./scripts/verify macos ui`: 24 affected tests pass, including window-level
  structural undo dispatch, free placement and outline conversion, long text,
  five-level hierarchy operations and shared-editor appearance restoration.
- The merged source retains remote `524302f` startup update checks, navigation
  and sidebar fixes, plus both font resources/license and the packaged updater.
- The candidate-only packaging path signs and verifies the final source. Exact
  candidate revision/signature/resource/font-load evidence is recorded outside
  Git in `/tmp/mudsnote-live-candidate-verification.json`.
- No installation or private bundle publication is performed by this chat. The
  coordinating Mac mini chat owns installation/distribution after source delivery.
  iOS is outside scope.

P0/P1/P2 findings: none remaining. P3: native macOS menus/popover chrome retain
platform styling; the functional content, geometry and contrast are verified.

final result: passed

# Live Mubu reference: overview only

The user rejected the old help-image approximation and supplied an authenticated
Mubu page. Inspect the live DOM/CSS and interaction states, rather than reusing
purple screenshots. Do not commit the user's document URL, business text or images.

Measured live tokens:
- Outline light: white background, #2e2e2e text, #949494 6-point dots,
  black/10% one-point guides. Dark: #1c1c1e background, #d4d4d4 text,
  #373c43 guides, same dots. Title 34/54.4; topic 16/25.6 plus 3-point
  vertical padding; indentation 28; text starts 31 points into the row.
- Map ink scheme: white paper, black rounded root, light gray first-level pills,
  plain 14-point deeper text and gray rounded elbow branches. Root 24-point
  Helvetica Neue Medium, 38-point line height, 24/12 horizontal/vertical padding;
  first-level 16/26 and 16/12 padding; deeper nodes 14/22.
- The app appearance (light/dark/system) and map palette are independent.
  Tested neutral map palettes are Ink and Focus; the latter has dark paper,
  light root, gray first-level pills and muted gray branches.
- Header 48 points, mode switch 91x26 with 6-point radius; map switch is neutral,
  outline-to-map switch uses #5856d5. Floating map panel 60x168, white in both
  schemes, with zoom, structure and palette controls.

Interaction evidence, tested on a disposable neutral document:
- Outline Enter adds a sibling; Tab/Shift-Tab changes indentation. Tested five
  levels. A parent's descendants retain their relative depth when it moves.
- Expanded fold/More affordances appear on the focused/hovered row. Collapsing
  hides the whole subtree and fills the 18-point outer dot, retaining the 6-point
  center dot. Clicking the dot drills into the topic; breadcrumbs return upward.
- Map single click selects; double click edits. Enter creates a sibling and Tab
  creates a child, as distinct from outline indentation. Map paste can create
  topics rather than simply insert text into the selected node.
- Dragging a parent moves its subtree. Delete removes its subtree. Command-Z and
  Command-Shift-Z restore/reapply structural operations. Tested all three.
- Description editing is a separate 14/24 secondary text block. Zoom controls
  include a slider and center-root action; center-root does not change zoom.

Implementation boundary: preserve the existing library rail/list/search and
canonical Markdown save path. Overview metadata owns structural topics; linked
notes keep their file identity and use the existing shared rich editor. Appearance,
map palette and structure belong to overview preferences.

## Implementation risk review (2026-11-04)

- Overview-only appearance, palette, structure and fold state use dedicated local
  preferences. The library rail, search, note rows, hotkeys and iOS are unchanged.
- Optional root title and area descriptions extend the local overview JSON.
  Legacy decoding is retained. A separate latest-full `Overview-recovery.json`
  snapshot is written before the canonical overview, preserving new fields if an
  older build later drops unknown keys. Loading never silently substitutes the
  recovery snapshot for canonical or malformed user state. A dedicated overview
  lock avoids serializing this small metadata with background document writes.
- Structural undo snapshots contain overview metadata, never copies of canonical
  Markdown files. Removing a subtree removes its overview memberships and edges;
  linked files survive. Moves reject cycles before mutation and retain descendant
  IDs. Existing editor saves finish before structural operations.
- Source Sans Pro Regular/Semibold 2.045 are bundled, unmodified, from the pinned
  Adobe source commit in `assets/fonts/SourceSansPro/README.md`. Registration is
  process-scoped; there is no installation into the user's font directories.
- Packaging change is limited to copying those two inert OTF resources and their
  OFL license into the existing Resources folder before normal signing. It does
  not alter signing identity, entitlements, installer behavior or update grants.
  Before installation, verify bundled font hashes, font loading and the usual
  candidate signature. The change is isolated on a feature branch for review.

## Free canvas and icon follow-up (2026-11-04)

The supplied chrome screenshot is GPT, not Mubu. Use thin outline SF Symbols for
existing navigation/search/compose controls and remove the native navigation
capsule. Keep the library layout and actions; do not invent notification controls.

The map is a continuous world-space canvas. Rebase a three-viewport scroll window
as the viewport approaches an edge, retaining a fixed backing-view size. Persist
optional `mapPosition` coordinates on areas/cards, scoped to the focused root.
Free content is separate from automatic branch layout but keeps its membership
in the outline. Dropping into a topic clears the free position and reassigns
ownership. Legacy JSON remains decodable and the recovery snapshot retains these
optional fields. Canonical note files do not move when their map positions change.

Real drag tracking uses the initial mouse-down point for its grab offset and the
current event for the drop indicator. The same path handles free placement and
subtree ownership changes; Escape cancels. AppKit context menus finish closing
before beginning inline editing. Structural changes preserve overview focus, and
the library window forwards overview command equivalents only when neither the
topic editor nor the shared note editor is active.

At an 811-point content width, the outline column begins 52.5 points from the
content edge. The live wrapper is capped at 872 points, with 105 points total
horizontal inset. Single-line node heights are exactly 62/50/44 points for root,
first level and deeper map nodes; wrapped text uses actual layout line counts.

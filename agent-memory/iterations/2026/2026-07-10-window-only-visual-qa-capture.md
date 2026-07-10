# Window-only Visual QA Capture

## Scope

- Baseline: `03c8bdd Cache loaded Notes navigation`
- Correct the Apple Notes comparison input without changing Mudsnote UI or behavior.

## Finding

- `screencapture -l` could return a full-screen-sized image while the harness treated it as a window image.
- The previous fallback crop used the Core Graphics window `y` value as a top coordinate; in this capture chain it required bottom-to-top conversion and removed about `44pt` of titlebar content.
- These two issues produced incorrect point metrics and draw scales even when the screenshot looked usable.

## Implementation

- Normalize every capture through the reported window bounds.
- Detect direct-window captures by aspect and backing-scale agreement.
- Fall back to a full-screen crop when direct capture is unavailable.
- Convert fallback `y` with `screen.maxY - (y + height)` and preserve the window's point size in PNG metadata.
- Record `direct-window` or `screen-crop` in visual-QA metadata.
- Automatically terminate the isolated QA app when activation or capture fails.

## Verification

- `bash -n scripts/visual_notes_qa.sh` passed.
- Offline replay against a previously validated full-screen capture produced the exact expected `1420x860pt / 2840x1720px` window image.
- Visual inspection confirmed the traffic lights, full titlebar, three panes, and bottom window border are all present.
- Visible-content sampling ratio was `0.9416`.
- Live capture could not run because the current desktop session exposed no frontmost application; the existing frontmost guard correctly stopped instead of emitting a misleading comparison.

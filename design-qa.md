# macOS header visual QA

final result: passed

Scope: pane-aligned header structure based on the supplied Obsidian crop;
this is an adaptation to Mudsnote's single-document editor, not a multi-tab feature.
The reference is dark; the requested light appearance is checked separately.

Compared the supplied reference and the final actual-window capture together.
Navigation occupies the list side; the current-document title and new-note action
occupy the editor side. Folder shortcuts remain in one compact row. At 921×613,
controls and content do not overlap, truncate unexpectedly, or leave extra footer chrome.
Current title follows folder/note selection. Search opens and Escape closes it.

The initial faded-effect preview was rejected as too transparent. Final correction
uses one full-strength native sidebar effect and tint-only children, preserving
native blur. Final capture: task visualization `material-review/05-balanced-header.png`.
Isolated window capture cannot prove desktop compositing; user acceptance of the
final material remains a subjective review, not implied by this structural QA.

Final `./scripts/verify macos pr`: 315 tests passed in five suites (19.374s).
Log: `/tmp/mudsnote-obsidian-final-pr.log`. No iOS or production installation.

## Flodo follow-up

Reference: https://flodo.fehey.com/zh, expanded app image, viewed together with
our actual preview. This reference guides material and restrained controls;
Obsidian still guides header structure. Backgrounds/content differ, so no pixel
match is claimed. Root native blur stays at full strength; child navigation tint
is reduced to 1.8%, and folder button borders show only on hover/selection.
Final window capture: `material-review/06-flodo-material.png` in task visualization.
Desktop-region inspection confirms background text is no longer legibly exposed;
its incidental overlapping window is excluded from the delivered screenshot.
Final `./scripts/verify macos pr`: 315 tests, five suites, 19.357s.
Log: `/tmp/mudsnote-flodo-final-pr.log`. Structural result remains passed;
material taste remains subject to the user's preview feedback.

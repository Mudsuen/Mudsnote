# macOS document workspace visual QA — 2026-09-14

Scope: macOS only. The user's Obsidian header reference defines control responsibilities; Flodo defines a restrained backdrop effect. Previous single-title-chip QA is superseded by this review.

## Verified interactions

The isolated native preview uses synthetic notes and its own defaults/support directories. Actual-window checks covered sidebar collapse/expand, foreground and background right-click tab opening, Command-T empty tabs, Control-Tab switching, Command-F document find, Shift-Command-F sidebar search, and edit/switch/back/undo/save. The last sequence was also checked by reading the saved Markdown; the temporary QA text was gone and the original body remained.

Tabs have independent buffers, undo managers, selection/scroll state, revisions and save ownership. Right-click actions retain their target URLs even if selection changes. Regression tests include simultaneous unsaved drafts, background open and undo isolation, save-failure close/retry, captured context actions, and trash read-only state. Empty tabs do not create files.

## Material and layout

Compared real desktop compositing against a synthetic blue/orange/purple/green background with repeated text. Clear Glass exposed too much background detail and lost contrast over dark windows. Fading a native effect to 78% also exposed sharp background text; that candidate was rejected. Final: one full-strength underWindowBackground/behindWindow effect following window activation, transparent child panes, opaque foreground text, and Reduce Transparency fallback.

The final desktop crop shows background color transitions across both panes while the repeated background text is no longer legible. It excludes the titlebar because an unrelated always-on-top Board panel overlapped that corner. The separate full-window image verifies header and tab geometry; isolated-window images do not prove backdrop compositing.

Local task artifacts (under the task visualization's material-review directory):
- 07-document-tabs.png: complete native window and two tabs.
- 08-background-compositing.png: real desktop content crop with color test backdrop.

No exact Flodo pixel match or user approval of the final visual taste is claimed. Open-tab layout is currently session-local; crash-recovery journaling and tab drag-reordering are not included in this change.

## Verification

- ./scripts/verify macos full: 321 ordinary tests in five suites and 8 Release performance tests in two suites passed. Log: /tmp/mudsnote-delivery-final.log.
- The real desktop crop checks the final full-strength material. The final delivery run also covers the startup editor undo-manager binding.
- No iOS build/device or shared production installation was used. The independent preview is not the installed application.

## Advisory review

The explicitly requested ChatGPT web review used separately verified Latest + far-right Pro. Sent once; the completed response was stable across three reads and pro-skills reports complete. The external answer's standalone sample project was not treated as integrated or locally verified code. Its useful findings were implemented and tested against this repository.

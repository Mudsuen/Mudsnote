# Mubu overview UI verification — macOS

## Confirmed scope

The user selected **only the overview mind map and outline**. The existing
library icon rail, search entry, note previews, metadata and thumbnails are
restored. The originally requested icon-only new-note action stays in the sidebar
heading. Mubu's sidebar is outside this comparison.

## Target and evidence

- Source visual truth: the desktop outline image and map animation in
  [Mubu's official quick-start guide](https://mubu.com/help/50).
- Outline image: `https://union-resource.oss-cn-shanghai.aliyuncs.com/admin/2025/07/22/687f583e50dff.png`
  (1080 × 669 source pixels, displayed at 1031.17 × 640 browser pixels).
- Map animation: `https://union-resource.oss-cn-shanghai.aliyuncs.com/admin/2025/07/22/687f58c0296de.gif`.
- Implementation: native Mudsnote Preview with disposable Markdown notes, isolated
  defaults and support directory under `/tmp/mudsnote-overview-qa-20261103`.
- Implementation screenshot paths: the computer-use tool emits inline captures
  in this chat and does not provide filesystem paths. No personal-note screenshots
  are checked into the repository.
- Viewports: 1100 × 760 and 896 × 580 AppKit points; screenshots are respectively
  2200 × 1520 and 1792 × 1160 pixels at 2×. Reference captures are 1226 × 720 browser
  pixels including the help page's image viewer. Compare the embedded reference
  content and the app at logical-point scale, excluding browser and macOS chrome.
- States: overview map, outline, folded branch, inline editor, navigation and zoom.
  The reference uses tutorial text and light appearance; the implementation uses
  synthetic life-area notes and the existing dark Mac workspace. These content,
  branding, native window chrome and appearance differences are intentional.
  This is a native UI adaptation; the evidence does not establish pixel identity.

## Comparison history

1. The initial grid differed in its main composition. Replaced it with one
   ownership tree shared by map and outline, then compared official and native
   captures in the same tool output.
2. Replaced generic overview cards and the large segmented switch with a purple
   root, tinted outlined topics, underlined text leaves, a compact top-right
   switch, breadcrumbs and a floating zoom panel.
3. The next captures showed an inset search field that did not fill the sidebar,
   and inconsistent outline bullet indentation. Bound the search row to the
   sidebar width, and gave branches and note leaves separate aligned bullet views.
4. After the scope reply, restored the original library presentation. Captures at
   896 × 580 points show the original icon rail and title/preview/metadata rows
   beside the retained Mubu outline. The new-note icon remains in the heading.
   The search action hides its redundant trigger while revealing the existing
   search field, so the extra compose icon does not widen the sidebar.

## Required fidelity surfaces

- Typography: native system/CJK fallback; 28-point outline title, 16-point outline
  rows, 15-point map topics/leaves, 18-point map root. The original library typography is outside the recreation scope.
  Hierarchy, wrapping and truncation are checked visually; the raster reference
  does not identify its exact font family.
- Layout rhythm: centered overview outline column with 24-point nesting;
  automatic map layout with curved branches and viewport fitting. The original
  library rail, search entry, 68-point note rows and native titlebar/document tabs
  remain outside the Mubu recreation.
- Colors: purple root and lavender branches/topic borders follow the reference;
  dark surfaces retain the existing app palette. Hover and keyboard focus have
  distinct feedback; the source's light palette is not used to judge dark colors.
- Assets: SF Symbols provide overview disclosure and toolbar icons.
  No reference illustrations or logos are required; text, branches and outlines
  are live AppKit content rather than bitmap substitutes.
- Copy/content: Mudsnote's name, areas, principles and original Markdown notes are
  preserved. New-note and overview-card creation remain separate actions. There
  are no nonfunctional share, account, cloud or membership controls.

## Functional verification

- `./scripts/verify macos ui`: 18 targeted tests cover creation, navigation,
  persistence, map/outline hierarchy, folding, inline edits, conflict protection
  and pointer feedback. The follow-up also checks that revealing search keeps the sidebar width and new-note icon. All 18 targeted tests pass on the scope-corrected source.
- Earlier real-window checks confirmed Chinese edits survive view switching and
  folding, and persist to the original note's current path after rename.
- The full PR gate is limited by pre-existing sidebar restoration and blocked
  autosave-navigation/exit tests, reproduced on unchanged `78ca90e`; see
  `agent-memory/incidents/2026-11-03-overview-verification-baseline.md`.
- Browser-console checks do not apply to the native AppKit implementation.

## Final acceptance

- No actionable P0/P1/P2 findings remain within the confirmed overview-only scope.
- Follow-up native-window verification at 896 × 580 points confirms the original
  rail and title/preview/metadata note rows. Clicking Search reveals the existing
  field while the sidebar remains exactly 238 points wide and the compose icon
  stays visible. Map/outline switching is functional with the restored shell.
- Earlier overview real-window checks passed at 896 × 580 points: an existing note opens
  from an outline bullet; pasted Chinese edits survive a switch to the map with
  focus retained; folding its parent saves and hides the edited subtree; expanding
  restores it; zoom changes from 100% to 110% and Fit returns to 100%; search finds
  the expected one document; icon-only ordinary creation opens the full editor
  without adding an overview node; returning to overview restores the hierarchy.
- File verification confirms the final edited text is on disk, and ordinary
  creation leaves the original six overview nodes unchanged.
- Full-view and focused sidebar/node/bullet regions were compared in combined
  reference/implementation screenshot outputs. No screenshot alone is treated
  as proof of persistence or keyboard behavior.
- P3 follow-up: exact font metrics and the light reference's rendering can differ
  from native macOS dark rendering. No additional visual iteration is required
  for the retained dark workspace.

final result: passed

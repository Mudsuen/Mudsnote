# Notes-style workspace design QA

## Accepted scope

The user's final direction supersedes exact Codex titlebar/list replication:
retain the original Apple Notes-style title, preview and metadata cards; refine
hover, click behavior and icon details; remove the white rail/list seam. No new
features or further decorative changes are part of this acceptance.

## Visual truth and privacy

- Codex reference: `/tmp/codex-clipboard-78864bd5-3b52-4aa0-a302-c0cc2643b836.png`, 1958 x 1456 pixels at 2x (979 x 728 points).
- Original Notes-style list: `/tmp/codex-clipboard-2b8d2426-5f22-41af-9fa1-a7d2b4ae4ea0.png`, 1792 x 1160 pixels at 2x (896 x 580 points).
- Final overview: `/tmp/mudsnote-codex-ui-transfer/notes-final-overview.png`.
- Final ordinary-note selection: `/tmp/mudsnote-codex-ui-transfer/notes-final-selected.png`.
- Full comparison input: `/tmp/mudsnote-codex-ui-transfer/notes-comparison-private.png`.
- Focused comparison input: `/tmp/mudsnote-codex-ui-transfer/notes-focused-private.png`.

The final actual-window captures were made on the coordinator laptop using the
unchanged Mini-signed candidate `411e360c387e8fd3b55bbcd88e192a3617ef59e1` and
synthetic fixture data. They are not Mini desktop captures. Both final captures
and both combined comparison inputs were opened and inspected in this review.
The supplied reference contains personal titles; its pixels and private combined
comparisons stay outside Git and must not be published to the website.

## Density, state and comparison method

The final window is 979 x 728 points / 1958 x 1456 pixels, in dark appearance.
The full comparison normalizes source and candidate to 979 x 728 at 1x and places
them in the same image. Focused rail/list crops use the same 2x-to-1x scale without
stretching their different widths. The Codex chat content is not a note-page
specification; the original Mudsnote image and the user's latest instruction
control the Notes-list hierarchy. System recording indicators are excluded.
Geometry checks also cover 896 x 580 and 1200 x 800; this report does not claim
new final live captures at those sizes.

## Comparison history

1. Initial Mudsnote showed duplicate navigation, oversized empty graph spacing,
   cards below the first viewport, and horizontal overflow. The shell and graph
   layout were adjusted while retaining original notes and save protection.
2. The first 979-point comparison identified P2 differences in sidebar width,
   new-note alignment, dim current-page title, titlebar spacing and legacy
   scrolling. The second laptop capture of candidate `94b0efe` confirmed two
   remaining active-window failures: wrapped/right-aligned new-note text and a
   dim title inside an oversized toolbar capsule.
3. Candidate `fdd9f9c` replaced the sidebar cell layout with explicit icon/label
   constraints and replaced the toolbar control with an unbordered static view.
   The coordinator verified single-line left alignment and readable title/no
   capsule, plus ordinary and overview creation with Chinese input and saving,
   back navigation and rail retention on list collapse.
4. The user then explicitly retained Notes-style multi-line rows and relaxed
   exact titlebar fidelity. Candidate `411e360` restored title/preview/metadata
   and 44-point thumbnails, differentiated hover/selection gray, unified the
   rail/list background, and removed its border/left corner seam. The final
   overview, selected-note capture and combined comparisons confirm these
   changes. The two corrected controls were not changed in this iteration.

## Five fidelity surfaces

- **Fonts/typography:** SF/PingFang; 14-point medium note titles with 12-point
  preview/metadata, retained Notes-style row hierarchy, readable static page
  title. The multi-line list is intentional, not a remaining drift from Codex.
- **Spacing/layout rhythm:** fixed narrow rail, independent scrolling list,
  retained 68-point note rows, visible overview cards, no whole-page horizontal
  scrollbar. The shared rail/list surface has no white seam. The note-editor
  divider remains intentional.
- **Colors/tokens:** neutral gray hover and a stronger gray selection; final
  selected-note screenshot shows a clear click state. Static title is readable;
  native overlay scrolling and the seam removal are confirmed. Exact native
  titlebar coloration is outside the user's narrowed fidelity requirement.
- **Image quality/assets:** real vector SF Symbols; note thumbnails retained.
  No chat/account/model imagery or generated raster UI was added. Source and
  candidate were compared at equal density.
- **Copy/content:** only note operations are represented. The sidebar new-note
  action creates an ordinary document; explicit overview new-note actions create
  cards. Synthetic note content is used for all final acceptance captures.

## Interaction and verification evidence

1. **Overview and ordinary navigation — passed:** on the laptop, selecting the
   sidebar fixture note opens the ordinary editor, Back returns to overview,
   collapse leaves the rail available, and overview has no horizontal overflow.
2. **Creation/editing — passed:** unchanged `fdd9f9c` controls were verified on
   the laptop with Chinese input and saving in both ordinary and card editors;
   ordinary notes were not added to the overview. Targeted Mini tests cover the
   four ordinary entry points and page-context restoration with pending edits.
3. **Notes list and pointer feedback — passed:** final actual click selection is
   visible in `notes-final-selected.png`; focused AppKit tests cover hover entry,
   exit and activation. The retained title/preview/meta and thumbnail behavior,
   sidebar controls and navigation passed the latest five related tests in
   `/tmp/mudsnote-notes-list-tests.log`. Tooltip/AX labels are retained; no claim
   is made of a separate final screenshot of every tooltip popup.

No full suite was run for this update. The explicit `mudsnote-ui` release route
records its actual scoped command/profile while retaining signature, provenance,
archive hash, candidate/installed fixture, and rollback gates. Six scoped
publisher-profile/host/no-change checks passed. Public website deployment is
not authorized and is excluded.

## Final assessment

No actionable P0/P1/P2 issue remains under the user's final Notes-style scope.
The coordinator's actual-window acceptance and the same-input comparisons agree.
Do not expand this change into further titlebar or decorative revisions.

final result: passed

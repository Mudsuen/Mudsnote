# Native workspace shell design QA

## Source, viewport and privacy

- Visual truth: `/tmp/codex-clipboard-78864bd5-3b52-4aa0-a302-c0cc2643b836.png` (Codex target, 1958 x 1456 pixels, 979 x 728 points, 2x).
- Original Mudsnote: `/tmp/codex-clipboard-2b8d2426-5f22-41af-9fa1-a7d2b4ae4ea0.png` (1792 x 1160 pixels, 896 x 580 points, 2x).
- Private reference pixels remain outside Git. They include personal titles and must not be uploaded publicly.
- Local evidence directory: `/Users/Donald/Documents/Codex/2026-10-28/01a18289-ba5a-7b41-9f74-57c9d1e4a0ee-mini/work/codex-ui-qa/`.
- First implementation: `candidate-979-first.png`, 1958 x 1456 pixels, native AppKit window without shadow. Synthetic notes only.
- Combined full-view input: `comparison-01-private.png`. Both captures were downsampled to 979 x 728 and placed together with neutral labels. The source is a chat page and the implementation is a note overview; compare shared shell structure and tokens, not unrelated content. System recording indicators and native activation differences are excluded.

## Comparison history and findings

1. Initial source inspection: repeated navigation and oversized multi-line rows in Mudsnote differed from the selected compact shell. The overview placed unassigned cards below empty areas and required horizontal scrolling. Reused only reviewed parts of the preserved layout branch; retained ordinary-versus-overview creation and hover fixes.
2. First actual 979 x 728 comparison found these actionable P2 differences:
   - Sidebar settled at 220 rather than approximately 238 points. The minimum/default now align at 238.
   - Ordinary new-note control was right-aligned. A leading-aligned native button cell now positions its real symbol and title consistently.
   - Top navigation buttons had excessive system spacing. A compact group now contains real back, forward and sidebar actions.
   - Static page title appeared disabled. It now uses an enabled, non-interactive label host with labelColor.
   - Main scrollbar was a persistent bright legacy scroller. It now uses small overlay scrollers with autohide and no horizontal scroller.
   - Inner boundary began at 40 points. The shell/rail now preserve a 44-point header boundary.
3. The same signed `94b0efea865320f4d95d9cec9138885d051931b8` candidate was subsequently captured on the coordinator's unlocked laptop with isolated fixture data. Evidence: `/tmp/mudsnote-codex-ui-transfer/candidate-979-active.png` and `/tmp/mudsnote-codex-ui-transfer/comparison-final-private.png`. Both were opened together in this review. This does not bypass the Mini lock or require a new build on the laptop.
4. The active-window comparison confirms two remaining P2 findings: the sidebar new-note title wraps into two lines and sits at the right; the current-page title remains dim inside a large native toolbar capsule. These are not inactive-window artifacts. The coordinator verified sidebar note navigation to an ordinary page, Back to overview, independent rail during sidebar collapse, and corrected overlay scrolling.
5. Narrow corrective implementation: replace the sidebar button-cell layout with explicitly constrained icon/one-line label subviews and a single accessible button hit target; replace the toolbar control label with a transparent static-text view, disable item borders, and constrain its size. No other UI feature or navigation behavior was changed. Laptop verification of these two corrections is pending; they remain open P2 findings until new actual screenshots confirm resolution.

## Five fidelity surfaces

- Fonts/typography: system SF/PingFang, 14-point regular note rows and subdued group headings; 16-point static page title. Final active-window comparison of the two corrected controls is pending.
- Spacing/layout rhythm: independent 52-point rail, 36-point hit regions, 44-point rail rhythm, 238-point list, compact 32-point rows and a shared rounded content boundary. Targeted geometry checks cover 896 x 580, 979 x 728 and 1200 x 800; final rendered checks pending.
- Colors/tokens: neutral gray hover/selection, dark content surface, restrained borders. First comparison accepted the overall hierarchy; overlay scrolling is verified; corrected title/toolbar rendering still requires a new capture.
- Image quality: vector SF Symbols only, no generated raster assets. Note image attachments retain compact 18-point thumbnails and their original files. Reference screenshots are not product assets.
- Copy/content: chat/model/account controls are intentionally absent. Sidebar new note and explicit overview new card remain distinct. No personal reference titles were copied into fixtures or source.

## Interaction evidence

- `./scripts/verify macos ui`: 14 affected tests passed in `/tmp/mudsnote-codex-ui-round2.log`, including ordinary/overview creation, page-history restoration with pending Chinese edits, list keyboard navigation, conflict safety, compact attachments, hover and viewport boundaries. This is NOT a full-suite result.
- Devflow's explicit `mudsnote-ui` verification profile has six scoped tests covering profile restrictions, unchanged default commands, host checks and no-change suppression. Actual verification command/profile are recorded in signed provenance and the manifest; signature, hash, candidate/installed fixture and rollback gates remain intact.
- Pending actual pointer/keyboard checks on the same signed laptop candidate: back/forward boundary states, sidebar note navigation, normal new note, overview card edit/save, sidebar collapse, hover/selected/tooltip/focus, independent scrolling and ordinary-window dragging.

- Narrow correction tests: `codexShellCriticalControlsStaySingleLineAndUnbordered`, `codexShellSidebarActionKeepsHoverAndActivation`, and `ordinaryNewNoteLeavesOverviewWithoutAddingCard` (four entry cases) passed. Log: `/tmp/mudsnote-two-controls-tests.log`. No full suite was run.

## Remaining acceptance steps

1. Capture the new signed candidate on the coordinator laptop at 979 x 728 and verify the two open P2 controls against the same reference in one comparison input; add focused chrome/list crops.
2. Verify 896 x 580 and 1200 x 800 states, including collapse and inline editing without horizontal overflow.
3. Complete actual interaction checks and record post-fix evidence for every P2 above.
4. Only then mark this report passed, push main, publish the scoped verified bundle and install Mini. Laptop installation belongs to the coordinator. Do not publish the public website.

final result: blocked

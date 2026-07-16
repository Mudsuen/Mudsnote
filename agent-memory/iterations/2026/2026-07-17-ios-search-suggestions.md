# 2026-07-17 iOS Notes-style search suggestions

## Request

Continue the iPhone Apple Notes parity goal while preserving Mudsnote's quick-note and Markdown strengths. The user explicitly deferred further iPhone table work, so this iteration improves the previously identified search workflow instead.

## Baseline

- Branch: `main`
- HEAD: `26bb5e1`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Empty focused search now presents a single horizontally scrolling row of structured suggestions for pinned notes, notes with attachments, notes with checklists, and notes edited today.
- Suggestions reuse the existing immutable library metadata and Smart Folder predicates instead of injecting fake keywords into full-text search.
- Suggested results respect the existing All, Notes, and Inbox scope selector and sort by their real modification or memo timestamp.
- Selecting a suggestion dismisses the keyboard and shows matching note cards immediately; typing switches back to ordinary full-text and attachment OCR search without stale suggested results.
- Clearing typed search or the selected filter returns to the normal folders screen, and tapping outside search releases focus.
- Corrected the commercial-readiness checklist: provider conflict review and editor conflict recovery were already complete, while dedicated accessibility and iPad validation remain outside the current iPhone-only scope.
- Recorded the user's decision to defer further iPhone table-authoring expansion while preserving existing portable Markdown table support.

Apple documents suggested searches such as notes with drawings, alongside typed, image, and scanned-document retrieval. This iteration adopts that structured-discovery pattern using Mudsnote's truthful local metadata: <https://support.apple.com/en-au/guide/iphone/iphb8628c6b8/ios>.

## Verification

- `git diff --check`: passed.
- `jq empty iOS/Localizable.xcstrings`: passed.
- Focused structured-search unit and UI tests: passed.
- Runtime screenshot inspected at `/tmp/mudsnote-search-suggestion-ui-20260717/75B0158E-8830-42DB-A485-44493349DAA9.png`; the suggestions remain on one horizontal row, the selected filter uses the Notes yellow treatment, and the result card stays clear of the bottom command bar.
- Full single-device regression:
  - Command: `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,id=BA9A4203-C694-492A-9CD0-6B80E3BC6ED5' -derivedDataPath /tmp/MudsnoteSearchSuggestions -resultBundlePath /tmp/MudsnoteSearchSuggestionsFull-20260717.xcresult -parallel-testing-enabled NO test`
  - Result: 139 tests, 0 failures, 0 skipped.
  - Result bundle: `/tmp/MudsnoteSearchSuggestionsFull-20260717.xcresult`.
- Shut down all simulators after verification.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice still reported the phone as `unavailable` and rejected installation with error 1011. The app was therefore not installed in this iteration.
- Final combined Simulator and Release DerivedData measured 472 MB and was deleted after verification. The retained full result bundle measures 11 MB and the screenshot evidence 196 KB; no extra simulator or project-local build cache was created.

## Decisions

- Search suggestions are structured filters, not magic query strings, so their labels and results remain truthful.
- The same suggestion definitions drive file and Inbox memo matching, preventing UI-only filter drift.
- Keep suggestions in one horizontally scrolling row to preserve the compact command surface on iPhone.
- Further table UI is explicitly deferred by the user and is not part of the next automatic parity iteration.

## Next

- Retry installation and launch on MudsPhone when CoreDevice exposes it.
- Continue the next non-table iPhone Notes-parity or commercial-readiness gap.

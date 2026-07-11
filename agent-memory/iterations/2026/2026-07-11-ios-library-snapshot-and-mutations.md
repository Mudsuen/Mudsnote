# 2026-07-11 iOS library snapshot and coordinated mutations

## Request

Continue optimizing Mudsnote iOS toward commercial-release completion, focusing on performance and data safety after the durable capture baseline.

## Baseline

- Branch: `main`
- HEAD: `16ea1ad`
- The iOS worktree was clean at checkpoint; unrelated macOS editor changes appeared during this iteration and were intentionally excluded.
- Existing iOS baseline: 7 tests passed on the iPhone 17 simulator.

## Changes

- Replaced repeated recursive reader scans with one `MarkdownFileStore` actor inventory.
- Reports the exact Markdown note count independently of the 24-item recent-file presentation limit.
- Derives Inbox, Daily, Templates, Attachments, recent files, and conflict warnings from one consistent snapshot.
- Changed Inbox delete, pin, and tag actions to coordinate a fresh disk read before mutation, so external or iCloud appends are not overwritten by stale UI state.
- Centralized Inbox serialization in `InboxParser` so recovery markers survive every rewrite.
- Added regression fixtures for a library larger than the recent limit and for an external append immediately before an Inbox mutation.

## Verification

- Commands run:
  - `git diff --check`
  - `xcodebuild -project MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
  - Debug and Release simulator builds, followed by signed-app install and launch.
- Result: 9 tests passed; Debug and Release builds succeeded; installed app launched on the iPhone 17 simulator.
- Not verified: a live multi-device iCloud conflict race, very large real-world libraries, or real-device energy behavior.

## Decisions

- Keep the 24-item limit as presentation scope only; totals must come from the complete inventory.
- Treat visible memo IDs as optimistic references and resolve them against the coordinated current file before mutation.
- Preserve external changes rather than retrying a mutation against stale text when its target memo no longer exists.

## Next

- Avoid full-library rescans after capture when only Inbox changed.
- Add bounded attachment validation and real-device iCloud conflict-resolution UX.

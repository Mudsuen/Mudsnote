# 2026-07-11 iOS Inbox delta refresh

## Request

Continue moving the Mudsnote iOS companion toward commercial-release performance after physical-device installation.

## Baseline

- Branch: `main`
- HEAD: `3600051`
- Existing macOS worktree changes were present and were not edited or staged.

## Changes

- Cached the latest complete iOS library snapshot inside the file-store actor and invalidated it when the authorized root changes.
- Added an Inbox-only delta load that rereads and parses `Inbox.md`, updates its recent-file metadata and exact Inbox count, and preserves the last complete inventory for unrelated folders.
- Routed plain-text Inbox captures plus delete, pin, and tag mutations through the delta path.
- Kept attachment captures, Daily/recent targets, queue replay, initial load, and explicit user refresh on the complete recursive inventory path.
- Corrected the asynchronous performance harness to remove about 100 ms of XCTest expectation polling from every measured iteration.

## Verification

- A focused correctness test proves an unrelated external Markdown file is not discovered by the delta load and is discovered by the following complete inventory.
- Corrected iPhone 17 Pro / iOS 26.5 Simulator baselines:
  - 1,000-note complete inventory: about 0.014 seconds average.
  - Inbox delta refresh over the cached 1,000-note inventory: about 0.00011 seconds average.
  - Maximum 32 MiB attachment draft preparation: about 0.011 seconds average.
- Full suite passed twenty unit/performance tests and three end-to-end UI tests, zero failures.
- The continuous-capture UI test saved to Inbox, cleared the draft, preserved destination behavior, switched to Daily, and saved again.
- Release Simulator build succeeded and validated the embedded Widget and application bundle.
- The post-change source build was re-signed with the profile-matching development identity, replaced on the connected iPhone Air, and launched successfully; both the host App and `MudsnoteCompanionWidget` processes were observed alive.

## Decisions

- The delta path is deliberately narrow: it is used only when the changed file set is known to be Inbox-only.
- External changes elsewhere in the authorized library remain the responsibility of explicit/full refresh, so exact inventory and conflict detection are not inferred from stale cache state.
- Performance records from the earlier polling-based harness should not be compared directly with these corrected clock measurements.

## Next

- Add UI automation for attachment rejection and interrupted-write states.
- Run real-device photo, audio, speech, Widget, and App Shortcuts smokes with the phone unlocked.

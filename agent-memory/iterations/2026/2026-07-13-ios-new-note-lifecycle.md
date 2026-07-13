# 2026-07-13 iOS new note lifecycle

## Request

Continue matching Apple Notes' iPhone note-creation lifecycle while keeping
Mudsnote files portable and safe.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `6fd26e9`
- Concurrent macOS editor and test changes were preserved and excluded.

## Changes

- A standalone note's first useful line now becomes its Notes-style list title
  even when the user does not write an explicit Markdown H1.
- On the first successful save, generated `Untitled Note*.md` files are renamed
  to the inferred title with portable invalid characters replaced, whitespace
  normalized, names bounded, and collisions handled without overwriting.
- File renaming is best-effort after the durable content save; a rename failure
  keeps the saved original file rather than turning cosmetic naming into data
  loss.
- The editor now updates its live document identity after a first-save rename,
  so later autosaves, photos, files, scans, and attachment removal use the new
  path.
- Closing a newly created, still-empty note removes only its generated empty
  Markdown file and restores the library count, matching Apple Notes' treatment
  of abandoned blank notes.
- Quick Look automation now waits for the system-owned close control instead of
  assuming it appears in the same frame as the preview container.
- Added Simplified Chinese empty-note cleanup failure copy.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteNamingBuild`.
- Storage automation verified plain-first-line title inference, portable title
  renaming, collision-safe generated names, saved-content preservation, and
  empty generated-file cleanup.
- UI automation verified the renamed standalone note under All Notes and verified
  an empty note disappears after Done and sheet dismissal with the count restored.
- A transient Quick Look control-timing assertion was converted to an explicit
  wait and passed in focused rerun.
- Final full App and UI suite: 78 passed, 0 failed, 0 skipped (61 unit/integration
  and 17 UI tests), using `test-without-building` after the focused rebuild.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteNamingTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_17-50-59-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteNamingDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted again, but CoreDevice could not locate the
  still-`unavailable` MudsPhone; install/launch remains unverified.

## Next

- Build and validate the signed Release artifact, then install when the physical
  iPhone data connection returns.
- Continue the remaining Notes interaction and visual parity audit.

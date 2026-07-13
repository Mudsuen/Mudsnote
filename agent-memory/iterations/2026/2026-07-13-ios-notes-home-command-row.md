# 2026-07-13 iOS Notes-style home command row

## Request

Continue visually converging the iPhone library and capture entry points on
Apple Notes without removing Mudsnote's Quick Note capability.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `6053ff4`
- Concurrent macOS editor and test changes were preserved and excluded.

## Evidence And Changes

- Captured the running iPhone 17 Pro home screen before changing the layout at
  `/tmp/mudsnote-home-current.png`.
- The evidence showed three separate bottom surfaces: search, Quick Note, and New
  Note. The extra Quick Note circle broke the simpler Apple Notes silhouette.
- Quick Note now lives inside the search capsule beside voice capture while
  remaining a direct 44-point single-tap target with its stable automation ID.
- The bottom area now has two primary surfaces: one search/voice/Quick Note
  capsule and one New Note circle.
- New Note keeps the requested black monochrome symbol and now uses the Notes-like
  folder yellow background instead of a white primary surface.
- The root large navigation title is now `Folders`, matching the corresponding
  Apple Notes information architecture.
- Captured the settled result at `/tmp/mudsnote-home-notes-row-settled.png` and
  confirmed the full folder content, toolbar, and bottom controls render together.

## Verification

- Focused UI automation verified Search, Quick Note, and New Note share one
  horizontal center line, Quick Note remains before New Note, quick capture still
  submits and collapses, and standalone New Note still opens its full editor.
- Final full App and UI suite: 79 passed, 0 failed, 0 skipped (61 unit/integration
  and 18 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteBottomTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_18-01-30-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteBottomDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted again, but CoreDevice could not locate the
  still-`unavailable` MudsPhone; install/launch remains unverified.

## Next

- Build and validate the signed Release artifact, then install when the physical
  iPhone data connection returns.
- Continue screenshot-led Notes parity on the folder rows and library hierarchy.

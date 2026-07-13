# 2026-07-13 iOS document scanning

## Request

Continue Notes-style iPhone editor parity with a native document scanner while
preserving portable local Markdown storage.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `8fead2b`
- Concurrent macOS source and tests were preserved and excluded.

## Changes

- Added the system VisionKit document scanner to the full note editor toolbar.
- Multi-page scans are converted into a page-preserving PDF with aspect-fit page
  rendering and safe margins.
- The generated PDF uses the user-facing name `Scanned Document.pdf`, passes
  through the existing file-size validation and transactional attachment path,
  and is stored as a relative Markdown link under `Attachments/yyyy/mm`.
- Temporary scan directories are uniquely isolated and removed after success or
  failure without leaking their UUID into the final attachment name.
- Cancellation dismisses cleanly; scanner/PDF failures display an explicit
  recovery alert without discarding the current note draft.
- Camera purpose copy now covers both photo capture and document scanning.
- The scan action is capability-gated: unavailable in Simulator and enabled on a
  supported physical iPhone.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteScanBuild`.
- Focused PDF test proved a valid two-page PDF and empty-scan rejection; focused
  UI automation proved the scanner entry is present in the full editor.
- Full App and UI suite after the final filename refinement: 68 passed, 0 failed,
  0 skipped.
- Signed Release iphoneos build passed, including embedded widget validation, at
  `/tmp/MudsnoteScanDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled,
  then shut down; no iPad or additional simulator was used.
- Result bundles:
  - `/tmp/MudsnoteScanFocused.xcresult`
  - `/tmp/MudsnoteScanFullFinal.xcresult`

## Device status

- CoreDevice listed `MudsPhone` (`2C558043-5D29-531D-878B-F07C4F288D5D`) as
  `unavailable`.
- The signed app was therefore not installed or launched in this iteration; an
  install attempt correctly failed because CoreDevice could not locate the
  offline device, not because of signing or trust.

## Next

- Reconnect and unlock `MudsPhone`, install and launch the signed Release build,
  and exercise the real camera scan flow before marking device verification done.

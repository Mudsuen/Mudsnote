# 2026-07-03 - Active-window Visual QA

## Context

The Apple Notes comparison image is the main loop for desktop parity work. A captured Mudsnote window could appear inactive, which made toolbar tint, traffic lights, and window chrome harder to compare against the active Apple Notes reference.

## Change

- Updated `scripts/visual_notes_qa.sh` to explicitly activate Mudsnote immediately after opening the packaged app.
- Activated Mudsnote again after the launch delay before locating and capturing the library window.
- Kept the existing window selection, blank-image detection, and stitched comparison output unchanged.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- The generated comparison shows Mudsnote in active-window chrome.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.

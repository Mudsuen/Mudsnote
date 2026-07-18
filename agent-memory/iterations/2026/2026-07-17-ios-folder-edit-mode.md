# iOS Notes-style folder edit mode

## Scope

- Baseline: clean `main` at `76c0b2c` (`Prepare iOS 1.0 App Store metadata`).
- Continued the iPhone-only Apple Notes parity goal without adding or changing table authoring.
- Dedicated accessibility work and iPad validation remained out of scope.

## Product audit

- Used Apple's current iPhone Notes folder guide and official iOS 26 screenshot as the reference surface.
- Rejected a simulator screenshot of the system Notes app because Notes was not installed in that simulator.
- The highest-impact visible gap was folder-management discoverability: Mudsnote exposed lifecycle actions only through long press, while Notes provides an explicit `Edit` entry beside New Folder.
- Compared the official reference and the implemented management state side by side. The toolbar hierarchy, non-navigating management rows, and visible action affordance align while Mudsnote keeps its dark theme, smart folders, quick-note entry, and Markdown model.

## Changes

- Added a Notes-style `Edit` / `Done` folder-management mode to the library home toolbar.
- Clears active search state before entering management mode so folder actions are presented against a stable list.
- Custom and smart folder rows stop navigating while management mode is active.
- Custom folders expose a visible action menu for subfolder creation, rename, valid moves, and deletion.
- Smart folders expose visible edit and delete actions.
- Preserved the existing long-press and swipe lifecycle actions in normal mode.
- Added Simplified Chinese localization for `Edit`.
- Added an end-to-end UI test that enters management mode, validates the action menu, renames `Projects` to `Work`, exits with `Done`, and confirms normal navigation is restored.

## Verification

- Focused folder-management UI test: 1/1 passed.
- Full single-destination regression on iPhone 17 Pro, iOS 26.5, simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`: 146/146 passed, with 100 unit tests and 46 UI tests, zero failures and zero skipped.
- Parallel testing remained disabled and no additional simulator was created.
- Generic iOS Release archive succeeded at version `1.0 (1)`.
- App and Widget passed strict code-sign verification; both privacy manifests were embedded; no App Intents/SSU archive warning was emitted.
- Physical device `MudsPhone` / iPhone Air remained `unavailable` to CoreDevice. DDI inspection and installation both stopped with CoreDevice error 1011 before reaching the phone; this is a device-service connectivity state rather than an app-trust failure.

## Storage

- Peak temporary artifacts: 478 MB DerivedData, 20 MB archive, 4.8 MB audit images, and about 524 KB logs.
- All artifacts were kept under `/tmp`; the sole simulator was shut down and temporary artifacts were removed after verification.

## Next

- Continue with the next highest-impact iPhone Notes parity gap, keeping Mudsnote's quick capture and Markdown advantages and leaving table authoring unchanged.

# 2026-06-08 iOS companion v0.3

## Request

参照 `/Users/Donald/Downloads/Mudsnote_iOS_Companion_v0.3_Dark_Codex_Package/` 制作 iOS app。

## Baseline

- Branch: main
- HEAD: bde053d
- Dirty files before work: none from `git status --short`

## Changes

- Created a new standalone iOS Xcode project under `iOS/`.
- Implemented folder authorization, Markdown folder initialization, pending write queue, append-only Markdown writes, attachments, audio recording, App Intents, bottom capture console, Inbox stream, preview, recent/search, and settings/status views.
- Kept the iOS app separate from the current macOS SwiftPM targets so existing Mudsnote packaging remains untouched.
- Simplified Quick Capture after simulator review: removed the sheet title/subtitle/cancel header, blended the text editor into the panel surface, reduced the default detent to 32%, and moved the home capture pill above the system tab bar so the controls no longer overlap.

## Verification

- Commands run:
  - `python3 /Users/Donald/Downloads/Mudsnote_iOS_Companion_v0.3_Dark_Codex_Package/scripts/validate_package.py`
  - `swift test`
  - `./scripts/package_app.sh`
  - `xcodebuild -list -project iOS/MudsnoteCompanion.xcodeproj`
  - `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -parse-as-library -typecheck ...`
  - XcodeBuildMCP `build_run_sim` on iPhone 17 / iOS 26.5
- App/page/package actually opened: macOS packaged app was rebuilt at `/Applications/Mudsnote.app`; iOS app launched on Simulator as `app.mudsnote.companion`.
- Result: Package input complete, macOS tests passed, macOS package succeeded, iOS source type-check passed, Xcode project lists the `MudsnoteCompanion` scheme, simulator build/install/launch succeeded.
- iOS smoke: first screen rendered the Markdown folder onboarding page; tapping `选择文件夹` opened the system Files picker. Screenshot: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/screenshot_optimized_9dc2cd73-a59e-4d2c-89fb-1c2be1af36b3.jpg`.
- iOS UI iteration smoke: bottom capture pill rendered above the tab bar with clear separation. Screenshot: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/screenshot_optimized_289537d7-bb75-4366-9f66-ba47af9f0719.jpg`.
- iOS Quick Capture smoke: opening the capture sheet showed no `Quick Capture` / `Inbox` / `Cancel` header, and the text editor was visually integrated into the panel. Screenshot: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/screenshot_optimized_865204eb-036d-49c2-b9d4-4280b9272689.jpg`.
- iOS text capture smoke: typed `Polish the iOS capture panel.`, sent it, and the Inbox stream rendered the new memo block dated `2026-06-08 22:16`.
- Not verified: Image capture, audio capture, target switching, and real-device signing flow in this iteration.

## Decisions

- Minimum target is iOS 17 as the PRD allows iOS 17 fallback while keeping the implementation SwiftUI-first.
- Widget and Share Extension source boundaries are present, with App Intents implemented in the app target first.

## Next

- Promote the widget and share extension references into real extension targets once signing/app group identifiers are finalized.
- Add a real iOS unit-test target to the Xcode project so `MudsnoteCompanionTests` runs under `xcodebuild test`.
- Continue checklist verification for image capture, audio capture, target switching, Dynamic Type, and permission-loss/conflict states.

## 2026-06-09 follow-up

- Replaced the home bottom one-line capture pill with a custom bottom navigation bar that keeps Inbox, Recent, and Settings visible while placing `添加笔记` as a centered plus action.
- Added a plus confirmation menu for text, image, and audio capture routes.
- Added `mudsnote://capture` URL scheme and verified it opens the capture sheet from the Simulator Home screen.
- Promoted the widget reference into a real `MudsnoteCompanionWidget` target and embedded `MudsnoteCompanionWidget.appex` in the iOS app bundle. The widget is a lightweight quick-capture launcher using `mudsnote://capture`.
- Added App Shortcuts for Capture, Append Inbox, and Append Daily, plus `updateAppShortcutParameters()` registration during app init.
- Added a small system-entry request bridge so Shortcut capture requests can open the capture sheet when the app becomes active.
- Set Debug `ENABLE_DEBUG_DYLIB = NO` for the app and widget targets to keep system-integration runtime lookup closer to release packaging.

Verification:

- `xcodebuild -list -project iOS/MudsnoteCompanion.xcodeproj` lists `MudsnoteCompanion` and `MudsnoteCompanionWidget`.
- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build` passed.
- XcodeBuildMCP `build_run_sim` passed on iPhone 17 / iOS 26.5.
- Simulator UI smoke verified the custom bottom nav and plus menu; tapping `文字快记` opened the simplified capture sheet.
- Package inspection found both `Metadata.appintents` and `PlugIns/MudsnoteCompanionWidget.appex` inside the built app.
- Shortcuts app indexed the `Mudsnote` actions (`Capture`, `Append Inbox`, `Append Daily`), but running `Capture` inside the simulator still failed with `LNActionForAutoShortcutPhraseFetchError Code=1 "Couldn't find AppShortcutsProvider."` after provider rename, explicit init, app uninstall/reinstall, Shortcuts restart, and Debug dylib disabling. Treat this as the remaining system-integration blocker to retest on a real signed device or a fresh simulator runtime.
- `swift test` passed with 53 tests.
- `./scripts/package_app.sh` passed and packaged `/Applications/Mudsnote.app`.

## 2026-06-09 refinement

- Restored the home shell to native SwiftUI `TabView` and moved capture to a plain transparent bottom-right plus button.
- Removed the unused bottom one-line capture entry source from the Xcode project so the old overlapping UI cannot be reintroduced accidentally.
- Changed the plus action to open text capture directly, with no intermediate route picker.
- Kept image and audio actions inside the simplified Quick Capture sheet, and changed the editor placeholder/body font to system `.body`.
- Changed attachment Markdown output to portable standard links:
  - Images: `![Image](Attachments/yyyy/mm/file.ext)`
  - Audio: `[Audio](Attachments/yyyy/mm/file.m4a)`
- Added local preview support for standard image/audio Markdown attachment lines while preserving legacy `![[...]]` parsing.
- Added `Capture Image` and `Capture Audio` App Intents and default App Shortcuts.
- Reworked the small widget into a 2x2 launcher: text occupies the top span, audio and image each occupy one bottom tile. The circular accessory remains a text quick-capture launcher.
- System image routes now open Quick Capture with the image tool selected; the user taps the image icon to invoke the iOS file picker. Directly presenting the file picker from a URL callback was unreliable in Simulator.

Verification:

- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -parse-as-library -typecheck ...` passed.
- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build` passed.
- `swift test` passed with 53 tests.
- XcodeBuildMCP `build_run_sim` passed on iPhone 17 / iOS 26.5.
- Simulator UI smoke verified the native tab bar, transparent bottom-right `添加笔记` button, direct text capture sheet, and no header/cancel block in Quick Capture.
- Text smoke wrote `Codex text capture smoke test` and Inbox rendered the new memo dated `2026-06-09 12:16`.
- Audio smoke recorded, stopped, attached `Audio`, saved, and wrote `[Audio](Attachments/2026/06/audio-20260609-121635.m4a)` to `Inbox.md`; the referenced `.m4a` exists under the same `Attachments/2026/06/` folder.
- Image system-entry smoke: `mudsnote://capture?mode=image` opened Quick Capture, and tapping the image icon presented the iOS Files picker. Screenshot: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/screenshot_optimized_0d6cefef-fba1-4eaf-bbce-44c9364fca73.jpg`.
- Package inspection found `PlugIns/MudsnoteCompanionWidget.appex` and `Metadata.appintents/extract.actionsdata`; metadata contains `Capture`, `Capture Image`, `Capture Audio`, `Append Inbox`, and `Append Daily`.
- `./scripts/package_app.sh` passed and packaged `/Applications/Mudsnote.app`.

Remaining checks:

- The Simulator Files picker is not exposed well to runtime accessibility snapshots, so image file selection was verified to the picker boundary rather than selecting a real image end-to-end in automation.
- Shortcuts direct execution should still be retested on a real signed device or fresh simulator because the previous simulator runtime had an App Shortcuts provider lookup failure despite generated metadata.

## 2026-06-09 Notes-style directory pass

- Removed the bottom tab bar entirely and kept only the floating bottom-right `添加笔记` button.
- Removed the Inbox top-right refresh button; Inbox and directory/list screens now rely on native pull-to-refresh.
- Replaced the home shell with a Notes-style `Folders` screen using a native grouped `List` and top search field.
- Added folder rows and counts for `All Notes`, `Inbox`, `Daily`, `Templates`, and `Attachments`.
- Added a `Tags` section populated from parsed Inbox tags, matching the Notes pattern of using tags as a directory/filter surface.
- Added lightweight folder statistics in `AppModel`/`MarkdownFileStore` without changing the plain Markdown storage model.
- Switched folder navigation from value-based routing to direct destination `NavigationLink`s after Simulator showed the value link rows were exposed as buttons but did not navigate reliably.

Verification:

- Official Notes references checked: Apple documents folders/subfolders in the folders list, search in Notes, and tags/Smart Folders as cross-folder filtering surfaces.
- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -parse-as-library -typecheck ...` passed.
- `swift test` passed with 53 tests.
- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build` passed.
- XcodeBuildMCP `build_run_sim` passed on iPhone 17 / iOS 26.5.
- Simulator UI smoke verified the `Folders` directory, no bottom tabs, no top-right refresh button, the right-bottom `添加笔记` action, and successful navigation into Inbox.
- `./scripts/package_app.sh` passed and packaged `/Applications/Mudsnote.app`.

## 2026-06-10 Notes visual polish and capture tools

- Reworked the home directory again to closely match the provided iOS Notes screenshot: light gray background, white rounded folder cards, yellow folder icons, tag chips, top `folder.badge.plus`/`Edit`, and a bottom floating search/mic/new-note bar.
- Removed the global forced dark color scheme so the Notes-style directory has correct black text and status contrast.
- Changed the small widget to pure icon tiles with no visible text.
- Changed image capture to use PhotosPicker; image route and image buttons now open the photo library rather than the Files picker.
- Added a compact format toolbar in Quick Capture matching the provided toolbar reference: `#`, image, bold, list, and more actions.
- Added format insertion helpers for `#tag`, `**bold**`, bullet lists, quote, checklist, and inline code.
- Added Speech framework transcription after voice recording with `NSSpeechRecognitionUsageDescription`; the app keeps the temporary audio file long enough for transcription and then cleans it up.
- Added an in-app audio playback row for Markdown audio attachments using `AVAudioPlayer`.
- Added row swipe actions on Inbox cards: leading swipe adds a default `#tag`; trailing swipe deletes or pins by rewriting `Inbox.md`. Folder-style file lists expose matching swipe affordances where safe.

Verification:

- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -parse-as-library -typecheck ...` passed.
- `swift test` passed with 53 tests.
- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build` passed.
- XcodeBuildMCP `build_run_sim` passed on iPhone 17 / iOS 26.5.
- Simulator screenshot verified the light Notes-style directory and bottom search/mic/new-note bar. Screenshot: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/screenshot_optimized_ae90c6b5-7d30-4c22-99f2-029582f99dc8.jpg`.
- Simulator smoke verified new note opens Quick Capture and shows the `# / image / bold / list / more` format toolbar.
- Simulator smoke verified the image button opens the iOS Photos picker. Screenshot: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/screenshot_optimized_afc7f262-9052-4fcf-9ef2-e00ab5369aa7.jpg`.
- `./scripts/package_app.sh` passed and packaged `/Applications/Mudsnote.app`.

Remaining checks:

- Speech transcription was compiled and permission-wired but still needs real-device audio validation; Simulator speech/microphone behavior may not reflect iPhone behavior.
- Widget visual verification in the Home Screen gallery remains manual; the widget target builds and the source no longer renders text in the small/circular widgets.

## 2026-06-10 Mudsnote visual unification pass

- Kept the Notes-inspired directory information architecture, but moved the home screen back into Mudsnote's own dark visual system.
- Restored the forced dark color scheme so the home, Inbox, preview, and capture surfaces share one contrast model.
- Changed the directory title from `Folders` to `Library` and removed the empty `Edit` button to avoid a dead interactive control.
- Reworked home folder cards, section headers, folder rows, tag chips, and the bottom search/mic/new-note bar to use `MudsnoteColors`, rounded dark cards, muted separators, and compact rounded typography.
- Added an inline clear button and search submit behavior to the bottom search field.
- Converted tag-filter memo lists to the same card/list structure as Inbox and gave them the same leading `Tag` and trailing `Pin`/`Delete` swipe actions.
- Tightened recent-file row typography and padding so folder lists do not visually diverge from Inbox memo cards.

Verification:

- `xcrun swiftc -target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path) -parse-as-library -typecheck ...` passed.
- `swift test` passed with 53 tests.
- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build` passed.
- XcodeBuildMCP `build_run_sim` passed on iPhone 17 / iOS 26.5.
- Simulator screenshot verified the unified dark Library home with folder groups, tags header, and bottom command bar. Screenshot: `/var/folders/hs/3lbg6xjs1kdc4xftnflt94y80000gn/T/screenshot_optimized_c370e472-d479-4b32-9b9b-0b342e9a4a7f.jpg`.
- Simulator smoke verified new-note opens Quick Capture directly and exposes the format toolbar.
- Simulator smoke verified Inbox navigation from Library, trailing left-swipe actions expose `Pin` and `Delete`, and leading right-swipe exposes `Tag`.
- `./scripts/package_app.sh` passed and packaged `/Applications/Mudsnote.app`.

Remaining checks:

- Real-device checks are still needed for microphone permission, speech transcription quality, and widget gallery appearance.

## 2026-06-14 real-device signing and smoke script

- Added the real Xcode signing team `3JA29GL46S` to the iOS app and widget targets. The certificate label still contains `95L8JU9A4K`, but `xcodebuild` uses `3JA29GL46S` for account/team provisioning.
- Added `scripts/device_smoke.sh` to build, install, and launch MudsnoteCompanion on the connected iPhone using a local `build/DeviceDerivedData` path.
- Updated `.gitignore` for local Xcode/device build artifacts.

Verification:

- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -configuration Debug -destination 'id=00008150-001C204022E2401C' -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=3JA29GL46S build` passed.
- Xcode generated development provisioning profiles for `app.mudsnote.companion` and `app.mudsnote.companion.widget`.
- `xcrun devicectl device install app --device 00008150-001C204022E2401C .../MudsnoteCompanion.app` installed the app on MudsPhone.
- `./scripts/device_smoke.sh` passed end-to-end: build, install, and launch on MudsPhone.

Remaining checks:

- UI interaction beyond successful launch, widget gallery appearance, microphone permission, and speech transcription still need manual or XCUITest follow-up on device.

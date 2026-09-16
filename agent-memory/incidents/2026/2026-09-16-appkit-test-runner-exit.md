# Swift Testing exited before finishing AppKit regressions

## Evidence

The default SwiftPM runner returned 0 while an AppKit test was still active,
without a final summary. An LLDB breakpoint on `exit` located the call in
`swift_task_asyncMainDrainQueue`, through the generated async runner. This
previously hid tests after sheet/toolbar interactions. The replacement runner
completed all 312 selected tests and exposed legacy fixture failures.

## Scoped risk review

The verification change is macOS-only. `verify_macos.sh` still builds the same
SwiftPM test bundle and preserves the PR/full performance filters. A synchronous
AppKit host loads that bundle, runs Swift Testing's existing entry point, and
services AppKit events until the test framework exits with its own result. It
adds no application startup code, signing changes, credentials, real note paths,
or persistent user defaults. All test data remains under synthetic temporary
roots. There are no XCTest test cases in this package.

The custom host imports the toolchain's Testing framework and uses its SwiftPM
entry point, so a future toolchain change may require an update. Build/load
failures are fatal; there is no fallback claiming success. Rollback is reverting
the two runner files. No release or iOS operation is involved.

## Recovery

The prior installed macOS application is retained locally at
`/tmp/Mudsnote-before-titlebar-20260916.app`. Quit Mudsnote before restoring that
bundle to `/Applications/Mudsnote.app`. Application recovery does not roll back
notes or settings.

## Verification

`./scripts/verify macos pr` completed all 312 selected tests in 5 suites with
zero failures. The host dispatches native AppKit events, so the floating browser
focus check runs rather than being bypassed. Toolbar customization fixtures use
unique toolbar identifiers to prevent AppKit's family synchronization from
mutating sibling test windows. Existing archive-search opt-in and unified
editor-title behavior remain covered.

`./scripts/verify macos live` built, signed, installed, and launched the macOS
candidate. Native-window inspection verified tree/list insets, seamless top
chrome, borderless compose control, lighter tabs, and opening/closing an empty
tab. Tree/list switching retained the current note and editor first responder.

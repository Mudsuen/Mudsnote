# 2026-07-15 iOS actionable content detection

## Request

Continue the full iPhone Apple Notes parity goal without weakening Mudsnote's
local-first Markdown boundary, quick capture, or complete editing workflow. This
iteration closes the everyday reading gap where Apple Notes recognizes actionable
content even when the author did not manually create a link.

## Baseline

- Branch: `main`
- HEAD: `cef0396`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Added bounded Foundation data detection to rendered Markdown lines.
- Bare email addresses open through `mailto:` and phone numbers through `tel:`.
- Detected street addresses open through an Apple Maps query URL.
- Detected content receives the Notes-like yellow underlined link treatment.
- Existing Markdown links retain their authored destination; detection only supplies
  a destination when the rendered content does not already have one.
- Detection modifies only the in-memory attributed reading surface. It never writes
  generated links or markers into the Markdown file.
- Added focused unit coverage for email, phone, address, underline styling, and
  explicit-link precedence.
- Added iPhone UI coverage proving detected email and phone content is exposed as
  tappable links in the normal half-sheet reader.

Apple's iPhone Notes guide states that street and email addresses, phone numbers,
dates, and similar data are automatically underlined and actionable. This iteration
implements the address, email, and phone subset without changing portable Markdown:
<https://support.apple.com/en-gb/guide/iphone/iph908d1558b/ios>.

## Verification

- `git diff --check`: passed.
- Focused parser and iPhone UI tests: passed.
- Runtime screenshot inspected at
  `/tmp/mudsnote-data-detection-ui/90345C4C-F901-4FDE-B19B-2C9B874FE51A.png`;
  email and phone links render with stable wrapping and do not disrupt the attachment
  card, table, or half-sheet layout.
- Full single-device regression:
  - Command: `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,id=BA9A4203-C694-492A-9CD0-6B80E3BC6ED5' -parallel-testing-enabled NO test`
  - Result: 132 tests, 132 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/Donald/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Logs/Test/Test-MudsnoteCompanion-2026.07.15_09-26-06-+0800.xcresult`
- Shut down all simulators after verification.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and
  `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone
  (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice reported the phone as
  `unavailable` and rejected installation with error 1011. The app was therefore not
  installed in this iteration.

## Decisions

- Actionable-content detection is a reading concern and must not rewrite Markdown.
- Authored Markdown links always win over automatic detection.
- A future locked-note feature must use real encryption and a deliberate key lifecycle;
  a view-only privacy curtain would be misleading and is not an acceptable substitute.

## Next

- Continue the current-state iPhone Notes parity audit and implement the next
  high-value everyday workflow gap.
- Treat date actions and encrypted locked notes as separate design scopes rather than
  extending detector behavior with undocumented or misleading shortcuts.
- Retry direct installation and launch verification when MudsPhone becomes available
  to CoreDevice.

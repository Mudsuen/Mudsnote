# Compact macOS chrome: review and ablation

Scope: macOS implementation and native verification. Starting commit:
`1237e3e84631cdb159e7ca44f062f173d3ad2049`.

## Independent Pro review status

A controlled 139-file project snapshot (macOS, shared core, iOS, tests, scripts,
and documentation) was prepared for the explicitly requested whole-project
review. The user authorized a retry, and Latest + Pro were independently verified
before the successful send. The complete response was captured and validated
with three stable reads on 2026-09-16:
https://chatgpt.com/c/6aaa2ae6-13b0-83e9-a3a6-5c6ae6d88fc6

The reviewer used a Linux environment; its proposed AppKit patches were not
runtime proof. Existing native ablation results remain authoritative for chrome.
Locally adopted corrections: exclusive new-note creation with collision retry;
commit tab identity only after successful load; remap inactive tabs on folder
moves; include URLs in tab redraw signatures; explicit manual-CI platform input.
A separate local search regression normalizes whitespace before filtered search.

Deferred recommendations: incremental tab view reuse, asynchronous session-state
refactoring, filesystem-event reconciliation, aggregate index memory budgeting,
and cross-platform trash semantics. These need separate behavioral evidence and
are not represented as resolved by this change.

Risk review: exclusive creation changes only new-note writes, preserving existing
files when another process wins a filename. Update-note replacement is unchanged.
CI defaults to macOS and still uses isolated verification fixtures; no cloud run
or iOS build is implied. All failure experiments use temporary notes and defaults.

The retained local review bundle, prompt hash, attempt receipt, and recovery
information are under `/tmp/mudsnote-pro-review-20260916`.

## Local findings and fixes

- The native unified toolbar reserved 52pt for 30pt tab chrome. Unified Compact
  reduces that to 40pt without shrinking tab hit targets.
- The editor reserved 34.75pt before its first text line for creation metadata.
  A 16pt date row with a 4pt gap and 4pt top offset reserves 24pt. Date typography
  is secondary, with the document title retaining the stronger hierarchy.
- The compose action followed the split tracking separator and therefore lived
  over the editor. It now precedes the separator, at the top of the sidebar.
- The search wrapper had no explicit size constraints and was compressed by
  AppKit's compact toolbar. Explicit 28pt wrapper / 24pt search geometry keeps
  the field inside its wrapper. Reducing search size alone does not lower the
  toolbar; it is retained for containment and visual alignment.
- Export removed the destination before reading the source. Exporting to the
  original path destroyed the source; a missing source destroyed an existing
  export. A title edit could also rename the source after its URL was captured.
  Resolve the URL after save, treat export-to-self as a no-op, then read before
  atomic destination replacement. Three reproductions failed before the fix.
- The Release test host built modules without `-enable-testing`, breaking
  `@testable` imports. Enable testing only for verification builds. Installed
  app packaging continues to use its separate production scratch directory.

## Ablation experiment

`LibraryChromeAblationTests.chromeFactorAblation` runs all eight combinations
of compact toolbar, compact search geometry, and compact metadata at 896pt and
1100pt window widths, with synthetic notes. It measures actual AppKit frames;
these are layout measurements, not a user study or claimed task-time gains.

| Variant | Toolbar height | Gap below tab | First text origin from window top |
| --- | ---: | ---: | ---: |
| Baseline | 52pt | 11pt | 86.75pt |
| Compact toolbar only | 40pt | 5pt | 74.75pt |
| Compact search only | 52pt | 11pt | 86.75pt |
| Compact metadata only | 52pt | 11pt | 76pt |
| Compact toolbar + metadata | 40pt | 5pt | 64pt |
| All three | 40pt | 5pt | 64pt |

Both widths gave the same vertical measurements. All sixteen combinations
retained the current note, text, and editor first responder through tree/list
switching. Reproduce with:

```sh
MUDSNOTE_CHROME_ABLATION_OUTPUT=/tmp/chrome-ablation.json ./scripts/verify macos pr
```

The export fix additionally has a removal comparison: all three targeted safety
cases fail on the original implementation and pass with the atomic-export fix.

## Scoped risk review

This is a native presentation change plus a narrower export failure surface.
No storage migration, file-format change, signing/entitlement change, iOS build,
or external publication is included. Export tests and measurements use isolated
UserDefaults suites and temporary files. The verification compiler flag changes
test builds only. The recoverable installed baseline is retained at
`/tmp/Mudsnote-before-pro-review-20260916.app`.

## Verification results

`./scripts/verify macos full` passed: 315 regular tests passed (the opt-in
ablation test is skipped in the normal run), then all 8 selected Release
performance tests passed. The separately enabled ablation run passed all 313
then-current tests and recorded the sixteen native-layout measurements above.
The three export safety tests each failed before the export change and passed
after it. No iOS build or installation was performed.

`./scripts/verify macos live` built, installed, and launched the candidate.
Real-window inspection confirmed compose is left of the sidebar divider, the
search focus ring is intact, and opening/closing a blank tab restores the prior
note. Collapsing and restoring the sidebar retained the editor first responder
and kept toolbar controls visible.

## Pro follow-up verification

`./scripts/verify macos full` passed 317 discovered tests (316 executed plus
one optional ablation skip) and all 8 Release performance tests. The deterministic
creation test inserts a competing file after the availability check and verifies
both bodies survive at distinct URLs. Filtered-search whitespace had three
failing expectations before correction and passed afterward. Platform-routing
fixtures passed; the manually dispatched cloud workflow itself was not run.

The first broad run exposed a test-fixture filename assumption and a transient
floating-search result failure. The fixture now derives the actual generated
name; floating search passed both focused and subsequent full verification.
Tab-load and folder-remap changes passed the existing AppKit suite; exhaustive
injected async-load failure coverage remains a follow-up, not claimed evidence.

The follow-up candidate passed `./scripts/verify macos live` and was installed.
A real-window check confirmed compact chrome and sidebar compose placement.
Opening and closing an empty tab restored the original selected document and
editor first responder. No user-note content was changed by this interaction.

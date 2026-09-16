# Compact macOS chrome: review and ablation

Scope: macOS implementation and native verification. Starting commit:
`1237e3e84631cdb159e7ca44f062f173d3ad2049`.

## Independent Pro review status

A controlled 139-file project snapshot (macOS, shared core, iOS, tests, scripts,
and documentation) was prepared for the explicitly requested whole-project
review. Live selection was verified as Latest and Pro independently. The single
Send attempt left the page displaying the original draft at chatgpt.com/ with
no conversation or assistant answer. The pro-skills one-send rule prevents an
unapproved retry; the user was asked to authorize one retry. No Pro conclusion
has been received or incorporated. This record is local evidence, not a claim
that the requested independent review completed.

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

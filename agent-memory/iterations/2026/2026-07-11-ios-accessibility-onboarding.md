# 2026-07-11 iOS accessibility onboarding

## Request

Continue Mudsnote iOS commercial accessibility work with installed-app Dynamic Type pressure testing.

## Baseline

- Branch: `main`
- HEAD: `cc4bfda`
- Standard-size English and Chinese onboarding rendered correctly.
- At `accessibility-extra-extra-extra-large`, the fixed stack truncated every major text block and compressed the primary action.

## Changes

- Detects accessibility Dynamic Type sizes and switches onboarding to a vertically scrollable layout.
- Keeps the existing centered, bottom-action composition for standard Dynamic Type sizes.
- Allows descriptive and requirement rows to take their full vertical size.
- Keeps the Choose Folder button reachable and prevents its label from wrapping outside the capsule.

## Verification

- Set Simulator content size with `simctl ui ... content_size accessibility-extra-extra-extra-large`.
- Built, installed, and launched `app.mudsnote.companion` on iPhone 17 / iOS 26.5 Simulator.
- Visual evidence:
  - failing baseline: `/tmp/mudsnote-onboarding-axxxl-20260711.png`
  - corrected layout: `/tmp/mudsnote-onboarding-axxxl-fixed-20260711.png`
- Result: title and explanation render in full, requirements expand without ellipsis, and remaining content is reachable through native scrolling.

## Decisions

- Prefer native scrolling at accessibility sizes over reducing font scale.
- Preserve the original compact visual hierarchy for standard-size users.

## Next

- Audit the library, capture console, settings, and error recovery at accessibility sizes.
- Run VoiceOver, Increase Contrast, Reduce Motion, landscape, and iPad checks.

# 2026-07-11 iOS iPad orientations

## Request

Address release validation findings exposed by the connected-device build.

## Baseline

- Branch: `main`
- HEAD: `95bdf90`
- Device builds warned that a universal iPhone/iPad app must support all orientations unless it requires full screen.

## Changes

- Kept the intended portrait-first iPhone experience.
- Declared portrait, upside-down portrait, landscape left, and landscape right for iPad.
- Preserved iPad multitasking support instead of hiding the warning with a full-screen-only requirement.

## Verification

- Release generic-iOS build succeeds with `CODE_SIGNING_ALLOWED=NO`.
- The prior `All interface orientations must be supported` validation warning is absent.

## Next

- Complete visual layout checks on iPad portrait, landscape, and multitasking widths.

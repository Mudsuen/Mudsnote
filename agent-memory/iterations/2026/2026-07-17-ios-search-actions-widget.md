# iOS search-first actions widget

## Request

Optimize the Mudsnote iPhone widget and add a second layout whose top action is Search Notes, with Voice input and Quick Note side by side below it. Keep the existing iPhone-only scope and install the result on the connected iPhone.

## Baseline

- Branch: `main`.
- Prior iOS checkpoint: `cef2d33` (`Document unified iPhone note entry`).
- Dirty files before work: none.
- ShortcutTiles was inspected only to resolve which widget the request referred to; it received no source changes.

## Changes

- The existing small Mudsnote widget is now a focused Quick Note launcher instead of presenting several apparent controls on a WidgetKit surface that supports only one reliable effective URL.
- A separate medium `Mudsnote Actions` widget places a full-width Search Notes action above equal Voice input and Quick Note actions.
- Search uses `mudsnote://search`; voice and text continue through the established `mudsnote://capture` audio and text routes.
- Search intent is retained through cold app bootstrap and authorized-folder loading, consumed exactly once, and focuses the native library search field without requiring a second tap.
- English and Simplified Chinese widget metadata and supporting copy are included.
- Unit coverage verifies one-shot search-route consumption, while UI coverage verifies that the widget entry arrives with the search field focused and ready for immediate typing.

## Verification

- Simulator build passed on the sole approved iPhone 17 Pro / iOS 26.5 destination.
- Targeted regression passed: 107/107 unit tests and 2/2 relevant UI tests, zero failures.
- Full single-destination regression passed with parallel testing disabled: 107/107 unit tests and 53/53 UI tests, 160/160 total, zero failures and zero skipped.
- Generic iOS Release archive succeeded at version `1.0 (1)` with the Mudsnote App and Widget embedded and strictly code-signed.
- The development-signed App installed on physical `MudsPhone` / iPhone Air and appeared in the device inventory as `app.mudsnote.companion` version `1.0 (1)`.
- The post-install launch request reached the phone but iOS rejected it because the device had relocked; this does not affect the completed installation.

## Storage

- Iteration build, test, and archive artifacts were kept under `/tmp` and removed after verification; the sole simulator was shut down.

## Next

- Add the new medium `Mudsnote Actions` widget from the iPhone widget gallery to use the Search / Voice input / Quick Note layout; existing widget instances do not automatically switch widget kinds.

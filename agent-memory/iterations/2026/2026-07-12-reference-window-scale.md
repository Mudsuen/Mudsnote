# Reference-scale library window

## Decision

- Default and canonical library windows use `940x630pt`, close to the supplied `931x623pt` Notes reference.
- Minimum size is `904x560pt`, preserving `220pt` source, `200pt` list, and at least `480pt` editor widths plus dividers.
- Layout migration version 5 changes only stored frames exactly matching the prior `1080x680pt` or `1080x720pt` defaults.
- Migrated frames retain their center; customized frames remain untouched.

## Verification

- Unit coverage proves exact-default migration and custom-frame preservation.
- Canonical side-by-side visual QA must be regenerated at the new point size before closing the iteration.

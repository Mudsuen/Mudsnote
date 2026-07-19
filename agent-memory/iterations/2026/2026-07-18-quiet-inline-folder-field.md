# Quiet inline folder field

## Problem

The macOS temporary `新建文件夹` row used a custom blue rounded field border and control background. In the compact dark source list it read as an oversized form input and crowded the selected default name.

## Fix

- Preserve the native `NSTextField` and shared field-editor input path.
- Remove the custom background, layer border, and accent stroke.
- Keep the field borderless with no focus ring.
- Use a `20pt` single-line height inside the unchanged `32pt` source row.

## Boundary

This is presentation-only. Full-name selection, Chinese IME composition, Return commit, Escape cancel, focus-loss commit, create, and rename semantics remain unchanged.

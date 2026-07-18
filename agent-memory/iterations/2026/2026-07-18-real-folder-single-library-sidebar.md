# Real-folder single-library sidebar

## Contract

- Use the already registered iCloud Drive `Mudsbuild` directory as the user's default macOS library.
- Do not require synthetic `All iCloud` or legacy `Notes` rows when only one root is configured.
- Preserve files in the former local root; changing registration must never delete or move them.

## Implementation

- Folder source titles use the physical directory's last path component, including the default root.
- A sole root replaces the internal `.all` navigation scope in the source list and becomes selected directly.
- The aggregate `All iCloud` scope is projected only for multiple top-level roots or an explicitly opened external document.

## Verification boundary

Tests cover truthful default-root naming, single-root aggregate suppression, multiple-root aggregate restoration, keyboard navigation, counts, search scopes, and safe root removal. Installed-app verification must confirm only `Mudsbuild` appears after rewriting the user's registered-root preferences; the old `~/Documents/Mudsnote` directory must remain untouched.

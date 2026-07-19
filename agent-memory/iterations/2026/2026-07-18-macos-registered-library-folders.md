# macOS registered library folders

## Contract

- Add an existing top-level folder without copying or moving its contents.
- Remove a registered source without deleting files.
- Keep destructive deletion limited to managed child folders.
- Reveal any folder source in Finder from its context menu.
- Do not auto-select recent external documents during an ordinary library launch.

## Implementation

- `File > 将文件夹添加到资料库…` and the `iCloud` source-group context menu open a directory picker.
- Registration rejects exact duplicates and parent/child overlaps with configured roots.
- Non-default root menus contain `在 Finder 中显示` and `从资料库移除`; the default root contains only Finder reveal; nested folders contain Finder reveal plus rename/delete.
- Root lifecycle changes refresh the source projection, full note snapshot, persisted disclosure/pin metadata, and active filesystem monitor.
- `recentShellNoteResults`, the full All Notes snapshot, source tags, and library search sessions use configured roots. A currently explicit external document can still be projected as one document, but its parent directory is not treated as a library root.

## Cause of the Hermes launch

The persisted default root remained `~/Documents/Mudsnote`. `~/.hermes/SOUL.md` had been opened externally and remained first in `mudsnote.recentFiles`; the deferred shell previously projected every recent path and selected that external entry before the managed snapshot arrived. The shared core search index also expanded recent-file parent directories, so an unscoped full library refresh could pull the entire external corpus into All Notes and Tags. The macOS library now always supplies its registered roots explicitly.

## Verification boundary

Regression coverage must prove source removal leaves both the directory and Markdown file intact, root menus use removal rather than delete, overlap registration fails, and a more-recent external `.hermes/SOUL.md` never becomes the deferred library selection.

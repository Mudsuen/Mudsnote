# Mudsnote Architecture

This is the stable architecture map. Use it to choose a task boundary; use
`./scripts/agent_context.sh <topic> [regex]` to get the smallest working set.
Historical changes do not belong here.

## Sources Of Truth

| Concern | Owner |
| --- | --- |
| Product overview and public build entrypoints | `README.md` |
| Repository rules and efficient working method | `AGENTS.md` |
| Stable system boundaries and task routes | This file |
| Current takeover state and durable behavior constraints | `docs/AI_HANDOFF.md` |
| User-visible iteration history | `CHANGELOG.md` |
| Durable decisions and concrete incidents | `agent-memory/decisions/`; `agent-memory/incidents/` |
| Old implementation evidence | `agent-memory/iterations/`; `agent-memory/archive/` |
| Delivery lifecycle | `docs/delivery-workflow.md`; Devflow task contract |

Do not copy the same fact into several owners. Link to the owner instead.

## System Shape

Mudsnote has two platform applications that share the same local-first Markdown
product contract but do not share a compiled UI or persistence module.

### macOS

`Package.swift` builds:

- `MudsnoteCore`: Foundation-only models, settings, migration, Markdown file I/O,
  drafts, search, and optional local AI commands.
- `Mudsnote`: the AppKit executable, app routing, quick capture, library window,
  rich editor, supporting windows, and packaging resources.

Dependency direction:

```text
AppKit views/controllers -> MudsnoteCore -> filesystem/UserDefaults
```

`MudsnoteCore` must not import AppKit or depend on window state. Controllers may
coordinate UI and asynchronous work, but filesystem enumeration and document
semantics belong in stores, projections, or focused services.

### iOS

`iOS/MudsnoteCompanion.xcodeproj` builds the SwiftUI app and widget. Its main
boundaries are:

- `App/`: composition, routing, and observable application state.
- `Core/`: security-scoped folder access, Markdown persistence, lifecycle
  mutations, drafts, attachments, search support, and background-safe actors.
- `Features/`: capture, library/search, reader/editor, and shared native bridges.
- `SystemIntegrations/`: App Intents and OS entrypoints.
- `Design/`: visual tokens and reusable styles.

Dependency direction:

```text
SwiftUI features -> AppModel/Core actors -> security-scoped filesystem
System entrypoints -----------------------> validated Core writes
```

Views must not create a second persistence model. New lifecycle behavior should
enter through `AppModel` and the existing actors so UI, widget, intents, pending
writes, and tests observe the same result.

### Cross-platform Markdown contract

Both apps preserve portable `.md` files and relative attachment references.
They may have platform-specific implementations, but changes to stored Markdown,
front matter, attachment layout, tags, or filename semantics are explicitly
`both` changes and require compatibility coverage on both platforms.

## Task Routes

Run `./scripts/agent_context.sh --list` for the executable topic names.

| Task | Start here | Expand only when needed |
| --- | --- | --- |
| Core note storage, settings, migration, search | `Sources/MudsnoteCore/`; `Tests/MudsnoteCoreTests/` | App controller using the changed API |
| macOS app launch, menus, URLs, hotkeys | `Sources/Mudsnote/AppController.swift`; `Sources/Mudsnote/HotKey.swift` | Destination window controller |
| macOS library, source list, note list, gallery | `LibraryWindowController.swift`; `LibraryNoteListProjection.swift`; `LibraryGalleryView.swift` | Rich editor or store only at their boundary |
| macOS rich editor, tables, links, attachments | `MarkdownRichEditor.swift`; focused Markdown/attachment helpers | Library or quick-capture command adapter |
| macOS quick capture or floating editor | `EditorWindowController.swift` and focused extensions; `Chrome/`; `QuickCaptureDocumentState.swift` | Core draft/save code |
| iOS app state and routing | `iOS/MudsnoteCompanion/App/` | The one feature/Core boundary involved |
| iOS Markdown storage and lifecycle | `MarkdownFileStore.swift`; related focused Core actor/type | `AppModel` caller and focused tests |
| iOS library, folders, tags, search, gallery | `RecentSearchView.swift`; `SmartFolder.swift`; `AppModel.swift` | Store query/mutation used by the flow |
| iOS note reader/editor and attachments | `MarkdownPreviewView.swift`; `Features/Shared/`; focused Core helpers | `AppModel` and UI tests |
| Build, package, CI, install | `scripts/verify`; platform verify script; `.devflow.yaml` | Package/device script for the selected platform |

## Large-file Boundaries

Several mature files are still deliberate hotspots. Do not read them from top to
bottom by default:

- `LibraryWindowController.swift` owns the macOS three-pane orchestration.
- `MarkdownRichEditorTests.swift` contains the serialized macOS integration suite.
- `MarkdownFileStore.swift` owns the iOS filesystem transaction boundary.
- `MarkdownPreviewView.swift` owns iOS rendering/editing helpers and presentation.
- `RecentSearchView.swift` owns several related library navigation surfaces.
- `AppModel.swift` is the iOS application-state coordinator.

For these files:

1. Find the symbol first with `rg -n` or `agent_context.sh <topic> <regex>`.
2. Read only the matching function/type and its direct callers, normally no more
   than 200 lines at a time.
3. After editing, inspect the focused diff instead of rereading the file.
4. Put a new independent model, projection, service, or reusable view in a focused
   file. Extend a hotspot only when the behavior genuinely shares its state and
   lifecycle.
5. Perform structural extraction in its own behavior-preserving task; do not mix
   broad movement with a bug fix.

This policy keeps context narrow now while allowing coherent, test-backed splits
instead of line-count-driven churn.

## Runtime Architecture Rules

- Markdown on disk is canonical; caches and snapshots are bounded projections.
- UI should paint from memory first and validate filesystem state asynchronously.
- Generation/cancellation checks must reject stale asynchronous results.
- Do not introduce a second note index, folder tree, or selection model for a new
  presentation when an existing projection can be reused.
- Keep user filesystem access outside PR CI. Tests use temporary directories and
  deterministic fixtures only.
- Quick capture remains a separate title/body workflow with its own compact
  chrome; it is not a miniature copy of the library editor.
- macOS installed artifacts and the connected iPhone are shared across worktrees.
  Only an explicit `live` scope may mutate either target.

## Change And Verification Flow

1. Declare `macos`, `ios`, or explicit `both`.
2. Run the matching context route and record a short set of confirmed facts.
3. Make the smallest cohesive change and add focused coverage.
4. Run `git diff --check`, then one focused test cycle.
5. Fix all known issues, rerun focused coverage once, and run the selected final
   `./scripts/verify <platform> pr|full|live` candidate.
6. Update only the document that owns a new durable fact.
7. Deliver through Devflow; real installs remain separate from PR CI.

See `docs/delivery-workflow.md` for the lifecycle and `docs/AI_HANDOFF.md` for
current product constraints.

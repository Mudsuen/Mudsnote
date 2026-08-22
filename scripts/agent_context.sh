#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TOPICS=(
  overview
  core-store
  macos-app
  macos-library
  macos-editor
  quick-capture
  ios-app
  ios-storage
  ios-library
  ios-editor
  delivery
)

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./scripts/agent_context.sh --task
  ./scripts/agent_context.sh --list
  ./scripts/agent_context.sh --check
  ./scripts/agent_context.sh <topic> [regex]

The topic command prints the smallest source/test working set. When a regex is
provided it searches only that set and caps matches per file.
USAGE
}

print_task_capsule() {
  echo "Legacy task capsule retired; using a local Git checkpoint."
  printf 'Repository: %s\n' "$ROOT_DIR"
  printf 'Branch: '
  git branch --show-current
  printf 'HEAD: '
  git rev-parse --short HEAD
  echo "Status:"
  git status --short
}

load_topic() {
  local topic="$1"
  FILES=()
  TESTS=()
  DOCS=()
  DESCRIPTION=""
  SEARCH_HINT=""

  case "$topic" in
    overview)
      DESCRIPTION="Cross-platform composition and product boundary"
      FILES=(
        Package.swift
        Sources/Mudsnote/AppController.swift
        Sources/MudsnoteCore/NoteStore.swift
        iOS/MudsnoteCompanion/App/AppModel.swift
        iOS/MudsnoteCompanion/App/RootView.swift
      )
      DOCS=(docs/ARCHITECTURE.md docs/AI_HANDOFF.md)
      SEARCH_HINT='@main|showLibrary|CaptureRoute|SystemEntryRequest|NoteStore'
      ;;
    core-store)
      DESCRIPTION="macOS shared models, settings, migration, Markdown I/O, drafts, and search"
      FILES=(Sources/MudsnoteCore)
      TESTS=(Tests/MudsnoteCoreTests)
      SEARCH_HINT='NoteStore|MarkdownEditorDocument|searchNotes|saveNewNote|updateNote|migrate'
      ;;
    macos-app)
      DESCRIPTION="macOS lifecycle, menus, hotkeys, URL/file routing, and supporting windows"
      FILES=(
        Sources/Mudsnote/AppController.swift
        Sources/Mudsnote/HotKey.swift
        Sources/Mudsnote/SearchWindowController.swift
        Sources/Mudsnote/PreferencesWindowController.swift
        Sources/Mudsnote/FloatingNoteBrowserController.swift
      )
      TESTS=(Tests/MudsnoteAppTests/MarkdownRichEditorTests.swift)
      SEARCH_HINT='applicationDidFinishLaunching|openFiles|showLibrary|HotKey|validateMenuItem'
      ;;
    macos-library)
      DESCRIPTION="macOS three-pane library, source/list/gallery projection, and file monitoring"
      FILES=(
        Sources/Mudsnote/LibraryWindowController.swift
        Sources/Mudsnote/LibrarySourceProjection.swift
        Sources/Mudsnote/LibraryNotesLayout.swift
        Sources/Mudsnote/LibraryNoteListProjection.swift
        Sources/Mudsnote/LibraryGalleryView.swift
        Sources/Mudsnote/LibraryFileSystemMonitor.swift
      )
      TESTS=(Tests/MudsnoteAppTests/MarkdownRichEditorTests.swift scripts/library_smoke.sh)
      DOCS=(docs/apple-notes-parity-roadmap.md)
      SEARCH_HINT='reloadNotes|selectedScope|outlineView|tableView|collectionView|saveCurrentNote'
      ;;
    macos-editor)
      DESCRIPTION="macOS rich Markdown rendering, commands, links, tables, paste, and attachments"
      FILES=(
        Sources/Mudsnote/MarkdownRichEditor.swift
        Sources/Mudsnote/MarkdownRichPasteNormalizer.swift
        Sources/Mudsnote/MarkdownAttachmentStorage.swift
        Sources/Mudsnote/AttachmentQuickLookController.swift
        Sources/Mudsnote/LinkEditorSheetController.swift
      )
      TESTS=(Tests/MudsnoteAppTests/MarkdownRichEditorTests.swift)
      SEARCH_HINT='MarkdownTextView|render|serialize|menu\(for|RichMarkdownTable|Attachment'
      ;;
    quick-capture)
      DESCRIPTION="macOS quick capture, floating editor, draft/save flow, and compact chrome"
      FILES=(
        Sources/Mudsnote/EditorWindowController.swift
        Sources/Mudsnote/EditorWindowController+UI.swift
        Sources/Mudsnote/EditorWindowController+TextHelpers.swift
        Sources/Mudsnote/EditorWindowController+Draft.swift
        Sources/Mudsnote/EditorWindowController+Formatting.swift
        Sources/Mudsnote/EditorWindowController+TagsAndSuggestions.swift
        Sources/Mudsnote/EditorWindowController+Save.swift
        Sources/Mudsnote/EditorWindowController+Attachments.swift
        Sources/Mudsnote/EditorWindowController+AI.swift
        Sources/Mudsnote/EditorWindowController+Appearance.swift
        Sources/Mudsnote/QuickCaptureDocumentState.swift
        Sources/Mudsnote/MarkdownRichEditor.swift
        Sources/Mudsnote/Chrome
      )
      TESTS=(Tests/MudsnoteAppTests/MarkdownRichEditorTests.swift)
      SEARCH_HINT='buildQuickCaptureUI|persistDraft|savePressed|QuickCapture|MarkdownTextView'
      ;;
    ios-app)
      DESCRIPTION="iOS composition, routing, observable state, onboarding, intents, and widget"
      FILES=(
        iOS/MudsnoteCompanion/App
        iOS/MudsnoteCompanion/MudsnoteCompanionApp.swift
        iOS/MudsnoteCompanion/SystemIntegrations
        iOS/MudsnoteCompanionWidget
      )
      TESTS=(iOS/MudsnoteCompanionTests iOS/MudsnoteCompanionUITests)
      SEARCH_HINT='AppModel|CaptureRoute|SystemEntryRequest|AppIntent|Widget'
      ;;
    ios-storage)
      DESCRIPTION="iOS security-scoped filesystem, Markdown lifecycle, drafts, and pending writes"
      FILES=(
        iOS/MudsnoteCompanion/Core/MarkdownFileStore.swift
        iOS/MudsnoteCompanion/Core/AuthorizedLibraryPath.swift
        iOS/MudsnoteCompanion/Core/MarkdownLibraryModels.swift
        iOS/MudsnoteCompanion/Core/MarkdownSearch.swift
        iOS/MudsnoteCompanion/Core/FolderAccessService.swift
        iOS/MudsnoteCompanion/Core/PendingWriteQueue.swift
        iOS/MudsnoteCompanion/Core/CaptureDraft.swift
        iOS/MudsnoteCompanion/Core/MarkdownTagSyntax.swift
        iOS/MudsnoteCompanion/Core/MarkdownNoteLink.swift
      )
      TESTS=(iOS/MudsnoteCompanionTests/MudsnoteCompanionTests.swift)
      SEARCH_HINT='MarkdownFileStore|startAccessingSecurityScopedResource|save|move|trash|restore'
      ;;
    ios-library)
      DESCRIPTION="iOS home, folders, tags, search, gallery, smart folders, and attachment browser"
      FILES=(
        iOS/MudsnoteCompanion/Features/Reader/RecentSearchView.swift
        iOS/MudsnoteCompanion/Core/SmartFolder.swift
        iOS/MudsnoteCompanion/Core/AttachmentTextIndex.swift
        iOS/MudsnoteCompanion/App/AppModel.swift
      )
      TESTS=(iOS/MudsnoteCompanionTests iOS/MudsnoteCompanionUITests)
      DOCS=(docs/ios-apple-notes-parity-roadmap.md)
      SEARCH_HINT='LibraryHomeView|FolderNotesListView|search|gallery|SmartFolder|AttachmentLibraryView'
      ;;
    ios-editor)
      DESCRIPTION="iOS note reader/editor, Markdown commands, tables, find, and native attachment bridges"
      FILES=(
        iOS/MudsnoteCompanion/Features/Reader/MarkdownPreviewView.swift
        iOS/MudsnoteCompanion/Features/Shared
        iOS/MudsnoteCompanion/Core/NotePDFExporter.swift
        iOS/MudsnoteCompanion/Core/AttachmentPresentationPreferences.swift
        iOS/MudsnoteCompanion/App/AppModel.swift
      )
      TESTS=(iOS/MudsnoteCompanionTests iOS/MudsnoteCompanionUITests)
      SEARCH_HINT='MarkdownPreviewView|MarkdownEditingCommand|NoteFind|MarkdownTable|Attachment'
      ;;
    delivery)
      DESCRIPTION="Platform scope detection, deterministic verification, packaging, and install"
      FILES=(
        scripts/verify
        scripts/detect_platform_scope.sh
        scripts/verify_macos.sh
        scripts/verify_ios.sh
        scripts/package_app.sh
        scripts/device_smoke.sh
        scripts/ios_signing_refresh.sh
      )
      DOCS=(docs/delivery-workflow.md AGENTS.md)
      SEARCH_HINT='PLATFORM_SCOPE|pr|full|live|package|install|sign|provision|LaunchAgent'
      ;;
    *)
      echo "ERROR: unknown context topic: $topic" >&2
      usage
      return 2
      ;;
  esac
}

print_list() {
  local topic
  for topic in "${TOPICS[@]}"; do
    load_topic "$topic"
    printf '%-15s %s\n' "$topic" "$DESCRIPTION"
  done
}

check_context_contract() {
  local failures=0
  local topic path

  for topic in "${TOPICS[@]}"; do
    load_topic "$topic"
    for path in "${FILES[@]}" "${TESTS[@]}" "${DOCS[@]}"; do
      if [[ ! -e "$path" ]]; then
        echo "ERROR: $topic routes to missing path: $path" >&2
        failures=1
      fi
    done
  done

  local handoff_lines handoff_words architecture_lines architecture_words entry_lines entry_words
  handoff_lines="$(wc -l < docs/AI_HANDOFF.md | tr -d ' ')"
  handoff_words="$(wc -w < docs/AI_HANDOFF.md | tr -d ' ')"
  architecture_lines="$(wc -l < docs/ARCHITECTURE.md | tr -d ' ')"
  architecture_words="$(wc -w < docs/ARCHITECTURE.md | tr -d ' ')"
  entry_lines="$(wc -l < AGENTS.md | tr -d ' ')"
  entry_words="$(wc -w < AGENTS.md | tr -d ' ')"

  if (( handoff_lines > 80 )); then
    echo "ERROR: docs/AI_HANDOFF.md exceeds its 80-line current-state budget ($handoff_lines)." >&2
    failures=1
  fi
  if (( architecture_lines > 170 )); then
    echo "ERROR: docs/ARCHITECTURE.md exceeds its 170-line stable-map budget ($architecture_lines)." >&2
    failures=1
  fi
  if (( handoff_words > 500 )); then
    echo "ERROR: docs/AI_HANDOFF.md exceeds its 500-word current-state budget ($handoff_words)." >&2
    failures=1
  fi
  if (( architecture_words > 1100 )); then
    echo "ERROR: docs/ARCHITECTURE.md exceeds its 1100-word stable-map budget ($architecture_words)." >&2
    failures=1
  fi
  if (( entry_lines > 90 )); then
    echo "ERROR: default agent entry context exceeds 90 lines ($entry_lines)." >&2
    failures=1
  fi
  if (( entry_words > 700 )); then
    echo "ERROR: default agent entry context exceeds 700 words ($entry_words)." >&2
    failures=1
  fi
  if ! grep -q -- 'agent_context.sh' AGENTS.md; then
    echo "ERROR: focused agent context routing is missing from AGENTS.md." >&2
    failures=1
  fi
  if grep -En '^## Latest iteration' docs/AI_HANDOFF.md >/dev/null; then
    echo "ERROR: chronological iteration logs do not belong in docs/AI_HANDOFF.md." >&2
    failures=1
  fi

  if (( failures != 0 )); then
    return 1
  fi

  echo "Agent context contract passed: entry=$entry_lines lines/$entry_words words; handoff=$handoff_lines/$handoff_words; architecture=$architecture_lines/$architecture_words."
}

print_topic() {
  local topic="$1"
  local query="${2:-}"
  local path

  load_topic "$topic"
  echo "Topic: $topic"
  echo "Purpose: $DESCRIPTION"
  echo "Source paths:"
  for path in "${FILES[@]}"; do
    echo "  $path"
  done
  if (( ${#TESTS[@]} > 0 )); then
    echo "Test paths:"
    for path in "${TESTS[@]}"; do
      echo "  $path"
    done
  fi
  if (( ${#DOCS[@]} > 0 )); then
    echo "Optional docs:"
    for path in "${DOCS[@]}"; do
      echo "  $path"
    done
  fi

  if [[ -z "$query" ]]; then
    echo "Suggested symbol regex: $SEARCH_HINT"
    echo "Next: ./scripts/agent_context.sh $topic '<narrow-regex>'"
    return 0
  fi

  echo "Matches for: $query"
  local status=0
  local matches=""
  set +e
  matches="$(rg -n --no-heading --color never -m 12 -- "$query" "${FILES[@]}" "${TESTS[@]}")"
  status=$?
  set -e
  if (( status == 1 )); then
    echo "No matches in the routed working set. Refine the term before expanding scope."
    return 1
  fi
  if (( status != 0 )); then
    return "$status"
  fi

  local match_count
  match_count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  printf '%s\n' "$matches" | sed -n '1,120p'
  if (( match_count > 120 )); then
    echo "... $((match_count - 120)) additional matches omitted; narrow the regex."
  fi
  return "$status"
}

case "${1:-}" in
  --task)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    print_task_capsule
    ;;
  --list)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    print_list
    ;;
  --check)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    check_context_contract
    ;;
  ""|-h|--help)
    usage
    ;;
  *)
    [[ $# -le 2 ]] || { usage; exit 2; }
    print_topic "$1" "${2:-}"
    ;;
esac

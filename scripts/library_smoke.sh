#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${MUDSNOTE_APP_PATH:-/Applications/Mudsnote.app}"
OUTPUT_DIR="${1:-$(mktemp -d /tmp/mudsnote-library-smoke.XXXXXX)}"
NOTES_DIR="$OUTPUT_DIR/Notes"
APP_SUPPORT_DIR="$OUTPUT_DIR/AppSupport"
MOVE_FOLDER="$NOTES_DIR/Smoke Folder"
DEFAULTS_SUITE="local.codex.mudsnote.library-smoke.$$"
NOTE_TITLE="Installed Smoke Note"
NOTE_BODY="Smoke body line"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$NOTES_DIR" "$APP_SUPPORT_DIR" "$MOVE_FOLDER"
printf '# Existing Seed\n\nUnrelated body\n' >"$NOTES_DIR/Existing Seed.md"
defaults delete "$DEFAULTS_SUITE" >/dev/null 2>&1 || true

cleanup() {
  local exit_code=$?
  trap - EXIT
  pkill -x Mudsnote >/dev/null 2>&1 || true
  defaults delete "$DEFAULTS_SUITE" >/dev/null 2>&1 || true
  exit "$exit_code"
}
trap cleanup EXIT

pkill -x Mudsnote >/dev/null 2>&1 || true
sleep 0.5
open -n "$APP_PATH" --args \
  --library \
  --visual-qa-defaults-suite "$DEFAULTS_SUITE" \
  --visual-qa-notes-dir "$NOTES_DIR" \
  --visual-qa-app-support-dir "$APP_SUPPORT_DIR"

for _ in {1..30}; do
  if osascript -e 'tell application "System Events" to return exists application process "Mudsnote"' 2>/dev/null \
    | grep -q true; then
    break
  fi
  sleep 0.2
done

sleep "${MUDSNOTE_LIBRARY_SMOKE_LAUNCH_DELAY:-3}"

UI_READY=false
for _ in {1..30}; do
  if osascript <<'APPLESCRIPT' 2>/dev/null | grep -q true
tell application "System Events" to tell process "Mudsnote"
  if (count windows) = 0 then return false
  set foundEditor to false
  set elements to entire contents of window 1
  repeat with index from 1 to count elements
    set candidate to item index of elements
    try
      set candidateRole to role of candidate as text
      if candidateRole = "AXTextArea" then set foundEditor to true
    end try
  end repeat
  return foundEditor
end tell
APPLESCRIPT
  then
    UI_READY=true
    break
  fi
  sleep 0.2
done
if [[ "$UI_READY" != true ]]; then
  echo "Installed app did not expose the Notes editor accessibility tree." >&2
  exit 1
fi

osascript - "$NOTE_TITLE" "$NOTE_BODY" <<'APPLESCRIPT'
on run arguments
  set noteTitle to item 1 of arguments
  set noteBody to item 2 of arguments

  tell application "Mudsnote" to activate
  tell application "System Events"
    tell process "Mudsnote"
      set frontmost to true
      repeat 30 times
        if (count windows) > 0 then exit repeat
        delay 0.2
      end repeat
      if (count windows) = 0 then error "Mudsnote library window did not appear"

      set titleIndex to 0
      set bodyIndex to 0
      repeat 30 times
        set elements to entire contents of window 1
        set titleIndex to 0
        set bodyIndex to 0
        set textFieldCount to 0
        repeat with index from 1 to count elements
          set candidate to item index of elements
          try
            set candidateRole to role of candidate as text
            if candidateRole = "AXTextField" then
              set textFieldCount to textFieldCount + 1
              if textFieldCount = 1 then set titleIndex to index
            end if
            if candidateRole = "AXTextArea" then
              if bodyIndex = 0 then set bodyIndex to index
            end if
          end try
        end repeat
        if titleIndex > 0 then
          if bodyIndex > 0 then exit repeat
        end if
        delay 0.2
      end repeat
      if titleIndex = 0 then error "Notes editor did not finish loading"
      if bodyIndex = 0 then error "Notes editor did not finish loading"

      keystroke "n" using command down
      delay 0.5

      repeat 15 times
        set elements to entire contents of window 1
        set titleIndex to 0
        set bodyIndex to 0
        set textFieldCount to 0
        repeat with index from 1 to count elements
          set candidate to item index of elements
          try
            set candidateRole to role of candidate as text
            if candidateRole = "AXTextField" then
              set textFieldCount to textFieldCount + 1
              if textFieldCount = 1 then set titleIndex to index
            end if
            if candidateRole = "AXTextArea" then
              if bodyIndex = 0 then set bodyIndex to index
            end if
          end try
        end repeat
        if titleIndex > 0 then
          if bodyIndex > 0 then exit repeat
        end if
        delay 0.2
      end repeat
      if titleIndex = 0 then error "Could not locate the Notes editor fields"
      if bodyIndex = 0 then error "Could not locate the Notes editor fields"

      set titleField to item titleIndex of elements
      set bodyArea to item bodyIndex of elements
      set focused of titleField to true
      set value of titleField to noteTitle
      set focused of bodyArea to true
      set value of bodyArea to noteBody
      delay 2

      keystroke "f" using command down
      delay 0.3
      set elements to entire contents of window 1
      set searchIndex to 0
      set textFieldCount to 0
      repeat with index from 1 to count elements
        set candidate to item index of elements
        try
          set candidateRole to role of candidate as text
          if candidateRole = "AXTextField" then
            set textFieldCount to textFieldCount + 1
            if textFieldCount = 2 then set searchIndex to index
          end if
        end try
      end repeat
      if searchIndex = 0 then error "Could not locate the Notes search field"
      set searchField to item searchIndex of elements
      set focused of searchField to true
      set value of searchField to noteTitle
      delay 0.2
    end tell
  end tell
end run
APPLESCRIPT

SEARCH_EVIDENCE=""
for _ in {1..30}; do
  SEARCH_EVIDENCE="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "System Events" to tell process "Mudsnote"
  set evidence to ""
  set elements to entire contents of window 1
  repeat with index from 1 to count elements
    set candidate to item index of elements
    try
      set candidateRole to role of candidate as text
      if candidateRole = "AXStaticText" then
        set evidence to evidence & (value of candidate as text) & linefeed
      end if
    end try
  end repeat
  return evidence
end tell
APPLESCRIPT
)"
  if grep -Fq "$NOTE_TITLE" <<<"$SEARCH_EVIDENCE"; then
    break
  fi
  sleep 0.2
done

SAVED_NOTE="$(find "$NOTES_DIR" -maxdepth 1 -type f -name '*installed-smoke-note.md' -print -quit)"
if [[ -z "$SAVED_NOTE" ]]; then
  echo "Installed app did not autosave the smoke note." >&2
  exit 1
fi

EXPECTED_CONTENT=$'# Installed Smoke Note\n\nSmoke body line'
ACTUAL_CONTENT="$(sed -e '${/^$/d;}' "$SAVED_NOTE")"
if [[ "$ACTUAL_CONTENT" != "$EXPECTED_CONTENT" ]]; then
  echo "Unexpected saved Markdown content in $SAVED_NOTE" >&2
  printf 'Expected:\n%s\nActual:\n%s\n' "$EXPECTED_CONTENT" "$ACTUAL_CONTENT" >&2
  exit 1
fi

if ! grep -Fq "$NOTE_TITLE" <<<"$SEARCH_EVIDENCE"; then
  echo "Search did not expose the newly created note in the installed app." >&2
  printf 'Accessibility evidence:\n%s\n' "$SEARCH_EVIDENCE" >&2
  exit 1
fi
if grep -Fq "Existing Seed" <<<"$SEARCH_EVIDENCE"; then
  echo "Search did not filter the unrelated fixture note." >&2
  exit 1
fi

osascript <<'APPLESCRIPT' >/dev/null
tell application "Mudsnote" to activate
tell application "System Events" to tell process "Mudsnote"
  set frontmost to true
  key code 125
  key code 36
  delay 0.5
  click menu item "移到最近删除" of menu 1 of menu bar item "文件" of menu bar 1
end tell
APPLESCRIPT

TRASHED_NOTE=""
for _ in {1..30}; do
  TRASHED_NOTE="$(find "$APP_SUPPORT_DIR/Trash" -maxdepth 1 -type f -name '*installed-smoke-note.md' -print -quit 2>/dev/null || true)"
  if [[ -n "$TRASHED_NOTE" && ! -e "$SAVED_NOTE" ]]; then
    break
  fi
  sleep 0.2
done
if [[ -z "$TRASHED_NOTE" || -e "$SAVED_NOTE" ]]; then
  echo "Installed app did not move the smoke note to Recently Deleted." >&2
  exit 1
fi

osascript <<'APPLESCRIPT' >/dev/null
tell application "Mudsnote" to activate
tell application "System Events" to tell process "Mudsnote"
  set frontmost to true
  set trashButtonIndex to 0
  set elements to entire contents of window 1
  repeat with index from 1 to count elements
    set candidate to item index of elements
    try
      set candidateRole to role of candidate as text
      set candidateDescription to description of candidate as text
      if candidateRole = "AXButton" then
        if candidateDescription = "Recently Deleted" then set trashButtonIndex to index
      end if
    end try
  end repeat
  if trashButtonIndex = 0 then error "Could not locate Recently Deleted"
  perform action "AXPress" of item trashButtonIndex of elements
  delay 1
  click menu item "恢复笔记" of menu 1 of menu bar item "文件" of menu bar 1
end tell
APPLESCRIPT

for _ in {1..30}; do
  if [[ -e "$SAVED_NOTE" && ! -e "$TRASHED_NOTE" ]]; then
    break
  fi
  sleep 0.2
done
if [[ ! -e "$SAVED_NOTE" || -e "$TRASHED_NOTE" ]]; then
  echo "Installed app did not restore the smoke note from Recently Deleted." >&2
  exit 1
fi

osascript <<'APPLESCRIPT' >/dev/null
tell application "Mudsnote" to activate
tell application "System Events" to tell process "Mudsnote"
  set frontmost to true
  click menu bar item "文件" of menu bar 1
  delay 0.3
  set moveItem to menu item "移到文件夹" of menu 1 of menu bar item "文件" of menu bar 1
  click moveItem
  delay 0.3
  click menu item "  Smoke Folder" of menu 1 of moveItem
end tell
APPLESCRIPT

MOVED_NOTE="$MOVE_FOLDER/$(basename "$SAVED_NOTE")"
for _ in {1..30}; do
  if [[ -e "$MOVED_NOTE" && ! -e "$SAVED_NOTE" ]]; then
    break
  fi
  sleep 0.2
done
if [[ ! -e "$MOVED_NOTE" || -e "$SAVED_NOTE" ]]; then
  echo "Installed app did not move the smoke note into Smoke Folder." >&2
  exit 1
fi

echo "Installed library smoke passed"
echo "app=$APP_PATH"
echo "fixture=$OUTPUT_DIR"
echo "saved_note=$SAVED_NOTE"
echo "trash_restore=passed"
echo "folder_move=$MOVED_NOTE"

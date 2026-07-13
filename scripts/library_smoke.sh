#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${MUDSNOTE_APP_PATH:-/Applications/Mudsnote.app}"
OUTPUT_DIR="${1:-$(mktemp -d /tmp/mudsnote-library-smoke.XXXXXX)}"
NOTES_DIR="$OUTPUT_DIR/Notes"
APP_SUPPORT_DIR="$OUTPUT_DIR/AppSupport"
MOVE_FOLDER="$NOTES_DIR/Smoke Folder"
ATTACHMENT_SOURCE="$OUTPUT_DIR/smoke attachment.pdf"
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
printf 'Installed attachment fixture\n' >"$ATTACHMENT_SOURCE"
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

open "$APP_PATH"
sleep 0.3

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

SAVED_NOTE=""
for _ in {1..30}; do
  SAVED_NOTE="$(find "$NOTES_DIR" -maxdepth 1 -type f -name '*installed-smoke-note.md' -print -quit)"
  if [[ -n "$SAVED_NOTE" ]]; then
    break
  fi
  sleep 0.2
done
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
  set trashCellIndex to 0
  set elements to entire contents of window 1
  repeat with index from 1 to count elements
    set candidate to item index of elements
    try
      set candidateRole to role of candidate as text
      set candidateDescription to description of candidate as text
      if candidateRole = "AXCell" then
        if candidateDescription = "Recently Deleted" then set trashCellIndex to index
      end if
    end try
  end repeat
  if trashCellIndex = 0 then error "Could not locate Recently Deleted"
  perform action "AXPress" of item trashCellIndex of elements
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

open "$APP_PATH"
sleep 0.3

osascript - "$ATTACHMENT_SOURCE" <<'APPLESCRIPT' >/dev/null
on run arguments
  set attachmentPath to item 1 of arguments
  set the clipboard to POSIX file attachmentPath
  tell application "Mudsnote" to activate
  tell application "System Events" to tell process "Mudsnote"
    set frontmost to true
    set elements to entire contents of window 1
    set bodyIndex to 0
    repeat with index from 1 to count elements
      set candidate to item index of elements
      try
        if (role of candidate as text) = "AXTextArea" then
          set bodyIndex to index
          exit repeat
        end if
      end try
    end repeat
    if bodyIndex = 0 then error "Could not locate the Notes editor body for attachment paste"
    set bodyArea to item bodyIndex of elements
    set focused of bodyArea to true
    key code 125 using command down
    key code 9 using command down
  end tell
end run
APPLESCRIPT

COPIED_ATTACHMENT=""
for _ in {1..30}; do
  COPIED_ATTACHMENT="$(find "$MOVE_FOLDER/Attachments" -type f -name 'smoke attachment.pdf' -print -quit 2>/dev/null || true)"
  if [[ -n "$COPIED_ATTACHMENT" ]] && grep -Fq \
    '[smoke attachment](Attachments/' "$MOVED_NOTE" && grep -Fq \
    'smoke%20attachment.pdf)' "$MOVED_NOTE"; then
    break
  fi
  sleep 0.2
done
if [[ -z "$COPIED_ATTACHMENT" || ! -e "$COPIED_ATTACHMENT" ]]; then
  echo "Installed app did not copy the pasted attachment into local storage." >&2
  exit 1
fi
if ! grep -Fq '[smoke attachment](Attachments/' "$MOVED_NOTE" \
  || ! grep -Fq 'smoke%20attachment.pdf)' "$MOVED_NOTE"; then
  echo "Installed app did not save a portable relative attachment link." >&2
  exit 1
fi

OBJECT_REPLACEMENT_CHARACTER=$'\xEF\xBF\xBC'
ATTACHMENT_UI_EVIDENCE="$(osascript <<'APPLESCRIPT'
tell application "System Events" to tell process "Mudsnote"
  set bodyValue to ""
  set hasAttachmentIndicator to false
  set elements to entire contents of window 1
  repeat with candidate in elements
    try
      set candidateRole to role of candidate as text
      if candidateRole = "AXTextArea" then set bodyValue to value of candidate as text
      if candidateRole = "AXImage" then
        if (description of candidate as text) = "有附件" then set hasAttachmentIndicator to true
      end if
    end try
  end repeat
  return bodyValue & linefeed & hasAttachmentIndicator
end tell
APPLESCRIPT
)"
if [[ "$ATTACHMENT_UI_EVIDENCE" != *"$OBJECT_REPLACEMENT_CHARACTER"* ]] \
  || [[ "$ATTACHMENT_UI_EVIDENCE" != *$'\ntrue' ]]; then
  echo "Installed app did not expose the rendered attachment and list indicator." >&2
  printf 'Accessibility evidence:\n%s\n' "$ATTACHMENT_UI_EVIDENCE" >&2
  exit 1
fi

pkill -x Mudsnote >/dev/null 2>&1 || true
sleep 0.5
open -n "$APP_PATH" --args \
  --library \
  --visual-qa-defaults-suite "$DEFAULTS_SUITE" \
  --visual-qa-notes-dir "$NOTES_DIR" \
  --visual-qa-app-support-dir "$APP_SUPPORT_DIR"
sleep "${MUDSNOTE_LIBRARY_SMOKE_RELAUNCH_DELAY:-3}"

RELOADED_ATTACHMENT_EVIDENCE="$(osascript - "$NOTE_TITLE" <<'APPLESCRIPT'
on run arguments
  set noteTitle to item 1 of arguments
  tell application "Mudsnote" to activate
  tell application "System Events" to tell process "Mudsnote"
    set frontmost to true
    repeat 30 times
      if (count windows) > 0 then exit repeat
      delay 0.2
    end repeat
    if (count windows) = 0 then error "Mudsnote library window did not reappear"

    repeat 30 times
      set elements to entire contents of window 1
      set titleValue to ""
      set textFieldCount to 0
      repeat with candidate in elements
        try
          if (role of candidate as text) = "AXTextField" then
            set textFieldCount to textFieldCount + 1
            if textFieldCount = 1 then set titleValue to value of candidate as text
          end if
        end try
      end repeat
      if titleValue = noteTitle then exit repeat
      delay 0.2
    end repeat

    set bodyValue to ""
    set titleValue to ""
    set hasAttachmentIndicator to false
    set elements to entire contents of window 1
    set textFieldCount to 0
    repeat with candidate in elements
      try
        set candidateRole to role of candidate as text
        if candidateRole = "AXTextField" then
          set textFieldCount to textFieldCount + 1
          if textFieldCount = 1 then set titleValue to value of candidate as text
        end if
        if candidateRole = "AXTextArea" then set bodyValue to value of candidate as text
        if candidateRole = "AXImage" then
          if (description of candidate as text) = "有附件" then set hasAttachmentIndicator to true
        end if
      end try
    end repeat
    return titleValue & linefeed & bodyValue & linefeed & hasAttachmentIndicator
  end tell
end run
APPLESCRIPT
)"
if [[ "$RELOADED_ATTACHMENT_EVIDENCE" != "$NOTE_TITLE"$'\n'* ]] \
  || [[ "$RELOADED_ATTACHMENT_EVIDENCE" != *"$OBJECT_REPLACEMENT_CHARACTER"* ]] \
  || [[ "$RELOADED_ATTACHMENT_EVIDENCE" != *$'\ntrue' ]]; then
  echo "Installed app did not render the saved attachment after relaunch." >&2
  printf 'Accessibility evidence:\n%s\n' "$RELOADED_ATTACHMENT_EVIDENCE" >&2
  exit 1
fi

echo "Installed library smoke passed"
echo "app=$APP_PATH"
echo "fixture=$OUTPUT_DIR"
echo "saved_note=$SAVED_NOTE"
echo "trash_restore=passed"
echo "folder_move=$MOVED_NOTE"
echo "attachment_copy=$COPIED_ATTACHMENT"
echo "attachment_reload=passed"

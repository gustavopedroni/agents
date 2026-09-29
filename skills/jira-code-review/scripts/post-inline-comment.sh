#!/usr/bin/env bash
# Post an inline discussion on a GitLab MR diff line; fall back to a general
# MR note (prefixed with file:line) when GitLab rejects the position.
# Usage: post-inline-comment.sh <project-path> <mr-iid> <file> <line> <body-file>
set -euo pipefail

PROJECT_RAW=$1
IID=$2
FILE=$3
LINE=$4
BODY_FILE=$5
PROJECT=$(printf %s "$PROJECT_RAW" | jq -sRr @uri)

REFS=$(glab api "projects/$PROJECT/merge_requests/$IID" | jq -c '.diff_refs')

PAYLOAD=$(jq -n \
  --rawfile body "$BODY_FILE" \
  --argjson refs "$REFS" \
  --arg file "$FILE" \
  --argjson line "$LINE" \
  '{body: $body, position: {
      position_type: "text",
      base_sha: $refs.base_sha,
      head_sha: $refs.head_sha,
      start_sha: $refs.start_sha,
      new_path: $file,
      new_line: $line
    }}')

if printf %s "$PAYLOAD" | glab api "projects/$PROJECT/merge_requests/$IID/discussions" \
  -X POST -H "Content-Type: application/json" --input - >/dev/null 2>&1; then
  echo "inline $FILE:$LINE"
else
  NOTE_FILE=$(mktemp)
  {
    printf '**`%s:%s`**\n\n' "$FILE" "$LINE"
    cat "$BODY_FILE"
  } >"$NOTE_FILE"
  glab mr note "$IID" -R "$PROJECT_RAW" -m "$(cat "$NOTE_FILE")" >/dev/null
  rm -f "$NOTE_FILE"
  echo "fallback-note $FILE:$LINE"
fi

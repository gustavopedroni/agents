#!/usr/bin/env bash
# Check whether an MR was already reviewed by jira-code-review at its current head_sha.
# (Marker string kept as "code-review-auto" for backward compat with already-posted notes.)
# Usage: check-reviewed.sh <project-path> <mr-iid>
# Output: "head_sha=<sha>" then "reviewed=yes|no"
set -euo pipefail

PROJECT_RAW=$1
IID=$2
PROJECT=$(printf %s "$PROJECT_RAW" | jq -sRr @uri)

HEAD_SHA=$(glab api "projects/$PROJECT/merge_requests/$IID" | jq -r '.diff_refs.head_sha')
echo "head_sha=$HEAD_SHA"

MARKER="code-review-auto head_sha=$HEAD_SHA"
if glab api "projects/$PROJECT/merge_requests/$IID/notes" --paginate | jq -r '.[].body' | grep -qF "$MARKER"; then
  echo "reviewed=yes"
else
  echo "reviewed=no"
fi

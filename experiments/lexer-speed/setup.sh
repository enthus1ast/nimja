#!/usr/bin/env bash
# Start a fresh lexer autoresearch run.
#
#   ./setup.sh [tag]
#
# - creates branch autoresearch-lexer/<tag> (default: lexer-YYYYMMDD) from HEAD
# - commits the experiment harness on that branch (so the baseline is clean)
# - writes results.tsv with a header
# - measures the unchanged lexer and records the baseline row
#
# Afterwards run ./experiment.sh "description" after every lexer edit.
#
# This file is FIXED. Do not edit it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TAG="${1:-lexer-$(date +%Y%m%d)}"
BRANCH="autoresearch-lexer/$TAG"

if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "branch $BRANCH already exists; pick another tag: ./setup.sh <tag>" >&2
  exit 1
fi

# Refuse to start on top of unrelated edits, or on top of a lexer edit that
# would silently become part of the baseline.
bad=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  p="${line:3}"
  case "$p" in *" -> "*) p="${p##* -> }" ;; esac
  case "$p" in
    experiments/lexer-speed | experiments/lexer-speed/*) ;;
    tests/interp | tests/interp/*) ;;
    *)
      bad="${bad}    ${p}"$'\n'
      ;;
  esac
done < <(git -C "$ROOT" status --porcelain --untracked-files=all)
if [ -n "$bad" ]; then
  echo "working tree has changes outside experiments/lexer-speed:" >&2
  printf '%s' "$bad" >&2
  echo "commit or stash them first (the baseline must be clean)." >&2
  exit 1
fi

git -C "$ROOT" checkout -q -b "$BRANCH" || exit 1

# Commit the harness if it is not committed yet (first-time setup).
if ! git -C "$ROOT" diff --quiet -- experiments/lexer-speed \
   || [ -n "$(git -C "$ROOT" ls-files --others --exclude-standard -- experiments/lexer-speed)" ]; then
  git -C "$ROOT" add experiments/lexer-speed
  git -C "$ROOT" commit -q -m "lexer autoresearch: harness and program" || exit 1
fi

# Fresh results file (untracked, see .gitignore).
printf 'commit\tcandidate_ms\tbaseline_ms\tspeedup\trt_mbps\tstatus\tdescription\n' \
  > "$HERE/results.tsv"
mkdir -p "$HERE/.work" "$HERE/logs"

echo "branch:  $(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
echo "commit:  $(git -C "$ROOT" rev-parse --short HEAD)"
echo "baseline: measuring the unchanged lexer (about 1 minute) ..."
"$HERE/experiment.sh" --baseline "baseline (unchanged lexer)"
echo
echo "next: edit src/nimja/lexer.nim, then run ./experiment.sh \"what you tried\""

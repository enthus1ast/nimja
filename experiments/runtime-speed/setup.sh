#!/usr/bin/env bash
# Start a fresh runtime-speed autoresearch run.
#
#   ./setup.sh [tag]
#
# - creates branch autoresearch-runtime/<tag> (default: runtime-YYYYMMDD)
# - commits the experiment harness on that branch (so the baseline is clean)
# - writes results.tsv with a header
# - measures the unchanged generator and records the baseline row
#
# Requires a clean working tree outside experiments/runtime-speed: this loop is
# the only experiment editing the tree (the lexer loop lives on its own branch
# and must be finished/reverted first).
#
# This file is FIXED. Do not edit it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TAG="${1:-runtime-$(date +%Y%m%d)}"
BRANCH="autoresearch-runtime/$TAG"

if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "branch $BRANCH already exists; pick another tag: ./setup.sh <tag>" >&2
  exit 1
fi

bad=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  p="${line:3}"
  case "$p" in *" -> "*) p="${p##* -> }" ;; esac
  case "$p" in
    experiments/runtime-speed | experiments/runtime-speed/*) ;;
    tests/interp | tests/interp/*) ;;
    *) bad="${bad}    ${p}"$'\n' ;;
  esac
done < <(git -C "$ROOT" status --porcelain --untracked-files=all)
if [ -n "$bad" ]; then
  echo "working tree has changes outside experiments/runtime-speed:" >&2
  printf '%s' "$bad" >&2
  echo "commit or stash them first (the baseline must be clean; run one" >&2
  echo "autoresearch experiment at a time)." >&2
  exit 1
fi

git -C "$ROOT" checkout -q -b "$BRANCH" || exit 1

if ! git -C "$ROOT" diff --quiet -- experiments/runtime-speed \
   || [ -n "$(git -C "$ROOT" ls-files --others --exclude-standard -- experiments/runtime-speed)" ]; then
  git -C "$ROOT" add experiments/runtime-speed
  git -C "$ROOT" commit -q -m "runtime autoresearch: harness and program" || exit 1
fi

printf 'commit\tcandidate_ns\tbaseline_ns\tspeedup\tstatus\tdescription\n' \
  > "$HERE/results.tsv"
mkdir -p "$HERE/.work" "$HERE/logs"

echo "branch:  $(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
echo "commit:  $(git -C "$ROOT" rev-parse --short HEAD)"
echo "baseline: measuring the unchanged generator (about 30 seconds) ..."
"$HERE/experiment.sh" --baseline "baseline (unchanged generator)"
echo
echo "next: edit src/nimja/parser.nim (or nimjautils/escaping), then run"
echo "      ./experiment.sh \"what you tried\""

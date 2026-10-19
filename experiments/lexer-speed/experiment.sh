#!/usr/bin/env bash
# One autoresearch experiment for the nimja lexer.
#
#   ./experiment.sh "short description"      test the edit in src/nimja/lexer.nim
#   ./experiment.sh --baseline "baseline"    measure the unchanged lexer
#
# Steps:
#   1. verify the fixed harness (sha256) and that only src/nimja/lexer.nim changed
#   2. fast correctness gate: token-for-token comparison with the reference lexer
#   3. A/B compile-time benchmark against the last kept commit (HEAD)
#   4. on a win: full test suites (basic + bugs + lexer unittests), then commit
#      otherwise: revert src/nimja/lexer.nim (the diff is kept in logs/*.patch)
#   5. append a row to results.tsv
#
# Last line of output is always:
#   RESULT status=<keep|discard|wrong|crash> speedup=<x> commit=<sha> reason=<...>
#
# Exit codes: 0 = experiment completed (read the RESULT line), 4 = setup/scope
# problem, 5 = harness problem.
#
# This file is FIXED. Do not edit it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LEXER="$ROOT/src/nimja/lexer.nim"
WORK="$HERE/.work"
BASE="$WORK/baseline"
LOGS="$HERE/logs"
TSV="$HERE/results.tsv"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
MIN_SPEEDUP="${MIN_SPEEDUP:-1.01}"
REPS="${REPS:-5}"
PATCH="$LOGS/$STAMP.patch"

baseline_only=0
if [ "${1:-}" = "--baseline" ]; then
  baseline_only=1
  shift
fi
DESC="${1:-}"
if [ -z "$DESC" ]; then
  echo "usage: ./experiment.sh [--baseline] \"short description\"" >&2
  exit 4
fi

mkdir -p "$WORK" "$LOGS"

die() {
  echo "FATAL: $*" >&2
  exit 4
}

finish() { # status cand base speed rt commit reason
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$6" "$2" "$3" "$4" "$5" "$1" "$DESC" >> "$TSV"
  if [ -s "$PATCH" ]; then
    echo "diff saved: $PATCH"
  fi
  echo "RESULT status=$1 speedup=$4 commit=$6 reason=$7"
  exit 0
}

# ---- 1. integrity of the fixed harness -----------------------------------
if ! (cd "$HERE" && sha256sum -c --quiet harness/FIXED.sha256); then
  die "fixed harness files were modified; restore them with:
    git -C '$ROOT' checkout -- experiments/lexer-speed/harness"
fi

# only src/nimja/lexer.nim may be changed/added by the agent
scope_bad=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  p="${line:3}"
  case "$p" in *" -> "*) p="${p##* -> }" ;; esac
  case "$p" in
    src/nimja/lexer.nim) ;;
    tests/interp | tests/interp/*) ;;
    *) scope_bad="${scope_bad}    ${p}"$'\n' ;;
  esac
done < <(git -C "$ROOT" status --porcelain --untracked-files=all)
if [ -n "$scope_bad" ]; then
  die "out-of-scope changes (only src/nimja/lexer.nim may change):
$scope_bad
  revert them (git checkout -- <path>) and retry."
fi

# ---- 2. extract the current best lexer as the baseline -------------------
mkdir -p "$BASE/nimja"
git -C "$ROOT" show HEAD:src/nimja/lexer.nim > "$BASE/nimja/lexer.nim" ||
  die "cannot read src/nimja/lexer.nim from HEAD"

if cmp -s "$LEXER" "$BASE/nimja/lexer.nim"; then
  if [ "$baseline_only" -eq 0 ]; then
    echo "no changes in src/nimja/lexer.nim -- nothing to test." >&2
    echo "edit the lexer (or use --baseline for a baseline measurement)." >&2
    exit 3
  fi
fi

git -C "$ROOT" diff -- src/nimja/lexer.nim > "$PATCH"

status=""
reason=""
cand=0
base=0
speedup=0
rt=0

# ---- 3. fast correctness gate -------------------------------------------
if ! timeout -s KILL 300 nim c --skipParentCfg:on --hints:off --warnings:off \
    --nimcache:"$WORK/nc-check" -o:"$WORK/check" "$HERE/harness/check.nim" \
    > "$LOGS/$STAMP-check-build.log" 2>&1; then
  status="crash"
  reason="candidate does not compile / check harness build failed ($LOGS/$STAMP-check-build.log)"
  tail -n 20 "$LOGS/$STAMP-check-build.log"
elif ! timeout -s KILL 300 "$WORK/check" > "$LOGS/$STAMP-check.log" 2>&1; then
  status="wrong"
  reason="behaviour differs from the reference lexer ($LOGS/$STAMP-check.log)"
  tail -n 25 "$LOGS/$STAMP-check.log"
fi

# ---- 4. A/B compile-time benchmark --------------------------------------
if [ -z "$status" ]; then
  if ! timeout -s KILL 300 nim c -d:release --skipParentCfg:on \
      --hints:off --warnings:off --nimcache:"$WORK/nc-benchmetric" \
      -o:"$WORK/bench_metric" "$HERE/harness/bench_metric.nim" \
      > "$LOGS/$STAMP-bench-build.log" 2>&1; then
    status="crash"
    reason="bench_metric.nim failed to build ($LOGS/$STAMP-bench-build.log)"
    tail -n 20 "$LOGS/$STAMP-bench-build.log"
  elif ! CAND_LEX="$LEXER" BASE_LEX="$BASE/nimja/lexer.nim" REPS="$REPS" \
      timeout -s KILL 1800 "$WORK/bench_metric" > "$LOGS/$STAMP-bench.log" 2>&1; then
    status="crash"
    reason="benchmark failed or timed out ($LOGS/$STAMP-bench.log)"
    tail -n 20 "$LOGS/$STAMP-bench.log"
  else
    cand=$(awk '$1=="candidate_lex_ms:" {print $2}' "$LOGS/$STAMP-bench.log")
    base=$(awk '$1=="baseline_lex_ms:"  {print $2}' "$LOGS/$STAMP-bench.log")
    speedup=$(awk '$1=="speedup:"           {print $2}' "$LOGS/$STAMP-bench.log")
    rt=$(awk '$1=="rt_mbps:"               {print $2}' "$LOGS/$STAMP-bench.log")
    cand="${cand:-0}"; base="${base:-0}"; speedup="${speedup:-0}"; rt="${rt:-0}"
    grep -E '^(candidate_lex_ms|baseline_lex_ms|speedup|rt_mbps):' \
      "$LOGS/$STAMP-bench.log"
    if ! awk -v s="$speedup" -v m="$MIN_SPEEDUP" 'BEGIN { exit !(s+0 >= m+0) }'; then
      status="discard"
      reason="speedup $speedup < required $MIN_SPEEDUP"
    fi
  fi
fi

# ---- 5. full test suite (only for a would-be keep) ----------------------
if [ -z "$status" ]; then
  gate=""
  if ! timeout -s KILL 1800 testament --colors:off --directory:"$ROOT/tests/" \
      p "basic/*.nim" --skipParentCfg:on > "$LOGS/$STAMP-gate-basic.log" 2>&1; then
    gate="basic suite"
  elif ! timeout -s KILL 1800 testament --colors:off --directory:"$ROOT/tests/" \
      p "bugs/*.nim" --skipParentCfg:on > "$LOGS/$STAMP-gate-bugs.log" 2>&1; then
    gate="bugs suite"
  elif ! timeout -s KILL 300 nim c -r --skipParentCfg:on --hints:off --warnings:off \
      --nimcache:"$WORK/nc-units" -o:"$WORK/lexer_units" "$LEXER" \
      > "$LOGS/$STAMP-gate-units.log" 2>&1; then
    gate="lexer unittests"
  fi
  if [ -n "$gate" ]; then
    status="wrong"
    reason="$gate failed ($LOGS/$STAMP-gate-*.log)"
    tail -n 15 "$LOGS/$STAMP-gate-basic.log" 2>/dev/null
    tail -n 15 "$LOGS/$STAMP-gate-bugs.log" 2>/dev/null
    tail -n 15 "$LOGS/$STAMP-gate-units.log" 2>/dev/null
  else
    status="keep"
    reason="faster and correct"
  fi
fi

if [ "$baseline_only" -eq 1 ] && [ "$status" = "discard" ]; then
  # the untouched baseline reports ~1.0; record it anyway
  status="keep"
  reason="baseline measurement"
fi

# ---- 6. commit or revert ------------------------------------------------
if [ "$status" = "keep" ] && [ "$baseline_only" -eq 0 ]; then
  git -C "$ROOT" add src/nimja/lexer.nim
  if ! git -C "$ROOT" commit -q -m "lexer: $DESC"; then
    status="crash"
    reason="git commit failed"
    git -C "$ROOT" checkout -- src/nimja/lexer.nim
  fi
elif [ "$status" != "keep" ]; then
  git -C "$ROOT" checkout -- src/nimja/lexer.nim
fi

commit=$(git -C "$ROOT" rev-parse --short HEAD)
finish "$status" "$cand" "$base" "$speedup" "$rt" "$commit" "$reason"

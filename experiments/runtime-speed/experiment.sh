#!/usr/bin/env bash
# One autoresearch experiment for nimja's runtime (generated-code) speed.
#
#   ./experiment.sh "short description"
#   ./experiment.sh --baseline "baseline"
#
# Steps:
#   1. verify the fixed harness (sha256) and that only allowed generator files
#      changed (src/nimja/parser.nim, nimjautils.nim, escaping.nim, nimja.nim)
#   2. snapshot the candidate `src` tree and extract the `HEAD` baseline `src`
#   3. build both drivers and run the gate (rendered output must be identical)
#      + the interleaved runtime benchmark (candidate vs baseline)
#   4. if it wins: confirm marginal wins with a second measurement, run the full
#      test suites, then commit; otherwise revert (diff saved to logs/*.patch)
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
WORK="$HERE/.work"
LOGS="$HERE/logs"
TSV="$HERE/results.tsv"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
MIN_SPEEDUP="${MIN_SPEEDUP:-1.01}"
RECHECK_BELOW="${RECHECK_BELOW:-1.03}"
ROUNDS="${ROUNDS:-10}"
PATCH="$LOGS/$STAMP.patch"
ALLOWED=(src/nimja/parser.nim src/nimja/nimjautils.nim src/nimja/escaping.nim src/nimja.nim)

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

# Pin to one core to reduce migration/frequency noise.
TASKSET=""
if command -v taskset >/dev/null 2>&1; then
  TASKSET="taskset -c 0"
fi

die() {
  echo "FATAL: $*" >&2
  exit 4
}

finish() { # status cand_ns base_ns speedup commit reason
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$5" "$2" "$3" "$4" "$1" "$DESC" >> "$TSV"
  if [ -s "$PATCH" ]; then
    echo "diff saved: $PATCH"
  fi
  echo "RESULT status=$1 speedup=$4 commit=$5 reason=$6"
  exit 0
}

# ---- 1. integrity of the fixed harness -----------------------------------
if ! (cd "$HERE" && sha256sum -c --quiet harness/FIXED.sha256); then
  die "fixed harness files were modified; restore them with:
    git -C '$ROOT' checkout -- experiments/runtime-speed/harness"
fi

# only the code-generator/runtime-helper files may be changed
scope_bad=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  p="${line:3}"
  case "$p" in *" -> "*) p="${p##* -> }" ;; esac
  case "$p" in
    src/nimja/parser.nim | src/nimja/nimjautils.nim | \
    src/nimja/escaping.nim | src/nimja.nim) ;;
    tests/interp | tests/interp/*) ;;
    *) scope_bad="${scope_bad}    ${p}"$'\n' ;;
  esac
done < <(git -C "$ROOT" status --porcelain --untracked-files=all)
if [ -n "$scope_bad" ]; then
  die "out-of-scope changes (only parser.nim, nimjautils.nim, escaping.nim and
nimja.nim may change -- run one experiment at a time on a clean tree):
$scope_bad
  revert them (git checkout -- <path>) and retry."
fi

# ---- 2. candidate snapshot + baseline tree ------------------------------
rm -rf "$WORK/cand" "$WORK/base"
mkdir -p "$WORK/cand" "$WORK/base"
cp -a "$ROOT/src" "$WORK/cand/src"
if ! git -C "$ROOT" archive HEAD src | tar -x -C "$WORK/base"; then
  die "cannot extract src from HEAD"
fi
[ -f "$WORK/base/src/nimja/parser.nim" ] || die "baseline src tree is missing"
[ -f "$WORK/cand/src/nimja/parser.nim" ] || die "candidate src tree is missing"

same=0
for f in "${ALLOWED[@]}"; do
  if [ -f "$ROOT/$f" ] && cmp -s "$ROOT/$f" "$WORK/base/$f"; then :; else same=1; fi
done
if [ "$same" -eq 0 ] && [ "$baseline_only" -eq 0 ]; then
  echo "no changes in the generator sources -- nothing to test." >&2
  echo "edit src/nimja/parser.nim (or --baseline for a baseline measurement)." >&2
  exit 3
fi

git -C "$ROOT" diff HEAD -- "${ALLOWED[@]}" > "$PATCH"

status=""
reason=""
cand=0
base=0
speedup=0

# ---- 3. build + gate + benchmark ---------------------------------------
if ! timeout -s KILL 300 nim c -d:release --skipParentCfg:on \
    --hints:off --warnings:off --nimcache:"$WORK/nc-measure" \
    -o:"$WORK/measure" "$HERE/harness/measure.nim" \
    > "$LOGS/$STAMP-measure-build.log" 2>&1; then
  status="crash"
  reason="measure.nim failed to build ($LOGS/$STAMP-measure-build.log)"
  tail -n 20 "$LOGS/$STAMP-measure-build.log"
else
  CAND_SRC="$WORK/cand/src" BASE_SRC="$WORK/base/src" ROUNDS="$ROUNDS" \
    timeout -s KILL 1800 $TASKSET "$WORK/measure" \
    > "$LOGS/$STAMP-bench.log" 2>&1
  rc=$?
  if [ "$rc" -eq 5 ]; then
    status="wrong"
    reason="rendered output differs from the baseline ($LOGS/$STAMP-bench.log)"
    tail -n 25 "$LOGS/$STAMP-bench.log"
  elif [ "$rc" -ne 0 ]; then
    status="crash"
    reason="driver build/run failed, exit $rc ($LOGS/$STAMP-bench.log)"
    tail -n 25 "$LOGS/$STAMP-bench.log"
  else
    cand=$(awk '$1=="candidate_ns:" {print $2}' "$LOGS/$STAMP-bench.log")
    base=$(awk '$1=="baseline_ns:"  {print $2}' "$LOGS/$STAMP-bench.log")
    speedup=$(awk '$1=="speedup:"       {print $2}' "$LOGS/$STAMP-bench.log")
    cand="${cand:-0}"; base="${base:-0}"; speedup="${speedup:-0}"
    grep -E '^(candidate_ns|baseline_ns|speedup):' "$LOGS/$STAMP-bench.log"
    if ! awk -v s="$speedup" -v m="$MIN_SPEEDUP" 'BEGIN { exit !(s+0 >= m+0) }'; then
      status="discard"
      reason="speedup $speedup < required $MIN_SPEEDUP"
    elif awk -v s="$speedup" -v r="$RECHECK_BELOW" 'BEGIN { exit !(s+0 < r+0) }'; then
      # A marginal win is re-measured with the same binaries; both runs must
      # clear the threshold, and the lower value is recorded.
      first="$speedup"
      SKIP_BUILD=1 CAND_SRC="$WORK/cand/src" BASE_SRC="$WORK/base/src" \
        ROUNDS="$ROUNDS" timeout -s KILL 1800 $TASKSET "$WORK/measure" \
        > "$LOGS/$STAMP-recheck.log" 2>&1
      rc2=$?
      s2=$(awk '$1=="speedup:" {print $2}' "$LOGS/$STAMP-recheck.log")
      s2="${s2:-0}"
      speedup=$(awk -v a="$first" -v b="$s2" 'BEGIN { print (a+0 < b+0) ? a : b }')
      echo "marginal win: first=$first recheck=$s2 -> recorded=$speedup"
      if [ "$rc2" -ne 0 ] || \
         ! awk -v s="$s2" -v m="$MIN_SPEEDUP" 'BEGIN { exit !(s+0 >= m+0) }'; then
        status="discard"
        reason="marginal win did not reproduce (first=$first recheck=$s2)"
      fi
    fi
  fi
fi

# ---- 4. full test suite (only for a would-be keep) ----------------------
if [ -z "$status" ]; then
  gate=""
  if ! timeout -s KILL 1800 testament --colors:off --directory:"$ROOT/tests/" \
      p "basic/*.nim" --skipParentCfg:on > "$LOGS/$STAMP-gate-basic.log" 2>&1; then
    gate="basic suite"
  elif ! timeout -s KILL 1800 testament --colors:off --directory:"$ROOT/tests/" \
      p "bugs/*.nim" --skipParentCfg:on > "$LOGS/$STAMP-gate-bugs.log" 2>&1; then
    gate="bugs suite"
  fi
  if [ -n "$gate" ]; then
    status="wrong"
    reason="$gate failed ($LOGS/$STAMP-gate-*.log)"
    tail -n 20 "$LOGS/$STAMP-gate-basic.log" 2>/dev/null
    tail -n 20 "$LOGS/$STAMP-gate-bugs.log" 2>/dev/null
  else
    status="keep"
    reason="faster and correct"
  fi
fi

if [ "$baseline_only" -eq 1 ] && [ "$status" = "discard" ]; then
  status="keep"
  reason="baseline measurement"
fi

# ---- 5. commit or revert ------------------------------------------------
if [ "$status" = "keep" ] && [ "$baseline_only" -eq 0 ]; then
  git -C "$ROOT" add -- "${ALLOWED[@]}"
  if ! git -C "$ROOT" commit -q -m "runtime: $DESC"; then
    status="crash"
    reason="git commit failed"
    git -C "$ROOT" checkout -- "${ALLOWED[@]}"
  fi
elif [ "$status" != "keep" ]; then
  git -C "$ROOT" checkout -- "${ALLOWED[@]}"
fi

commit=$(git -C "$ROOT" rev-parse --short HEAD)
finish "$status" "$cand" "$base" "$speedup" "$commit" "$reason"

## Score + correctness gate for the runtime-rendering experiment.
##
## Compiles `driver.nim` twice -- against the candidate `src` tree and against
## the baseline (`HEAD`) `src` tree -- then:
##
##   1. GATE: runs both with GATE=1 and requires byte-identical rendered output
##      for every template in `templates.nim` (exit 5 on mismatch).
##   2. BENCH: runs both binaries in interleaved rounds, keeps the minimum
##      nanoseconds per workload and sums them:
##        speedup = baseline_ns / candidate_ns
##
## Environment:
##   CAND_SRC, BASE_SRC  nimja `src` directories to compile against
##   ROUNDS              interleaved rounds (default 10)
##   SKIP_BUILD=1        reuse the existing driver binaries (harness dev only)
##   BUILD_TIMEOUT       seconds per `nim c` (default 600)
##   RUN_TIMEOUT         seconds per driver run (default 300)
##
## Exit codes: 0 = ok, 2 = build/run failure, 3 = timeout, 5 = behaviour
## mismatch.
##
## This file is FIXED. Do not modify it.
import std/[os, osproc, strutils, strformat, tables, algorithm, sequtils]

const
  harnessDir = currentSourcePath().parentDir
  repoRoot = harnessDir.parentDir.parentDir.parentDir
  workDir = repoRoot / "experiments" / "runtime-speed" / ".work"

proc envOr(name, fallback: string): string =
  result = getEnv(name)
  if result.len == 0:
    result = fallback

let
  candSrc = envOr("CAND_SRC", workDir / "cand" / "src")
  baseSrc = envOr("BASE_SRC", workDir / "base" / "src")
  rounds = try:
      parseInt(envOr("ROUNDS", "10"))
    except ValueError:
      10
  buildTimeout = envOr("BUILD_TIMEOUT", "600")
  runTimeout = envOr("RUN_TIMEOUT", "300")

proc runCmd(cmd: string): (string, int) =
  execCmdEx(cmd, options = {poUsePath, poStdErrToStdOut})

proc fail(code: int, msg: string, output = "") =
  stderr.writeLine msg
  if output.len > 0:
    stderr.writeLine output
  quit(code)

proc compileDriver(side, srcDir: string): string =
  ## Compile driver.nim against one `src` tree.
  if not fileExists(srcDir / "nimja" / "parser.nim"):
    fail(2, "no nimja sources at " & srcDir)
  let bin = workDir / side / "driver"
  createDir(workDir / side)
  let cmd = "timeout -s KILL " & buildTimeout & " nim c -d:release " &
            "--skipParentCfg:on --hints:off --warnings:off " &
            "--path:" & quoteShell(srcDir) & " " &
            "--nimcache:" & quoteShell(workDir / ("nc-" & side)) & " " &
            "-o:" & quoteShell(bin) & " " &
            quoteShell(harnessDir / "driver.nim")
  let (output, code) = runCmd(cmd)
  if code != 0:
    fail(if code in {124, 137}: 3 else: 2,
         "compiling the " & side & " driver failed (exit " & $code & ")", output)
  result = bin

proc runDriver(bin: string, gate: bool): string =
  let prefix = if gate: "GATE=1 " else: ""
  let cmd = prefix & "timeout -s KILL " & runTimeout & " " & quoteShell(bin)
  let (output, code) = runCmd(cmd)
  if code != 0:
    fail(if code in {124, 137}: 3 else: 2,
         "running the driver failed (exit " & $code & ")", output)
  result = output

proc runBench(bin: string): Table[string, int64] =
  let output = runDriver(bin, gate = false)
  for line in output.splitLines:
    let parts = line.split('\t')
    if parts.len == 3 and parts[0] == "case":
      try:
        result[parts[1]] = parseBiggestInt(parts[2]).int64
      except ValueError:
        fail(2, "cannot parse case line: " & line)
  if result.len == 0:
    fail(2, "no case timings from the driver", output)

proc compareOutput(candOut, baseOut: string) =
  ## Byte-identical rendered output required.
  if candOut == baseOut:
    return
  let a = candOut.splitLines
  let b = baseOut.splitLines
  var shown = 0
  for i in 0 ..< min(a.len, b.len):
    if a[i] != b[i]:
      stderr.writeLine "output differs at line ", i + 1
      stderr.writeLine "  candidate: ", a[i][0 ..< min(200, a[i].len)]
      stderr.writeLine "  baseline:  ", b[i][0 ..< min(200, b[i].len)]
      inc shown
      if shown >= 5:
        break
  if shown == 0:
    stderr.writeLine "output line counts differ: candidate=", a.len,
                     " baseline=", b.len
  quit(5)

# --- build -----------------------------------------------------------------
var candBin, baseBin: string
if getEnv("SKIP_BUILD") == "1":
  candBin = workDir / "cand" / "driver"
  baseBin = workDir / "base" / "driver"
else:
  candBin = compileDriver("cand", candSrc)
  baseBin = compileDriver("base", baseSrc)

# --- 1. correctness gate ---------------------------------------------------
let candGate = runDriver(candBin, gate = true)
let baseGate = runDriver(baseBin, gate = true)
compareOutput(candGate, baseGate)

# --- 2. interleaved benchmark ---------------------------------------------
var
  candMin, baseMin: Table[string, int64]
  names: seq[string]
  ratios: seq[float]
  candTotals, baseTotals: seq[int64]

proc checkWorkloads(cases: Table[string, int64]) =
  if names.len == 0:
    names = toSeq(cases.keys)
    names.sort()
  elif cases.len != names.len:
    fail(2, "workload count changed between runs: " & $cases.len & " vs " & $names.len)
  for name in names:
    if not cases.hasKey(name):
      fail(2, "missing workload in a run: " & name)

proc total(cases: Table[string, int64]): int64 =
  for name in names:
    result += cases[name]

proc updateMin(mins: var Table[string, int64], cases: Table[string, int64]) =
  for name in names:
    let v = cases[name]
    if not mins.hasKey(name) or v < mins[name]:
      mins[name] = v

# The two sides are measured back-to-back within a round and the ratio of that
# pair is recorded; the reported speedup is the MEDIAN of the per-round ratios.
# This cancels slow drift (CPU frequency / system load), which a min-of-mins
# estimator cannot: a single lucky window on one side would bias it.
for r in 0 ..< rounds:
  var c, b: Table[string, int64]
  if (r and 1) == 0:
    c = runBench(candBin)
    b = runBench(baseBin)
  else:
    b = runBench(baseBin)
    c = runBench(candBin)
  checkWorkloads(c)
  checkWorkloads(b)
  let ct = total(c)
  let bt = total(b)
  if ct <= 0 or bt <= 0:
    fail(2, "empty workload total")
  candTotals.add ct
  baseTotals.add bt
  ratios.add bt.float / ct.float
  updateMin(candMin, c)
  updateMin(baseMin, b)

ratios.sort()
let speedup =
  if ratios.len == 0: 0.0
  elif (ratios.len and 1) == 1: ratios[ratios.len div 2]
  else: (ratios[ratios.len div 2 - 1] + ratios[ratios.len div 2]) / 2.0

var candMinSum, baseMinSum: int64
for name in names:
  let c = candMin[name]
  let b = baseMin[name]
  candMinSum += c
  baseMinSum += b
  echo &"case {name}: cand={c} base={b} speedup={b.float / max(c.float, 1.0):.4f}"

var candBest, baseBest: int64 = high(int64)
for i in 0 ..< rounds:
  if candTotals[i] < candBest: candBest = candTotals[i]
  if baseTotals[i] < baseBest: baseBest = baseTotals[i]

echo "ratios: ", ratios.mapIt(&"{it:.4f}").join(" ")
echo "---"
echo &"candidate_ns: {candBest}"
echo &"baseline_ns: {baseBest}"
echo &"speedup: {speedup:.4f}"
echo &"rounds: {rounds}"

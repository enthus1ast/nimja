## Timing / gate body, `include`d by `driver.nim`.
##
## `GATE=1` renders every template once and prints the outputs (the gate diffs
## them between candidate and baseline). Otherwise each timed workload is run
## and the minimum of five samples is printed as
##   case<TAB>name<TAB>cpu-nanoseconds
##
## Timing uses **process CPU time** (CLOCK_PROCESS_CPUTIME_ID), not wall clock:
## the agent's own model server and other experiments may be hammering the CPU
## while this runs, and CPU time measures the work this process actually did.
##
## This file is FIXED. Do not modify it.
import std/[os, strutils, monotimes]

when defined(posix):
  import std/posix

proc cpuNs(): int64 =
  ## CPU time (user+sys) of this process in nanoseconds.
  when defined(posix):
    var ts: Timespec
    if clock_gettime(ClockId(CLOCK_PROCESS_CPUTIME_ID), ts) == 0:
      return int64(ts.tv_sec) * 1_000_000_000'i64 + int64(ts.tv_nsec)
  result = getMonoTime().ticks # non-POSIX fallback: wall clock

include "templates.nim"

var sink: int

proc dumpAll() =
  for (name, rendered) in renderAll():
    echo "### ", name, " ", rendered.len
    echo rendered

template bench(name: string, iters: int, call: untyped) =
  block:
    for _ in 0 ..< (iters div 10): # warm up
      sink += (call).len
    var best = high(int64)
    for _ in 0 ..< 5:
      let t0 = cpuNs()
      var n = 0
      for _ in 0 ..< iters:
        n += (call).len
      let t1 = cpuNs()
      sink += n
      let d = t1 - t0
      if d < best:
        best = d
    echo "case\t", name, "\t", best

if getEnv("GATE") == "1":
  dumpAll()
else:
  let users = @[("alice", 30), ("bob", 17), ("carol", 18)]

  bench("page", 20000, benchPage("Benchmark", benchItems, true))
  bench("page-anon", 20000, benchPage("", benchItems, false))
  bench("static", 40000, benchStatic(1234))
  bench("vars", 40000, benchVars("a", "b", "c", "d", "e", "f", "g", "h"))
  bench("proc", 20000, benchProc("World"))
  bench("bigProc", 30000, benchBigProc("World"))
  bench("constBlock", 40000, benchConstBlock(true))
  bench("mixedConst", 30000, benchMixedConst("tail"))
  bench("escape", 20000, benchEscape(benchUnsafe))
  bench("escape-plain", 30000, benchEscapePlain("plain text 123"))
  bench("loop", 8000, benchLoop(benchItems))
  bench("nested", 30000, benchNested(users, true))
  bench("filters-spaceless", 20000, benchSpaceless(benchFilterText))
  bench("filters-nl2br", 20000, benchNl2br(benchFilterText))
  bench("filters-truncate", 20000, benchTruncate(benchFilterText))
  bench("filters-slugify", 10000, benchSlugify(benchFilterText))
  bench("scalars", 20000, benchScalars(-42, 3.5, true, 'x'))

  if sink < 0:
    echo "unreachable ", sink

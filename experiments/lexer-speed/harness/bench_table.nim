## Human-facing microbenchmark table for the lexer (benchy).
##
## Informational only -- the experiment's score comes from
## harness/bench_metric.nim (compile-time VM lexing). Use this table to see
## where the time goes while you develop an idea.
##
##   nim c -r -d:release --skipParentCfg:on \
##     --path:$HOME/projects/benchy/src harness/bench_table.nim
##
## This file is FIXED.
import benchy

# explicit relative import: immune to machine-wide --path shadowing
import ../../../src/nimja/lexer

const
  corpus = staticRead("corpus/corpus.txt")
  readme = staticRead("../../../readme.md")
  bigmaster = staticRead("../../../playground/bigmaster.nimja")

proc lexCount(s: string): int =
  for t in lex(s):
    result += t.value.len

var acc: int

timeIt "runtime: whole corpus (2.0 MB)":
  for i in 0 ..< 4:
    acc += lexCount(corpus)

timeIt "runtime: readme.md (40 KB, static heavy)", 300:
  acc += lexCount(readme)

timeIt "runtime: bigmaster.nimja (44 KB, mixed)", 300:
  acc += lexCount(bigmaster)

timeIt "runtime: 8 variables (small)", 20_000:
  acc += lexCount("{{a}}{{b}}{{c}}{{d}}{{e}}{{f}}{{g}}{{h}}")

timeIt "runtime: comments/evals (small)", 20_000:
  acc += lexCount("{# a comment #}{% if x %}<p>hi</p>{% end %}{{x}}{# c #}")

if acc < 0:
  echo "unreachable ", acc

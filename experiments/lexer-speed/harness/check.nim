## Fast correctness gate for a candidate lexer.
##
## Compares the candidate `src/nimja/lexer.nim` against the frozen reference
## lexer (harness/reference/lexer_reference.nim) token by token -- kind, value,
## line and column, and exception behaviour:
##
##   1. the fixed 2 MB benchmark corpus (as one input)
##   2. every real `*.nimja` template in the repo, one input per file
##   3. hand-picked edge cases
##   4. structured random inputs with a fresh random seed every run
##
## The lexer itself prints "Endchar expected..." warnings to stdout for
## unterminated blocks; stdout is redirected to /dev/null here and all harness
## reporting goes to stderr.
##
## This file is FIXED. Exit code 0 = behaviour identical, 1 = mismatch.
import std/[strutils, random, os, posix]
import cases

# Silence the lexer's own stdout warnings (they are behaviour-neutral noise).
let devnull = open("/dev/null", O_WRONLY)
if devnull >= 0:
  discard dup2(devnull, cint(1))
  discard close(devnull)

var
  mismatches = 0
  checks = 0

# 1. the benchmark corpus itself must lex cleanly (ct_lex needs that)
let corpusTokens = dumpCandidate(corpus)
if corpusTokens.len > 0 and corpusTokens[^1].startsWith("RAISE"):
  stderr.writeLine "corpus: candidate lexer raises on the benchmark corpus: ",
                   corpusTokens[^1]
  inc mismatches
inc checks

# 2. every real template in the repo, separately (file-boundary behaviour)
let files = repoFiles()
for i, f in files:
  inc checks
  if not compareOne("file", i, readFile(f)):
    stderr.writeLine "  file: ", f
    inc mismatches

# 3. edge cases + 4. random inputs
randomize()
let seed = rand(1_000_000_000)
var r = initRand(seed)
var inputs = edgeCases()
for x in randomInputs(r, 2500):
  inputs.add x
stderr.writeLine "random seed: ", seed
for i, s in inputs:
  inc checks
  if not compareOne("edge/random", i, s):
    inc mismatches
    if mismatches >= 15:
      stderr.writeLine "stopping after 15 mismatches"
      break

stderr.writeLine "check: ", checks, " inputs compared, ", mismatches, " mismatches"
if mismatches > 0:
  stderr.writeLine "check: FAIL"
  quit(1)
stderr.writeLine "check: OK"

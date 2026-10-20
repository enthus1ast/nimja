## Shared helpers for the lexer experiment: canonical token dumps for the
## candidate lexer and the frozen reference lexer, the fixed corpus, the repo's
## real templates and a deterministic random input generator.
##
## This file is FIXED (see harness/FIXED.sha256). Do not modify it.
import std/[strutils, os, random]

# Import the candidate by an explicit relative path. `nimja/lexer` would be
# resolved via the module search path, which a machine-wide nim.cfg can shadow
# (this repo lives next to another nimja checkout).
import ../../../src/nimja/lexer
import reference/reference_api

const
  repoRoot* = currentSourcePath().parentDir.parentDir.parentDir.parentDir
  corpus* = staticRead("corpus/corpus.txt")

const maxTokens* = 500_000

proc canon(kind, value: string, line, col: int): string =
  ## One token as a single comparable line. `escape` makes the value safe to
  ## print and compare (it escapes control chars, quotes and high bytes).
  kind & "|" & $line & "|" & $col & "|" & escape(value)

proc dumpCandidate*(s: string): seq[string] =
  try:
    for t in lex(s):
      result.add canon($t.kind, t.value, t.line, t.col)
      if result.len > maxTokens:
        result.add "TOOMANY"
        break
  except CatchableError as e:
    result.add "RAISE:" & $e.name

proc dumpReference*(s: string): seq[string] =
  referenceTokens(s)

proc compareOne*(label: string, idx: int, s: string): bool =
  ## Compares one input, prints a report on mismatch. Returns true when equal.
  let refToks = dumpReference(s)
  let cand = dumpCandidate(s)
  if refToks == cand:
    return true
  let shown = escape(s)
  stderr.writeLine "MISMATCH: ", label, " input #", idx, " (", s.len, " bytes): ",
       shown[0 ..< min(300, shown.len)]
  var diff = -1
  for i in 0 ..< min(refToks.len, cand.len):
    if refToks[i] != cand[i]:
      diff = i
      break
  if diff >= 0:
    stderr.writeLine "  first diff at token ", diff
    stderr.writeLine "    reference: ", refToks[diff]
    stderr.writeLine "    candidate: ", cand[diff]
  else:
    stderr.writeLine "  token counts differ: reference=", refToks.len, " candidate=", cand.len
  false

proc compareInputs*(label: string, inputs: seq[string]): int =
  ## Returns the number of mismatches; prints the first few reports.
  for i, s in inputs:
    if not compareOne(label, i, s):
      inc result
      if result >= 5 and inputs.len > 10:
        stderr.writeLine label, ": stopping after 5 mismatch reports"
        break

proc repoFiles*(): seq[string] =
  ## The repo's own templates (real-world input), plus the readme (mostly
  ## static text). Directories that only contain build output are skipped.
  for base in ["tests", "examples", "playground", "bench"]:
    for p in walkDirRec(repoRoot / base, yieldFilter = {pcFile}):
      if p.endsWith(".nimja") and not p.contains("nimcache"):
        result.add p
  result.add repoRoot / "readme.md"

proc edgeCases*(): seq[string] =
  ## Hand-picked inputs that hit the lexer's odd corners. This list is part of
  ## the behaviour spec: the candidate must match the reference on all of them.
  const cases = [
    "", " ", "\n", "\r\n", "\r", "\t",
    "{", "}", "{{", "}}", "{%", "%}", "{#", "#}",
    "{{}}", "{%%}", "{##}", "{{ }}", "{% %}", "{# #}",
    "{{x}}", "{{ x }}", "{{-x-}}", "{%- if x -%}", "{#- c -#}",
    "a{{b}}c", "foo {baa}", "{ nope }", "{nope", "nope}",
    "{}", "{ }", "{{ } }}", "{{ x }", "{% x %", "{# x #",
    "{{foo\\}\\}}}", "{{foo\\}}}", "{{foo\\}}",
    "\\", "\\\\", "abc\\", "{{a\\}}", "{{a\\", "{{a\\\\}}",
    "{{\"", "{{\"a\"}}", "{{\"a\\\"b\"}}", "{{\"a\\\\\"}}",
    "{{\"\"\"abc\"\"\"}}", "{{\"\"\"abc\"\"}}", "{{\"\"\"abc}}",
    "{{\"\"\"a\"b\"\"\"}}", "{{ \"}}\" }}", "{{ '}}' }}",
    "{% if \"%}\" %}", "{# {{x}} #}", "{# #} #}", "{{a{#b#}c}}",
    "{% {% %}", "{% if x %}a{% end %}", "{%raw%}{{x}}{%endraw%}",
    "\n{{a}}\n", "{{a}}\r\n", "a\nb\r\nc", "{{a}}\n{{b}}",
    "{{ }}  ", "  {{ x }}", "\t{{ x }}\t", "{{ x }}\n",
    "ä", "日本語", "🎉",
    "\xc2\xa0{{a}}\xc2\xa0",   # NBSP around a variable
    "\xe3\x80\x80{{a}}\xe3\x80\x80", # ideographic space
    "a\x00b", "{{a\x00b}}", "{{\"a\x00b\"}}",
    "{{x}}}}", "{{{{x}}", "%}{%", "##{#", "{%x%}{#y#}{{z}}",
    "a{b}c{d}e", "{{a}}{#b#}{%c%}text", "{#\n#}", "{%\n%}", "{{\n}}",
    "{{a\nb}}", "{% a\nb %}", "{# a\nb #}",
  ]
  for c in cases:
    result.add c

const fragAlpha = "abcXYZ019 \t\r{}%#\"'\\/<>-_=.:,;!?()[]&|*+$@~^`\n"

proc randomInputs*(r: var Rand, count: int): seq[string] =
  ## Structured random templates plus raw noise. Fresh seed every run (printed
  ## by check.nim) so the lexer cannot be special-cased for it.
  const lone = ["{", "}", "{{", "}}", "{%", "%}", "{#", "#}"]
  const ws = [" ", "\t", "\n", "\r\n", "\xe3\x80\x80"]
  for i in 0 ..< count:
    var s = newStringOfCap(256)
    let blocks = r.rand(1 .. 10)
    for b in 0 ..< blocks:
      case r.rand(0 .. 7)
      of 0: # plain text, may contain single braces
        for _ in 0 ..< r.rand(0 .. 40):
          s.add fragAlpha[r.rand(0 .. fragAlpha.high)]
      of 1: # variable
        s.add "{{"
        for _ in 0 ..< r.rand(0 .. 16):
          s.add fragAlpha[r.rand(0 .. fragAlpha.high)]
        s.add "}}"
      of 2: # eval
        s.add "{%"
        for _ in 0 ..< r.rand(0 .. 16):
          s.add fragAlpha[r.rand(0 .. fragAlpha.high)]
        s.add "%}"
      of 3: # comment
        s.add "{#"
        for _ in 0 ..< r.rand(0 .. 20):
          s.add fragAlpha[r.rand(0 .. fragAlpha.high)]
        s.add "#}"
      of 4: # quoted string, possibly escaped or triple quoted
        var inner = ""
        for _ in 0 ..< r.rand(0 .. 12):
          case r.rand(0 .. 3)
          of 0: inner.add '\"'
          of 1: inner.add '\\'
          of 2: inner.add '\n'
          else: inner.add fragAlpha[r.rand(0 .. fragAlpha.high)]
        let q = if r.rand(0 .. 1) == 0: "\"" else: "\"\"\""
        s.add "{{" & q & inner & q & "}}"
      of 5: # unmatched opener / closer
        s.add lone[r.rand(0 .. lone.len - 1)]
      of 6: # raw bytes (may be invalid utf-8, the lexer works on bytes)
        for _ in 0 ..< r.rand(1 .. 20):
          s.add chr(r.rand(0 .. 255))
      else: # newline / whitespace run
        for _ in 0 ..< r.rand(1 .. 6):
          s.add ws[r.rand(0 .. ws.len - 1)]
    if s.len > 4096: # keep individual inputs small
      s.setLen(4096)
    result.add s

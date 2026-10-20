## Namespace wrapper around the frozen reference lexer.
##
## `import x as y` still makes the imported symbols visible unqualified in Nim,
## so importing the reference lexer directly from cases.nim makes `lex(...)`
## ambiguous. This wrapper is the only place that touches the reference lexer.
##
## This file is FIXED. Do not modify it.
import std/strutils

import ./lexer_reference

const maxTokens = 500_000

proc canon(kind, value: string, line, col: int): string =
  ## Keep in sync with `canon` in harness/cases.nim.
  kind & "|" & $line & "|" & $col & "|" & escape(value)

proc referenceTokens*(s: string): seq[string] =
  ## Canonical token dump of the reference lexer for one input.
  try:
    for t in lex(s):
      result.add canon($t.kind, t.value, t.line, t.col)
      if result.len > maxTokens:
        result.add "TOOMANY"
        break
  except CatchableError as e:
    result.add "RAISE:" & $e.name

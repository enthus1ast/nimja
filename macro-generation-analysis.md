# Nimja macro generation — analysis & improvements

Scope: the Nim code that `compileTemplateStr` / `compileTemplateFile` /
`tmpls` / `tmplf` generate (`src/nimja/parser.nim`), using Nimja's own debug
outputs.

Toolchain: Nim 2.2.4. All outputs below were produced with the debug defines
from the readme:

```bash
nim c -r --path:src -d:dumpNwtAst      yourfile.nim   # NwtNode tree
nim c -r --path:src -d:dumpNwtAstPretty yourfile.nim  # tree as JSON
nim c -r --path:src -d:dumpNwtMacro    yourfile.nim   # generated Nim AST
```

Pipeline recap: `lex` → `parseFirstStep` (FSNode) →
`parseSecondStep` (NwtNode) → `astAst` (Nim AST). `compile` fills blocks,
resolves `self.<block>` and condenses strings; `doCompile` then emits the
generated statements (`result &= "..."`, `result &= $x`, control flow).

---

## F-1 (APPLIED) strings made adjacent by `self.` inlining were not re-condensed

**Problem.** `compile` did `fillBlocks(base).condenseStrings()` and *then*
`resolveSelf(...)`. Splicing a `self.<block>` body in turns it back into
adjacent `NStr` nodes, but nothing merged them again, so each became its own
runtime `result &=` call.

Reproduce with `_base.nimja` / `_child.nimja` (child overrides `title`, base's
body prints `{{self.title}}`):

*Before* (`-d:dumpNwtMacro`):
```nim
when result is string:
  result = newStringOfCap(48)
result &= "<html>child-title\nB:"
result &= "child-title"
result &= "</html>\n"
```

*After* moving the single Nwt-stage condense to run after `resolveSelf`:
```nim
when result is string:
  result = newStringOfCap(48)
result &= "<html>child-title\nB:child-title</html>\n"
```

Three appends collapse to one, output unchanged. The same applies to
`self_multiblock.nimja` (two `&=` of `"title"` merge into one). This directly
serves the goal of saving runtime `&=` calls.

**Change applied** (`parser.nim`, `compile`): `fillBlocks` and `resolveSelf`
now run first, then a single `condenseStrings()`:
```nim
if blockToRender == "":
  result = fillBlocks(templateCache[0])
else:
  result = fillBlocks(blocks[blockToRender])   # + error for unknown block
var resolving = initHashSet[string]()
result = resolveSelf(result, resolving).condenseStrings()
```
The number of `condenseStrings` passes is unchanged (FS stage + Nwt stage);
only the Nwt-stage position moved. All existing tests still pass
(41 basic + 12 bug tests).

---

## F-2 `guessedStringLen` (the `newStringOfCap` size) is unreliable

`guessedStringLen` is a `compileTime` global (`parser.nim:80`) incremented as a
**side effect** of `parseSecondStepOne` for every `FsStr` (`parser.nim:325`),
reset in `doCompile` and turned into `newStringOfCap(len)`.

Because it is a side effect of parsing, it is wrong in two directions:

**(a) Disabled on cache hits.** `loadCache` returns `cacheNwtNode[str]` without
calling `parseSecondStep`, so no strings are counted on a cache hit. Compiling
the *same* template twice:

```nim
proc a(): string = compileTemplateStr("AAAA{{1}}BBBB")
proc b(): string = compileTemplateStr("AAAA{{1}}BBBB")
```
```nim
# a():                                  # b() (cache hit):
when result is string:                  when result is string:
  result = newStringOfCap(8)              result = newStringOfCap(0)
```
The second render silently loses its pre-allocation.

**(b) Counts overridden/unchosen content.** For the extends example above the
real static length is 39, but `newStringOfCap(48)` was emitted, because the
base template's overridden `base-title`/`base-body` literals are counted too.
Both branches of `if`/`else` are likewise summed.

**Recommendation.** Drop the parse-time counter and compute the size from the
**final** `NwtNode` tree in `compile` (the tree that is actually emitted),
e.g. a small recursive `sum NStr.strBody.len`. That is cache-safe and matches
the output; loop bodies / branch alternatives still count once (unavoidable,
but no longer actively wrong). It also removes the global mutable state.

---

## F-3 template-defined `proc`/`func` bodies are not pre-allocated, and leak into the outer cap

For
```nim
proc render(name: string): string =
  compileTemplateStr("{% proc greet(n: string): string = %}Hi {{n}}!{% end %}{{greet(name)}}")
```
the generated code is:
```nim
when result is string:
  result = newStringOfCap(4)      # <-- this is greet's literal length
proc greet(n: string): string =
  result &= "Hi "                 # <-- no pre-allocation for greet's result
  result &= $n
  result &= "!"
result &= $greet(name)
```
Two issues:
1. `greet`'s own `result` never gets a `newStringOfCap`, although its static
   length is known at compile time.
2. `guessedStringLen` counted `greet`'s literals (`"Hi "`, `"!"` = 4) and used
   them for the **outer** render's buffer, which has no literals at all.

**Recommendation.** Scope the static length per generated proc: compute the
body length in `astProc` (`parser.nim:494`) and emit a `newStringOfCap` at the
top of that proc's body; exclude the proc body from the outer counter.

---

## F-4 `$` is emitted unconditionally

`astVariable` (`parser.nim:360`) always generates `result &= $<expr>`. When the
expression is already a string this is unnecessary, e.g. the call to a
template proc whose return type is `string`:

```nim
result &= $greet(name)     # greet(name) is already a string
```

A macro cannot know the type of an arbitrary expression at expansion time, but
a small helper avoids the call while staying type-safe:

```nim
template appendValue(dst: var string, value: untyped) =
  when value is string: dst.add value
  else: dst.add $value
```
Then emit `appendValue(result, expr)` instead of the raw `&=`/`$` pair. This
also removes the odd `$ do: expr` shape (see F-6). Low risk, measurable on
variable-heavy templates.

---

## F-5 `newStringOfCap(0)` is still emitted

For variable-only templates the generated code starts with
```nim
when result is string:
  result = newStringOfCap(0)
```
which is a no-op. `doCompile` (`parser.nim:834`/`842`) could skip
`generatePreallocatedStringDef` when the computed length is `0`, or use a small
minimum heuristic (e.g. number of variable appends) if a guess is wanted.

---

## F-6 `$` is applied to a `StmtList`, producing `$ do: ...`

`astVariable` does `newCall(newIdentNode("$"), parseStmt(body))`. `parseStmt`
returns a `StmtList`, so the dump shows:
```nim
result &=
    `$` do:
  x
```
instead of `result &= $x`. It compiles fine, but unwrapping a single-expression
`StmtList` (`if varb.len == 1 and varb[0].kind notin {nnkStmtList, nnkDo,
nnkBlockStmt}: varb = varb[0]`) yields cleaner, more predictable code. Cosmetic
(combined with F-4 it disappears anyway).

---

## F-7 inherent limits (documented, not “bugs”)

- Loop bodies count their literals once, so `newStringOfCap` under-estimates
  for long loops — iteration count is unknown at compile time.
- Only one branch of `if`/`case` runs, so summing both over-estimates. A future
  `newStringOfCap` from the final tree (F-2) could take the max branch instead
  of the sum, but the current behavior is acceptable.

---

## Summary

| # | Finding | Impact | Status |
|---|---------|--------|--------|
| F-1 | `self.` inlining re-created adjacent strings, no re-condense | extra runtime `&=` | **applied** |
| F-2 | `guessedStringLen` wrong on cache hits / overridden blocks | wrong `newStringOfCap` | recommended |
| F-3 | template procs/funcs get no pre-allocation; leak into outer cap | wrong/unused pre-allocation | recommended |
| F-4 | unconditional `$` for string expressions | extra call | recommended |
| F-5 | `newStringOfCap(0)` emitted | dead statement | recommended |
| F-6 | `$` applied to `StmtList` (`$ do:`) | cosmetic | recommended |
| F-7 | loops/branches can't be sized statically | inherent | — |

Only F-1 was changed; it keeps the two-pass condense strategy (FS stage +
Nwt stage) intact and was verified with the full suite:
`tests/basic` 41 passed, `tests/bugs` 12 passed.

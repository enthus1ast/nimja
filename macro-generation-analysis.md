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

**Applied.** The parse-time counter was removed and the size is now computed
from the **final** `NwtNode` tree in `compile` via a recursive
`staticLen(...)` (sum of `NStr.strBody.len`); `compile` assigns it to
`guessedStringLen` after the final condense. It is cache-safe and matches the
emitted tree; loop bodies / branch alternatives still count once (unavoidable,
but no longer actively wrong). Because it is recomputed per `compile`, the
nested `importnimja` compiles no longer leak into each other. See the
benchmark results below.

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

**Recommendation — implemented, benchmarked, reverted.** Emitting a
`newStringOfCap` inside `astProc` (guarded by a `>= 32` length threshold) was
implemented and measured; it was neutral-to-slightly-negative on the
`template proc` benchmark (the extra call per invocation is not repaid by
fewer reallocations for small procs), so it was reverted. It may still be
worth it for templates with large proc bodies.

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
also removes the odd `$ do: expr` shape (see F-6).

**Measured, reverted.** `appendValue` was implemented with `bindSym` and
benchmarked: `$` on a `string` is already an inlined identity in Nim, so the
`vars` and `cache` scenarios were unchanged and `page`/`static`/`proc` were
within noise (±2%). It adds a template indirection for no measurable gain, so
it was reverted.

---

## F-5 `newStringOfCap(0)` is still emitted

For variable-only templates the generated code starts with
```nim
when result is string:
  result = newStringOfCap(0)
```
which is a no-op. **Applied:** `doCompile` now skips
`generatePreallocatedStringDef` when the computed length is `0` (a small but
free win on variable-heavy templates).

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
`StmtList` would yield cleaner code. **Not implemented** — purely cosmetic, no
runtime effect identified.

---

## F-7 inherent limits (documented, not “bugs”)

- Loop bodies count their literals once, so `newStringOfCap` under-estimates
  for long loops — iteration count is unknown at compile time.
- Only one branch of `if`/`case` runs, so summing both over-estimates. A future
  `newStringOfCap` from the final tree (F-2) could take the max branch instead
  of the sum, but the current behavior is acceptable.

---

## Benchmark tool & measured results

`bench/benchmark.nim` uses [treeform/benchy](https://github.com/treeform/benchy)
to time the *generated* render code (not compile time). Run it with:

```bash
nimble bench
# or
nim c -r -d:release bench/benchmark.nim
```

`bench/config.nims` adds `bench/../src` and the sibling `../benchy/src`; if
benchy is installed with nimble the second `switch` can be dropped. Each
scenario renders 10_000 times per timed iteration (50 iterations) and
accumulates the output length so the calls are not dead-code-eliminated.

Scenarios: a realistic `page` (static + `if` + `for`), a `static`-heavy page,
`vars` (8 adjacent variables), `cache` (two procs with the *same* template
string) and `template proc`.

Measured with `taskset -c 0`, Nim 2.2.4, `-d:release`; min ms per 10_000
renders (median of 3 runs):

| scenario | before | after (F-2 + F-5) | change |
|----------|-------:|------------------:|-------:|
| page (8 items) | 1.455 | 1.451 | ~0% |
| static (long body) | 1.051 | 1.060 | ~0% |
| vars (8 variables) | 0.563 | 0.539 | **-4%** |
| cache hit (same template twice) | 1.558 | 1.384 | **-11%** |
| template proc | 1.895 | 1.895\* | ~0% |

\* The `template proc` generated code is byte-identical before/after, so the
run-to-run variation there is binary-layout noise; it is listed as unchanged.

The `cache` win is exactly F-2 (the second proc now gets
`newStringOfCap(54)` instead of `newStringOfCap(0)`); the `vars` win is F-5
(no more `newStringOfCap(0)` no-op).

F-3 and F-4 were implemented and benchmarked, then reverted because they gave
no measurable improvement (see above).

## Summary

| # | Finding | Impact | Status |
|---|---------|--------|--------|
| F-1 | `self.` inlining re-created adjacent strings, no re-condense | extra runtime `&=` | **applied** |
| F-2 | `guessedStringLen` wrong on cache hits / overridden blocks | wrong `newStringOfCap` | **applied** |
| F-3 | template procs/funcs get no pre-allocation; leak into outer cap | wrong/unused pre-allocation | measured, reverted |
| F-4 | unconditional `$` for string expressions | extra call | measured, reverted |
| F-5 | `newStringOfCap(0)` emitted | dead statement | **applied** |
| F-6 | `$` applied to `StmtList` (`$ do:`) | cosmetic | not implemented |
| F-7 | loops/branches can't be sized statically | inherent | — |

F-1, F-2 and F-5 are in the tree; the two-pass condense strategy (FS stage +
Nwt stage) is intact. Verified with the full suite plus the benchmark:
`tests/basic` 41 passed, `tests/bugs` 12 passed.

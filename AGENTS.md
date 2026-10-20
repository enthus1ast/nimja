# AGENTS.md — Nimja

Nimja is a **compiled, statically typed template engine** for Nim (Jinja2/Twig
inspired). Templates are turned into Nim AST at **compile time**; there is no
runtime template interpreter. This file is the entry point for agents working
in this repo.

## Pipeline (memorize this)

```
template text
  └─ lex()                 src/nimja/lexer.nim   → Token (NwtString/Variable/Comment/Eval)
       └─ parseFirstStep() src/nimja/parser.nim   → FSNode  (flat, delimiters resolved)
            └─ parseSecondStep()                  → NwtNode (nested tree)
                 └─ astAst()/astAstOne()          → Nim AST (NNimNode)
```

- `{{ x }}`  → `result &= $(x)` (variable)
- `{% stmt %}` → `parseStmt(stmt)` (arbitrary Nim statement)
- `{% if/for/while/case/when/proc/func/macro/scope/block/extends %}` are parsed
  into the corresponding control structure / macro output.

`compileTemplateStr` / `compileTemplateFile` are **macros**: they must be called
inside a proc/func/iterator and append to the implicit `result` (or to
`varname`). `tmpls` / `tmplf` are inline shorthands that create their own
variable.

## Layout

| Path | Purpose |
|------|---------|
| `src/nimja.nim` | public umbrella module; exports `compileTemplateStr`, `compileTemplateFile`, `getScriptDir`, `tmpls`, `tmplf`, `nimjautils`, `os` |
| `src/nimja/parser.nim` | lexing orchestration, FSNode/NwtNode types, AST generation, public macros |
| `src/nimja/lexer.nim` | character-level lexer + its own unittests (`when isMainModule`) |
| `src/nimja/nimjautils.nim` | template helpers: `loop`, `cycle`, `~`, `truncate`, `slugify`, `spaceless`, `nl2br`, `includeRaw*`, `?`, `|` |
| `src/nimja/sharedhelper.nim` | compile-time/runtime `read` + `getScriptDir` used by `baseDir` |
| `src/nimja/hcrutils.nim` | hot-code-reload helpers (dynlib watching) |
| `tests/basic/*.nim` | main test suite (testament) |
| `tests/bugs/*.nim` | regression tests for fixed bugs + compile-error specs |
| `tests/templates`, `tests/basic/**/*.nimja` | template fixtures |
| `examples/` | fromReadme, prologue/jester, dynlib, hcr examples |
| `experiments/runtime-speed/` | autonomous runtime-speed research loop; read its `program.md` |
| `readme.md` | the user manual (large; the source of truth for features) |

## Build & test

Nim 2.x is required (`nimble` version pins `nim >= 1.4.8`).

```bash
nimble tests                 # runs basic/ + bugs/ + compiles all examples
nimble bench                 # render benchmarks (needs treeform/benchy, see bench/)
# focused:
testament --directory:"./tests/" p "basic/*.nim"
testament --directory:"./tests/" p "bugs/*.nim"
# single file:
nim c -r --path:src tests/basic/test_simple.nim
# lexer's own unittests:
nim c -r --path:src src/nimja/lexer.nim
```

`tests/config.nims` already adds `--path:../src`, so tests import `../../src/nimja`.

Useful compile-time defines (from the readme):

```bash
-d:dumpNwtAst -d:dumpNwtAstPretty -d:dumpNwtMacro
-d:nwtCacheOff -d:noPreallocatedString -d:noCondenseStrings
```

## Writing tests

- Add feature tests to `tests/basic/`, bug regressions to `tests/bugs/`.
- Runnable tests use `discard """ joinable: false """` (templates must not be
  fused across tests) plus `unittest` or `doAssert`.
- Templates must be compiled **inside a proc**:
  ```nim
  proc render(x: int): string =
    compileTemplateStr("{{x}}")     # appends to `result`
  ```
- **Compile-error tests** use a testament spec. The error is usually reported
  in `parser.nim` (or `lexer.nim`), so set `file:`:
  ```nim
  discard """
    joinable: false
    errormsg: '''unhandled exception: uneven when's'''
    file: "parser.nim"
  """
  include ../../src/nimja/parser
  const foo = compile("{% when true %}B")
  ```
  For errors raised during AST generation (e.g. `error "..."` from
  `astVariable`) call `compileTemplateStr(...)` in a proc and set
  `file: "parser.nim"`.
- `context` is a **named** parameter (`context = {node: rax, baa: foo}`); it
  creates template aliases. It cannot be passed positionally, and cannot
  contain procs/funcs.
- When a template `extends`, only strings/comments may precede the `extend`
  and all content must live in `{% block %}`s.

## Working rules

0. **The `experiments/runtime-speed/` harness is fixed.** When running that
   loop, edit only `src/nimja/parser.nim`, `src/nimja/nimjautils.nim`,
   `src/nimja/escaping.nim` or `src/nimja.nim`; the harness verifies itself
   with `harness/FIXED.sha256` and rejects out-of-scope changes. See
   `experiments/runtime-speed/program.md`.
1. **Verify before you edit.** Read the relevant `readme.md` section and the
   source, then reproduce the behaviour with a small harness. Do not trust
   comments blindly.
2. **Add a regression test for every bug.** Put it in `tests/bugs/` and make it
   fail before the fix, pass after. This is the durable record of the fix.
3. **Remove false claims.** If a doc/comment contradicts verified behaviour,
   correct or delete it.
4. **After a fix, run both suites** (`basic/*.nim` and `bugs/*.nim`) and keep
   the existing basic tests green.
5. Clean up scratch files and generated binaries; add new test binaries to
   `.gitignore` if they are not already covered.

## Known gotchas (verified)

- `{% case %}` chokes on a string node (e.g. the newline of a nicely formatted
  template) between `{% case expr %}` and the first `{% of ... %}`: it reports
  `should not happen: str`. Put `{% of ... %}` on the same line as
  `{% case ... %}`.
- A machine-wide `$HOME/projects/nim.cfg` (Nimby) adds `--path:nimja/src`,
  which can shadow *this* checkout for path-based imports like
  `import nimja/lexer` (verified: it resolved to `~/projects/nimja/src` even
  with an absolute `--path:`). The test suite is unaffected (it uses relative
  imports), but ad-hoc harnesses should use relative imports or
  `--skipParentCfg:on`.

- `blocks` and the `cacheNwtNode*` tables are **compile-time globals** shared by
  every template compiled in the same module; block bodies are re-registered on
  each `compile`, and `self.<block>` is resolved per `compile` invocation.
- Whitespace control works for `{%- -%}`, `{{- -}}` and `{#- -#}`.
- `baseDir` must be set (`getScriptDir()`) for `extends`/`importnimja`. Import
  paths resolve against `baseDir`, not the importing file.
- `errorOnUnevenBlocks` checks `if`, `for`, `while`, `when` and `block` only;
  unbalanced `case`/`scope`/`proc` fall through to Nim errors.
- Template errors report **file, line and column**. Positions live in
  `Token`/`FSNode`/`NwtNode` (compile-time only, never emitted into the AST);
  `templateError` raises `NimjaError` and `doCompile` converts it via
  `reportNimjaError` (`setLineInfo` + `error`). Calling `compile` directly still
  raises a catchable `NimjaError` (a `ValueError`). See `error-reporting.md`.
- `{% importnimja "path" %}` sees the parent's variables. An optional
  `"block"` picks a block; an optional `{name: value}` context (`NImportContext`)
  emits `template name = value` aliases inside a `block`, so they are scoped to
  the imported template only.
- `compileTemplateStr(str)` accepts a string literal, a `const` string or a
  folded static expression (`staticStr` resolves consts via `getImpl`); a
  runtime `let`/`var` argument errors instead of silently using its name.
- HTML escaping lives in `src/nimja/escaping.nim` (`HTMLSafeStr`, `htmlEscape`,
  `safe`, `e`). The scan for characters to escape is vectorized with SSE2 via
  `nimsimd` (x86-64 baseline, no runtime check; scalar fallback for other
  targets) and the output is sized exactly — the earlier `len * 3` buffer
  **overflowed** on `&`/`"` runs (6 bytes per char). `compileTemplateStr`/`File`/`tmpls`/`tmplf` take an
  `escapeWith` proc (`escapeWith = htmlEscape` for HTML, any proc for
  URL/JS/...). Escaping is idempotent; the generated call is `nwtStrProc`,
  defaulting to `$` so escaping costs nothing when unused.
- `condenseStrings` runs twice on purpose (FS stage, then Nwt stage after
  `fillBlocks`/`self` resolution) to merge adjacent strings and reduce runtime
  `&=` calls. The output pre-allocation size (`newStringOfCap`) is computed
  from the final node tree by `staticLen` in `compile`.
- `astAst` groups maximal runs of `NStr`/`NVariable`; `astRun` emits
  `when v is static:` so the compiler folds `const` variables into the
  neighbouring literal (issue #53, see `const-folding.md`). All-static runs
  fold to one string; mixed runs fold each const with its preceding literal.
  Literal variables (`{{"x"}}`, `{{42}}`) are folded directly. Only simple
  identifiers are folded, so proc calls keep their runtime side effects.
- Template `proc`/`func` bodies with `>= 15` static chars get their own
  `newStringOfCap` in `astProc` (see `macro-generation-analysis.md` F-3).
- Benchmark edits to generated code with `nimble bench` (see
  `bench/benchmark.nim` and `macro-generation-analysis.md`); results are noisy,
  pin with `taskset -c 0` and compare min times. `$` on a Nim `string` is an
  inlined identity, so an "avoid `$`" helper does not help.
- Entry/output is a `string` (`result` / `varname`) appended with `&=`; the
  generated code preallocates when possible (`noPreallocatedString` disables it).
- The output-size estimate (`staticLen`) is a **heuristic, not a length**: static
  blocks + `perVariableAllowance` (16) per `{{ }}` variable (32 when escaping),
  `8 *` for `for`-bodies, floored at `minPreallocCap` = 64 for non-empty
  templates. Under-estimating costs a `realloc` + copy of everything written so
  far, which is the dominant cost of small renders; over-estimating only costs
  memory, but a much larger floor (128) measured *slower*, so the floor is a
  tuned value, not "bigger is better".
- `int`/`float`/`float32` variables are emitted as `addInt`/`addFloat(dst, expr)`
  and `char`/`bool` as `dst.add expr` (`appendVarSmart`): `$` would allocate a
  temporary string per value. This only applies when escaping is off and the
  output is not an iterator (`nwtIter`).
- `loop()`'s `previtem`/`nextitem` are **accessors** (`func previtem[T](loop)`),
  not fields: filling two `Option[T]` per iteration costs a refcount bump per
  element, and most loops never read them. `Loop` keeps a borrowed
  `ptr UncheckedArray[T]` to the iterated data for that.
- `cycle()` is a macro: a literal `@[a, b]` argument is rewritten to an array
  literal so it does not allocate a `seq` on every call (the documented
  `loop.cycle(@["odd", "even"])` spelling is allocation-free).
- Helper hot paths copy runs instead of appending char by char (`addSlice` =
  `setLen` + `copyMem`): `nl2br`, `spaceless`, `truncate`. `truncate` also scans
  words instead of `splitWhitespace()` (which allocates a seq + a string per
  word), and `slugify` strips/lowercases/filters in one pass with
  `toLowerAscii` — `strutils.toLower(string)` is re-exported from `std/unicode`
  and decodes runes (≈10x slower, and pointless for the ASCII-only slug path).

## Bug history

The earlier static-analysis notes (`nimjaBugs2.md`/`nimjaBugs4.md`) were
removed once every finding was either fixed or shown to be intentional. Their
regression tests live in `tests/bugs/`; use those and the git history as the
record of what was wrong and how it was fixed.

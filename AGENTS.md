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
| `readme.md` | the user manual (large; the source of truth for features) |

## Build & test

Nim 2.x is required (`nimble` version pins `nim >= 1.4.8`).

```bash
nimble tests                 # runs basic/ + bugs/ + compiles all examples
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

- `blocks` and the `cacheNwtNode*` tables are **compile-time globals** shared by
  every template compiled in the same module; block bodies are re-registered on
  each `compile`, and `self.<block>` is resolved per `compile` invocation.
- Whitespace control works for `{%- -%}`, `{{- -}}` and `{#- -#}`.
- `baseDir` must be set (`getScriptDir()`) for `extends`/`importnimja`. Import
  paths resolve against `baseDir`, not the importing file.
- `errorOnUnevenBlocks` checks `if`, `for`, `while`, `when` and `block` only;
  unbalanced `case`/`scope`/`proc` fall through to Nim errors.
- `condenseStrings` runs twice on purpose (FS stage, then Nwt stage after
  `fillBlocks`/`self` inlining) to merge adjacent strings and reduce runtime
  `&=` calls.
- Entry/output is a `string` (`result` / `varname`) appended with `&=`; the
  generated code preallocates when possible (`noPreallocatedString` disables it).

## Bug history

The earlier static-analysis notes (`nimjaBugs2.md`/`nimjaBugs4.md`) were
removed once every finding was either fixed or shown to be intentional. Their
regression tests live in `tests/bugs/`; use those and the git history as the
record of what was wrong and how it was fixed.

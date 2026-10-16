# Nimja bug audit & fixes — round 4

Scope: `src/nimja/lexer.nim`, `src/nimja/parser.nim`, `readme.md`, `nimja.nimble`.
Toolchain: Nim 2.2.4.

Method: read-through, then reproduce/verify **every** claim from
`nimjaBugs2.md` / `nimjaBugs3.md` and probe for new bugs with small
compile/run harnesses (`compileTemplateStr` must be called inside a proc).
All items below were reproduced before being fixed, and each fix has a
regression test under `tests/bugs/`.

Status legend: **FIXED** (changed + test), **NOT A BUG** (claim disproved),
**OPEN** (documented, intentionally not fixed here).

---

## FIXED

### F-1 `mustStrip` crashed on a lone `-` (was `nimjaBugs2.md` P-1)
`parser.nim`, `mustStrip`. After removing a leading `-` the code indexed
`value[^1]` without checking that the string was still non-empty, so
`{{-}}` / `{{- }}` raised `IndexError: index out of bounds` at compile time.

Fix: guard the second check with `result.token.value.len != 0`.
Empty variable bodies (`{{-}}`, `{{--}}`, `{{}}`) now produce a clear
`Empty variable body ...` error raised from `astVariable`.

Test: `tests/bugs/test_bug_empty_variable.nim`.

> Correction to `nimjaBugs2.md`: it claimed `{{--}}` also crashes. It does
> **not** (`"--"[0 .. ^2]` is the empty string in Nim); only a value that
> becomes empty after the first strip crashed. The doc was corrected.

### F-2 `errorOnUnevenBlocks` never checked `when` (was `nimjaBugs2.md` P-2) and `block`
`parser.nim`, `errorOnUnevenBlocks`: the `findAll` set omitted
`FsWhen`/`FsEndWhen`, so the `when` counter was always 0 and the
`of FsWhen/FsEndWhen` branches were dead code. The same routine also never
looked at `FsBlock`/`FsEndBlock`, so a template with `{% block %}` and no
`{% endblock %}` was silently accepted.

Fix: added `FsWhen, FsEndWhen, FsBlock, FsEndBlock` to the scanned set and a
`blockcount` counter that raises `uneven block's`.

Tests: `tests/bugs/test_bug_uneven_when.nim`,
`tests/bugs/test_bug_uneven_block.nim`.

### F-3 Unterminated triple-quoted string swallowed the closing `}}` (was `nimjaBugs2.md` L-1)
`lexer.nim`, `lexInnerStrTripple`. It only stopped at a closing `"""` and
never at the enclosing block delimiter, so `{{"""}}` consumed everything to
EOF and yielded a mangled token (`value: "\"\"\"}}"`) followed by a
downstream, confusing parse error.

Fix: `lexInnerStrTripple` now reports whether it found the closing `"""`;
if not, `lexBetween` raises
`Unterminated triple quoted string in block at line <n>`.

Test: `tests/bugs/test_bug_lexer_strings.nim` (also verifies the
terminated case still works).

### F-4 Escaped quote inside a single-quoted string broke the lexer (new)
`lexer.nim`, `lexInnerStr` stopped at the first `"` even if it was escaped by
a backslash. A template like `{{ "a\"b" }}` therefore split the string at the
escaped quote and produced
`Cannot parse variable body: "a\"b" }}`.

Fix: `lexInnerStr` now copies a backslash together with the following
character (`\\`, `\"`, …) verbatim instead of treating the quote as the end.

Test: `tests/bugs/test_bug_lexer_strings.nim`.

### F-5 Debug output on every `{% importnimja %}` / `{% importnwt %}` (new)
`parser.nim`, `parseSecondStepOne` had leftover `echo file` and
`echo blockToRender` statements, so importing a template printed the path and
block name to stdout **at compile time**.

Fix: removed both `echo`s.

### F-6 Circular / self `extends` recursed forever (new)
`parser.nim`, `extend`. A template whose `extends` chain loops
(e.g. a file extending itself) recurse until the VM hit
`maximum call depth ... (current value: 2000)`.

Fix: `extend` now tracks the already-seen `extendsPath`s and raises
`circular extends detected: <path>`.

Test: `tests/bugs/test_bug_circular_extend.nim` +
`tests/bugs/bug_circular.nimja`.

### F-7 Undefined `self.` block gave a confusing Nim error (was `nimjaBugs3.md` #3)
`parser.nim`, `astVariable`. Referencing a block that does not exist
(`{{ self.foo }}`) fell through to `parseStmt("self.foo")` and surfaced as
`undeclared identifier: 'self'`.

Fix: if the body starts with `self.` and the block is missing, raise
`Undefined block referenced by \`self.\`: <name>`.

Test: `tests/bugs/test_bug_undefined_self_block.nim`. (The happy path is
covered by `tests/basic/test_self.nim` and `test_fragments.nim`.)

### F-8 Unknown `blockToRender` killed the compiler (new)
`parser.nim`, `compile` called `quit()` when the requested block was not
known, aborting the whole compiler process instead of reporting an error.

Fix: raise `Block '<name>' is not known.`

Test: `tests/bugs/test_bug_unknown_block_to_render.nim`.

### F-9 `thisIs` off-by-one (was `nimjaBugs2.md` L-2)
`lexer.nim`, `thisIs` used `pos > buf.len` (should be `>=`) and would read
`buf[pos]` out of bounds at `pos == buf.len`. Currently unreachable because
every caller guards with `pos < buf.len`, but fixed for consistency with
`isEof`.

### F-10 readme examples passed `context` positionally (new, docs)
`readme.md` showed
`compileTemplateString("...", {node: rax, baa: foo})` and
`tmpls("...", {node: rax, baa: foo})`. The 2nd positional parameter is
`baseDir: static string`, not `context`, so the example does not compile
(verified). Fixed to `context = {...}`.

### F-11 readme changelog used the unsupported `{{importnimja ...}}` form (new, docs)
`readme.md` (0.9.0 changelog) and the fragments section documented
`{{importnimja "x"}}`. Only `{% importnimja "x" %}` is supported;
the `{{...}}` form fails with `undeclared identifier: 'importnimja'`.
Corrected the examples to the block form.

### F-12 Broken AI-added test files (new)
`tests/basic/test_lexer_bugs.nim` and `tests/basic/test_parser_bugs.nim`
(added in commit `12ef38c "ai analysis"`) did not compile at all: their
`discard """ ... """` spec contained unescaped `"""` and an undefined
`newToken` helper, and testament aborted with
`invalid key for test spec` / `testament spec violation`. Removed and
replaced by compiling tests in `tests/bugs/`.

### F-13 `docs` nimble task removed the wrong directory (new, build)
`nimja.nimble` ran `rmDir("src/htmldocs/")`, but the stray generated folder is
`src/nimja/htmldocs/`, so it was never cleaned. Fixed the path and removed the
tracked stray `src/nimja/htmldocs/` (duplicate of `docs/nimja/nimjautils.html`).

### F-14 `nimjaBugs3.md` was mostly false (new, docs)
Re-verified every item:
- #1 “`lexInnerStrTripple` fails for content ending in a quote, e.g. `{{"a"}}`”
  — **false**. `{{"a"}}` is a single-quoted string handled by
  `lexInnerStr` and works; the only failing case is the unterminated
  triple string (F-3).
- #2 “initial slice `buf[pos .. pos+2]` can read out of bounds” — **not a
  bug**, the caller only calls the triple reader after asserting three
  quotes exist.
- #3 “`astVariable` … cryptic parse error” — partly false: the old error was
  `undeclared identifier: 'self'`, not a parse error. The real usability
  issue was fixed (F-7).
- #4 “`compile` assumes a non-empty cache” — not reachable; `extend` always
  inserts at least one entry.
- #5 “`findAll` type-signature mismatch” — **false**. There are two
  overloaded `findAll` iterators (one over `FsNode`, one over `NwtNode`),
  each with a matching element type.

The file was removed since it contained no valid open findings.

### F-15 `self.<block>` resolved to the last-registered block (issue #107)
`parser.nim`, `compile`/`astVariable`. `blocks` is a compile-time global and
`{{ self.<name> }}` was resolved lazily during AST generation, so when the same
block name existed in more than one template the reference picked up whichever
template registered last. With `importnimja` this made an imported template's
`self.title` render the importing template's `title`.

Fix: `compile` now walks the finished node tree and replaces every
`self.<block>` variable with the block's body **at the end of the same `compile`
invocation** (`resolveSelf`), before a later template can overwrite `blocks`.
A `resolving` set guards against a block referencing itself through `self.`.

Test: `tests/bugs/test_bug_107_self_blockname.nim` +
`tests/bugs/self_blockname_parent.nimja` / `self_blockname_child.nimja`.
Before the fix the test produced `parentchildparent`; it now produces the
expected `parentchildchild`.

---

## OPEN (verified, not fixed here)

- **O-1 `condenseStrings` runs twice** (was `nimjaBugs2.md` P-3): on the
  `FSNode` stage in `loadCache` and again on the `NwtNode` stage after
  `fillBlocks`. The second pass is needed because `fillBlocks` can make
  strings adjacent; it is only wasted work on templates without blocks.
  Harmless.
- **O-2 Unreachable `else` in `parseFirstStep`** (was `nimjaBugs2.md` P-4):
  every `NwtTokenKind` is handled, the branch is dead code.
- **O-3 Comment whitespace control is ignored**: `{#- ... -#}` does not strip
  surrounding whitespace because `NwtComment` tokens are dropped in
  `parseFirstStep` before `whitespaceControl` runs (verified: `A {#- c -#} B`
  renders `A  B`). Only `{%- -%}` and `{{- -}}` work.
- **O-4 Unbalanced block delimiters give internal errors**: a stray
  `{% else %}` / `{% endblock %}` raises
  `unhandled exception: [SS] NOT IMPL: (kind: FsElse, ...)` instead of a
  user-friendly message. `case`/`scope`/`proc` balance is not checked by
  `errorOnUnevenBlocks` and surfaces as Nim errors (e.g. “not all cases are
  covered”).
- **O-5 `cycle` divides by zero** for an empty `elems` sequence
  (`nimjautils.nim`, `cycle`).
- **O-6 `extends`/`importnimja` paths are resolved relative to `baseDir`**,
  not the importing file. This is the documented design, but it surprises
  people whose imported template itself imports a sibling by relative path.

---

## Regression tests added

`tests/bugs/`
- `test_bug_lexer_strings.nim` — F-3, F-4 (+ `}}` in string, terminated triple)
- `test_bug_empty_variable.nim` — F-1
- `test_bug_uneven_when.nim` — F-2
- `test_bug_uneven_block.nim` — F-2
- `test_bug_circular_extend.nim` + `bug_circular.nimja` — F-6
- `test_bug_undefined_self_block.nim` — F-7
- `test_bug_unknown_block_to_render.nim` — F-8
- `test_bug_107_self_blockname.nim` (+ parent/child `.nimja`) — F-15

Run with `nimble tests` or
`testament --directory:"./tests/" p "bugs/*.nim"`.

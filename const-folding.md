# Const / static variables folded into string blocks (issue #53)

Question: can compile-time constant variables in `{{ ... }}` be folded into the
surrounding string block, saving runtime `add` calls?

**Status: implemented for runs of simple identifiers.** A maximal run of string
blocks and variables is now emitted as

```nim
when v1 is static and v2 is static:      # all variables are compile time
  result &= "a " & $v1 & " b " & $v2     # one add, compiler folds the literal
else:
  result &= "a "                         # previous per-variable code
  result &= $v1
  result &= " b "
  result &= $v2
```

---

## 1. Did we already do this? No

`compileTemplateStr("A {{ foo }} B {{ n }} C")` with `const foo = "foo baa"` and
`const n = 42` used to compile to (`-d:dumpNwtMacro`, `--expandArc:render`):

```nim
result &= "A "
result &= $foo      # Nim already folds $const to the literal "foo baa"
result &= " B "
result &= $n        # ... "42"
result &= " C"
```

So Nim folds `$const` to a literal, but the `add` calls stay separate and
`condenseStrings` cannot merge them (a variable is not an `NStr`). The
pre-allocation size (`guessedStringLen`) also misses the const values.

## 2. The general case is impossible at macro-expansion

Nimja's macro only has the variable **name as a string**;
`parseStmt("foo")` yields an unresolved identifier and there is no way to know
whether the name binds to a `const` at the call site — semantic analysis happens
after the macro. This is discussed in
[forum.nim-lang.org/t/9283](https://forum.nim-lang.org/t/9283) ("in general this
is not possible").

## 3. What is possible: let the *compiler* decide with `when ... is static`

The macro cannot resolve the symbol, but the generated code can ask the compiler
at *its* compile time:

```nim
when foo is static:
  result &= "A " & $foo & " B"   # compiler constant-folds this to one literal
else:
  result &= "A "
  result &= $foo
  result &= " B"
```

`--expandArc` confirms `when foo is static` (const) produces a single
`result &= "A foo baa B"`, while a runtime variable takes the `else` branch.

### Implementation (`parser.nim`)

* `astAst` groups maximal runs of `NStr`/`NVariable` and calls `astRun`.
* `astRun`:
  * builds the current per-node code as the `else` branch;
  * if every variable is a **simple identifier** (`varExpr(...).kind ==
    nnkIdent`), builds a folded `&`-concatenation and a `when` condition
    (`v1 is static and v2 is static ...`).
* Only simple identifiers are folded on purpose: `x is static` is broader than
  "is a const" (a pure proc call is `static` too), and folding a call would
  move its evaluation, and any side effect, to compile time. `{{ sideEffect() }}`
  is covered by a test that asserts it still runs once at runtime.
* Runs are split at variables that are not simple identifiers (string/int
  literals, `self.`, calls), so those do not disable folding of their
  neighbours.

## 4. Measured effect

50 `{{ a }}` (const) followed by `{% if x %}{{x}}{% endif %}` so the render is
not constant-folded as a whole (Nim 2.2.4, `-d:release`, `taskset -c 0`, 5000
renders per timed run):

| | min time |
|---|---|
| before (50 `add`s) | ~1.75 ms |
| after (1 `add`) | ~0.43 ms |

≈ **4x faster** for this all-const run. `nimble bench` has a `const block`
scenario now.

## 5. Limitations / caveats

* **The whole run must be static.** The condition is `v1 is static and ...`, so a
  single runtime variable in the same run disables folding for the run. In a
  typical page `{{ siteName }}</h1><p>{{ userContent }}` both are in one run
  (`</h1><p>` is the `NStr` between them), so `siteName` does not fold. A
  per-variable fallback (fold each `NStr`+`var` pair) would recover one `add`
  per static variable in mixed runs, at the cost of a more complex `else`
  branch; not implemented.
* **Pre-allocation still under-estimates.** `newStringOfCap` is computed at
  macro time from literal lengths only; the const value is unknown then. The
  folded literal is longer than the cap, but the string still grows correctly.
* **Compile-time cost.** The `when` branch roughly doubles the generated AST for
  affected runs (only the taken branch is compiled, so runtime code size is
  unchanged).
* **`is static` vs `is const`.** Restricting to simple identifiers keeps this
  safe; `is static` on calls would fold compile-time-evaluable calls.

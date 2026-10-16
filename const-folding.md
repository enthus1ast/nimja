# Const / static variables folded into string blocks (issue #53)

Question: can compile-time constant variables in `{{ ... }}` be folded into the
surrounding string block, saving runtime `add` calls?

**Status: implemented.** A maximal run of string blocks and variables now
prefers to fold into one string:

```nim
when v1 is static and v2 is static:      # all variables are compile time
  result &= "a " & $v1 & " b " & $v2     # one add, compiler folds the literal
else:
  when v1 is static:                     # mixed run: fold each const with its
    result &= "a " & $v1                 # preceding literal, still saves adds
  else:
    result &= "a "
    result &= $v1
  ...
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
  * if any variable is **not** a simple identifier (`varExpr(...).kind ==
    nnkIdent`), it uses the normal per-node code;
  * otherwise the first branch is `when v1 is static and v2 is static ...:` with
    the fully folded `&`-concatenation (best case: one `add`);
  * the `else` branch folds **each variable with the literal before it**
    (`when v is static: result &= "pre" & $v`), so a mixed run still saves one
    `add` per static variable.
* Only simple identifiers are folded on purpose: `x is static` is broader than
  "is a const" (a pure proc call is `static` too), and folding a call would
  move its evaluation, and any side effect, to compile time. `{{ sideEffect() }}`
  is covered by a test that asserts it still runs once at runtime.
* Runs are split at variables that are not simple identifiers (string/int
  literals, `self.`, calls), so those do not disable folding of their
  neighbours.

## 4. Measured effect

Run with Nim 2.2.4, `-d:release`, `taskset -c 0`, 5000 renders per timed run.

**All-static run** - 50 `{{ a }}` (const) followed by a runtime-dependent
`{% if x %}` so the render is not constant-folded as a whole:

| | min time |
|---|---|
| before (50 `add`s) | ~1.75 ms |
| after (1 `add`) | ~0.43 ms |

≈ **4x faster**.

**Mixed run** - 50 `{{ a }} ` (const, space separated) followed by `{{ x }}`
(runtime) in the same run:

| | min time |
|---|---|
| before (~100 `add`s) | ~2.05 ms |
| after (one `add` per const) | ~1.56 ms |

≈ **25% faster**. `nimble bench` has `const block` (all static) and
`const mixed` scenarios.

## 5. Limitations / caveats

* **Adjacent variables** with no literal between them (`{{a}}{{b}}{{x}}`) are
  only folded when *all* of them are static; in a mixed run they stay as
  separate adds (there is no literal to merge with).
* **Pre-allocation still under-estimates.** `newStringOfCap` is computed at
  macro time from literal lengths only; the const value is unknown then. The
  folded literal is longer than the cap, but the string still grows correctly.
* **Compile-time cost.** The `when` adds a second copy of the run's AST (only
  the taken branch is compiled, so runtime code size is unchanged).
* **`is static` vs `is const`.** Restricting to simple identifiers keeps this
  safe; `is static` on calls would fold compile-time-evaluable calls.

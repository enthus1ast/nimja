# Nimja error reporting — investigation

Goal: template errors should report **(template) file, line and column**, and
the change must have **zero runtime cost**.

This is an investigation; nothing here is implemented yet. It contains the
current-state audit, a verified mechanism (with a working prototype), the data
flow changes needed, edge cases and a suggested implementation plan.

---

## 1. Current state

### 1.1 What exists

* `lexer.nim` tracks a `line` counter and stores it in `Token.line`
  (`lexer.nim:92`, `:136`).
* `Token` also has a `charinbuf*: int` field (`lexer.nim:14`) that is **never
  written** — grep shows it is only declared. It is always `0`.
* `FSNode` (`parser.nim`) and `NwtNode` (`parser.nim`) carry **no** position or
  file information at all.

### 1.2 What an error looks like today

Template `bad.nimja` (missing `{% endif %}`):

```twig
line one
line two
{% if true %}
hello
```

```nim
proc render(): string = compileTemplateFile("bad.nimja", baseDir = "/tmp/nimjaerr")
```

```
/home/david/projects/nimja/src/nimja/parser.nim(676, 5) errorOnUnevenBlocks
...
/home/david/projects/nimja/src/nimja/parser.nim(676, 5) Error: unhandled exception:
  uneven if's: @[(kind: FsStr, value: "line one\nline two\n", ...), (kind: FsIf,
  value: "true", ...), (kind: FsStr, value: "\nhello\n", ...)] [ValueError]
```

The compiler points at **`parser.nim`**, not at `bad.nimja`. The message dumps
the whole `FSNode` list instead of the offending position. The same is true for
every `raise newException(ValueError, ...)` / `error "..."` site
(`parser.nim:223,245,267,374,386,396,400,442,553,575,639,649,676..684,736,823`).

### 1.3 The `line` counter is already wrong

`line` is unreliable before we even attach it:

* **Double counting.** the main `lex` iterator calls `handleNl` at the top of
  its loop, and the sub-lexers (`lexStr`, `lexBetween`) call `handleNl` again
  per character. When the first character a sub-lexer sees is `\n`, the line is
  incremented twice.

  ```
  src = "x\n{{a}}\n{{b}}\n"
      NwtVariable line=1 value=a   # correct
      NwtVariable line=3 value=b   # WRONG, b is on line 2
  ```

* **Newlines inside strings are never counted.** `lexInnerStr` and
  `lexInnerStrTripple` copy characters directly without calling `handleNl`, so
  a multi-line `"""..."""` shifts every following line number.

* **No column at all** (`charinbuf` is dead).

So "add line/col to errors" also means **fixing position tracking first**.

---

## 2. Mechanism: `macros.error(msg, node)` + `setLineInfo`

Nim's `macros` module has exactly what is needed
(`lib/core/macros.nim`):

```nim
proc error*(msg: string, n: NimNode = nil)          # error at n's location
proc setLineInfo*(arg: NimNode, file: string, line, column: int)
```

`setLineInfo` lets us fabricate a throw-away `NimNode` pointing at any
**existing** file/line/column, and `error(msg, thatNode)` makes the compiler
print the diagnostic there.

### Verified prototype

```nim
import macros

proc reportError(msg: string, file: string, line, col: int) {.noreturn.} =
  let n = newIdentNode("templateError")
  if file.len > 0:
    n.setLineInfo(file, line, col)
  error(msg, n)

proc inner() =
  reportError("bad template syntax", "/tmp/nimjaerr/does_exist.nimja", 2, 0)

macro m(): untyped =
  inner()
  result = newStmtList()

m()
```

Output:

```
/tmp/errproto2.nim(16, 2) template/generic instantiation of `m` from here
/tmp/nimjaerr/does_exist.nimja(2, 1) Error: bad template syntax
```

The final `Error:` line is now **the template file**, with template line/column.
Notes:

* **Column is 0-based**: passing `0` displays `1`, passing `5` displays `6`.
  The lexer should therefore store a 0-based column.
* **The file must exist** (`setLineInfo` stats it; otherwise the compiler raises
  `OSError: No such file or directory`). `compileTemplateFile`/`extends`/
  `importnimja` all have a real path. A template given as a **string** does not
  — see §4.
* `setLine` takes a `uint16`, so `line > 65535` overflows (acceptable).
* `error` still prints the macro-expansion traceback above the `Error:` line,
  but unlike `raise newException` there is no VM stack dump and no
  `[ValueError] repr` noise.

`warning`/`hint` accept a node the same way and could be used for lint-style
diagnostics.

---

## 3. Data-flow changes (all compile time)

```
buffer ──lex──► Token(line, col) ──parseFirstStep──► FSNode(line, col, file)
                                       │
                                       ├─ errorOnUnevenBlocks / duplicated / extends
                                       ▼
                              parseSecondStep ──► NwtNode(line, col, file)
                                       │
                                       └─ astVariable / astEval / astProc
```

1. **Lexer**
   * track `col` (`pos - lineStart`), reset `lineStart` when a `\n` is seen;
   * fix the double `handleNl`;
   * count newlines (and track column) inside `lexInnerStr` /
     `lexInnerStrTripple`;
   * store `col` in `Token`. `charinbuf` is unused today; either reuse it or add
     a proper `col*: int` field (see §5 for the test impact).

2. **`FSNode`** — add `line`, `col` (and `file`, or set a global before parsing),
   filled from the `Token`.

3. **`NwtNode`** — add common fields *before* the `case` (allowed in Nim, and
   free at runtime because the type is compile-time only):

   ```nim
   NwtNode = object
     line: int
     col: int
     file: string
     case kind: NwtNodeKind
       ...
   ```
   Filled in `parseSecondStepOne` from the `FSNode`.

4. **Source file** — `loadCache`/`loadCacheFile` know the resolved path
   (`nwtBaseDir / path`). Set a compile-time `currentFile` before parsing a file
   and copy it into the nodes (the `NwtNode` cache then bakes it in).

5. **Error helper**

   ```nim
   proc templateError(msg: string, file: string, line, col: int) {.noreturn.} =
     let n = newIdentNode("templateError")
     if file.len > 0:
       n.setLineInfo(file, line, col)
     error(msg, n)
   ```
   Replace the `raise newException(ValueError, ...)` / `error "..."` sites with
   `templateError(msg, node.file, node.line, node.col)`.

   For `errorOnUnevenBlocks`, use a small stack while scanning so the exact
   unmatched `if`/`for`/`while`/`when`/`block` is reported (instead of dumping
   the whole list).

---

## 4. File name for `compileTemplateStr`

`compileTemplateStr` has no template file, and `setLineInfo` requires an
existing file. Options:

* **Point at the macro call site** using the `str` argument NimNode
  (`str.lineInfoObj`) and append the template position to the message:
  `error(msg & " (template line 3, col 5)", str)`. Honest and simple;
  the caret lands on the user's Nim source where the template string starts.
* For a triple-quoted inline template, the template line `N` is approximately
  the Nim line of the string start plus `N`; this can be used to point the node
  at the right line of the **user's** file for a closer match, at the cost of
  column accuracy (TAB/`"""`/indentation offsets).
* Do **not** write the template to a temp file just to get a path.

`compileTemplateFile`, `extends` and `importnimja` should always use the real
resolved template path (best case).

---

## 5. Zero runtime cost

* `Token`, `FSNode` and `NwtNode` exist **only at compile time**; the generated
  Nim AST is built from `NwtNode` but never contains the position fields. Adding
  them changes neither the generated code nor the runtime.
* `setLineInfo`/`error` run **only on the error path**.
* Verification method for the implementation: compare `-d:dumpNwtMacro` output
  before/after (must be byte-identical) and run `nimble bench`.

The only cost is a little extra compile-time memory/CPU per node.

---

## 6. Edge cases & caveats

* **Lexer is a standalone module** with its own `when isMainModule` unittests.
  It should not import `macros`/`error`. Keep raising a *positioned* exception
  (e.g. a `NimjaLexError` carrying line/col) or keep emitting `lexerMsg`, and let
  `loadCache` convert it to `templateError`.
* **Cache.** `cacheNwtNode` is keyed by template **string**, so the same string
  used from two different files would be cached with the first file's name.
  Rare; acceptable, or include the file in the cache key.
* **`error` traceback noise.** The macro-expansion stack is still printed. It is
  much cleaner than the current `unhandled exception ... [ValueError]` +
  `$fsns` dump, and is the standard Nim behaviour.
* **Test churn.** The lexer tests construct expected `Token`s (`newToken(...)`)
  and compare structurally. Adding a `col` field (or filling `charinbuf`) makes
  those comparisons fail; the tests need to either set the expected position or
  compare `(kind, value)` only.
* **Files must exist**, so string templates need the fallback in §4.

---

## 7. Suggested implementation order

1. Fix `line` counting (single `handleNl` owner) and count newlines inside
   strings; add a `col` and unit-test the lexer positions.
2. Thread `line`/`col`/`file` through `FSNode` → `NwtNode`.
3. Add `templateError` and migrate the highest-value sites first:
   `parseSecondStepOne` (unexpected tag), `errorOnUnevenBlocks`,
   `errorOnDuplicatedBlocks`, `validExtend`, `astVariable`/`astEval`.
4. Handle the string-template fallback and the lexer exception bridge.
5. Verify: `-d:dumpNwtMacro` diff is empty, `nimble bench` unchanged,
   41 basic + 12 bug tests green, and add a compile-error test asserting the
   template file/line appears (`errormsg` + `file:` in the test spec).

Estimated: ~1 day; most of it is the lexer position correctness and the test
updates for `Token`.

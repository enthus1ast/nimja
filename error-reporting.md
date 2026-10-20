# Nimja error reporting (file, line, column)

Template errors now point at the **template file and position**, for example:

```
/home/david/projects/nimja/tests/bugs/bug_circular.nimja(1, 1) Error: circular extends detected
/tmp/nimjaerr/bad.nimja(3, 1) Error: `if` is missing `endif`
/tmp/nimjaerr/elsebad.nimja(1, 1) Error: Unexpected template tag (unbalanced or misplaced): else ''
```

For string templates (no file) the diagnostic points at the macro call site and
appends the in-template position to the message:

```
/tmp/nimjaerr/strerr.nim(3, 22) Error: `if` is missing `endif` (template line 2, col 1)
```

**Zero runtime cost**: all position data lives in compile-time-only types
(`Token`, `FSNode`, `NwtNode`); it is never emitted into the generated AST and
`setLineInfo`/`error` only run on the error path. Verified by diffing
`-d:dumpNwtMacro` output (byte-identical) and re-running `nimble bench`.

---

## How it works

### 1. Position tracking in the lexer (`src/nimja/lexer.nim`)

* `Token` has `line*` and `col*` (both 0 based, `col` is the byte offset from
  the line start); the previously unused `charinbuf` was removed.
* `lineStart` is updated whenever a `\n` is consumed (`handleNl`), so the column
  is derived from `pos` alone.
* Newlines inside quoted / triple-quoted strings are counted
  (`lexInnerStr`, `lexInnerStrTripple`), and the old double `handleNl` counting
  (main loop + sub-lexer) was removed.

### 2. Positions on the node types (`src/nimja/parser.nim`)

* `FSNode` gains `line`, `col`, `file`.
* `NwtNode` gains `line`, `col`, `file` as **common fields before the `case`**
  (allowed in Nim, and free at runtime because the type is compile time only).
* `atPos(node, fsNode)` copies the position from `FSNode` to `NwtNode` in every
  `parseSs*` and in the simple node cases of `parseSecondStepOne`.
* `file` is threaded through `compile` → `extend` → `loadCache`, using the real
  resolved path for `compileTemplateFile`, `extends` and `importnimja`.

### 3. Located errors

```nim
type NimjaError* = ref object of ValueError
  file*: string
  line*: int
  col*: int

proc templateError(msg, file: string, line, col: int) {.noreturn.} =
  raise NimjaError(msg: msg, file: file, line: line, col: col)

proc reportNimjaError(e: NimjaError) {.noreturn.} =
  let n = newIdentNode("templateError")
  var msg = e.msg
  if e.file.len > 0:
    n.setLineInfo(e.file, e.line + 1, e.col)   # setLineInfo is 1 based
  else:
    msg = msg & " (template line " & $(e.line + 1) & ", col " & $(e.col + 1) & ")"
    if nwtFallbackFile.len > 0:
      n.setLineInfo(nwtFallbackFile, nwtFallbackLine, nwtFallbackCol)
  error(msg, n)
```

* `templateError` is used everywhere an error used to be raised/`error`-ed.
* `doCompile` wraps `compile(...)` **and** the AST generation in
  `try: ... except NimjaError as e: reportNimjaError(e)`, so the compiler prints
  `file(line, col) Error: msg` via `macros.error(msg, node)`.
* Because `NimjaError` is a `ValueError`, calling the internal `compile(...)`
  directly still raises a **catchable** exception (used by
  `tests/basic/test_doublicated_blocks.nim` and
  `tests/bugs/test_bug_error_positions.nim`).

### 4. String templates

`compileTemplateStr` sets `nwtFallbackFile/Line/Col` from the string argument
node (`str.lineInfoObj`); `compileTemplateFile` uses `instantiationInfo(-1, true)`
for its call site. When no template file is known, the diagnostic is reported at
that fallback location and the message carries `(template line X, col Y)`.

`setLineInfo` requires the file to exist, so a fabricated path cannot be used.

### 5. Unbalanced tags

`errorOnUnevenBlocks` now walks the tags with a stack, so it reports the exact
unmatched tag (`unexpected \`else\` without matching opener`) or the opener that
is missing its end tag (`\`if\` is missing \`endif\``) with its position, instead
of dumping the whole `FSNode` list.

`tagName(k)` derives the user-facing tag name from the enum member name
(`$k` with the `Fs` prefix stripped and lower-cased), so no mapping table is
needed.

---

## Tests

* `tests/bugs/test_bug_error_positions.nim` asserts `NimjaError.line/col`
  directly (missing `endif`, unexpected tag, duplicated block, and a
  multi-line triple-quoted string that must not shift later positions).
* `src/nimja/lexer.nim` (`when isMainModule`) has a line/column test.
* The existing compile-error specs were updated to the new messages/files.

`tests/basic` 41 passed, `tests/bugs` 13 passed.

---

## Caveats

* `setLine` uses `uint16`, so lines above 65535 wrap.
* The `cacheNwtNode` cache is keyed by the template string, so the same string
  used from two files keeps the first file's name.
* The compiler still prints the macro-expansion traceback above the `Error:`
  line; that is standard Nim behaviour and much cleaner than the previous
  `unhandled exception ... [ValueError]` plus `$fsns` dump.

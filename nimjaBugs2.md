# Nimja static analysis — lexer + parser

Scope: `src/nimja/lexer.nim` and `src/nimja/parser.nim`.
Method: read-through + targeted compile/run verification (Nim 2.2.4).
Each item below is either **verified by reproduction** or **latent** (cannot be
triggered with the current call sites / would need a specific input). Things I
**hypothesized but disproved** are listed at the end so they don't linger.

Nimja is a compile-time template engine: `lex` -> `parseFirstStep` (FSNodes) ->
`parseSecondStep` (NwtNodes) -> Nim AST. `compileTemplateStr/File` must be called
inside a proc (the generated code appends to the implicit `result`).

---

## VERIFIED BUGS

### L-1 (high) `lexInnerStrTripple` never stops at the `}}` delimiter — it swallows it
`lexer.nim`, `lexInnerStrTripple`. The inner triple-quoted string reader loops
only looking for a closing `"""`. It never treats the enclosing `}}` (the
`{{ ... }}` variable delimiter) as a terminator, so everything up to EOF / the
next `"""` is consumed as string content.

Reproduced:
```
toSeq(lex("{{\"\"\"}}"))
=> @[Token(NwtVariable, value: "\"\"\"}}")]   # value is """}}  <-- the }} was eaten
[0] Endchar expected but not found... '}}'     # also emitted to stderr
```
The variable token's value is `"""}}` and the lexer reports "Endchar expected".
Any `{{ """...""" }}` whose triple string is not cleanly closed before `}}`
behaves this way. `lexInnerStr` (single `"` variant) does stop at `"`, so the
triple variant is strictly worse.

### P-1 (high) `mustStrip` index-out-of-bounds crash on a lone `-` token
`parser.nim`, `mustStrip`:
```nim
if result.token.value[0] == '-':
  result.stripPre = true
  result.token.value = result.token.value[1 .. ^1]   # strip first char
if result.token.value[^1] == '-':                    # now on possibly-empty string
  result.stripPost = true
  result.token.value = result.token.value[0 .. ^2]
```
If the cleaned value is exactly `"-"` (e.g. template `{{-}}`) or `"--"`
(`{{--}}`), the first slice yields `""`/`"-"` and the second check
`value[^1]` runs on an empty string → `IndexError: index out of bounds, the
container is empty`.

Reproduced (compile-time, inside a proc):
```
compileTemplateStr("A{{-}}B")
=> stack: parseFirstStep -> mustStrip -> indices.nim []  "index out of bounds, container is empty"
```
(`"-"[1 .. ^1]` itself returns `""` in Nim, so the first slice is fine; it's the
`value[^1]` on the now-empty string that crashes.)

### P-2 (medium) `errorOnUnevenBlocks` never detects unbalanced `when` — dead code
`parser.nim`, `errorOnUnevenBlocks`:
```nim
for fsnode in fsns.findAll({FsIf, FsEndif, FsFor, FsEndfor, FsWhile, FsEndWhile}):
  case fsnode.kind
  of FsIf: ifs.inc ... of FsWhile: whiles.inc
  of FsWhen: whens.inc        # <-- unreachable
  of FsEndWhen: whens.dec     # <-- unreachable
```
`findAll` is given a set that **omits** `FsWhen`/`FsEndWhen`, so those nodes are
never passed to the `case`. `whens` is therefore always `0` and the
`if whens != 0` guard never fires. The `of FsWhen / FsEndWhen` branches are dead
code. Consequence: a template with a `{% when %}` and no `{% endwhen %}` is
accepted and rendered silently.

Reproduced:
```
compileTemplateStr("{% when true %}B")   # missing endwhen
=> "B"                                   # no error raised (unlike a missing endif)
```
The same routine DOES catch missing `if`/`for`/`while`; the gap is specific to
`when` (and the readme changelog claims "Error on uneven when blocks" since
0.8.7, which is not actually true).

---

## LOW / STYLE

### P-3 (low) `condenseStrings` runs twice over the same nodes
`parser.nim`: `loadCache` condenses on the FSNode stage, and `compile` condenses
again on the NwtNode stage (`fillBlocks(base).condenseStrings()`). The second
pass is redundant — already-condensed NStr nodes are simply re-merged into one.
Harmless but wasted compile-time work; consider dropping one.

### P-4 (low) Unreachable `else` in `parseFirstStep`
```nim
else: echo "[FS] Not catched:", token
```
`token.kind` is always one of `NwtEval/NwtString/NwtVariable/NwtComment`, all
handled above, so this branch can never execute. Dead code.

### L-2 (low, latent) `thisIs` off-by-one
`lexer.nim`, template `thisIs`:
```nim
template isEof(): bool = pos >= buf.len
template thisIs(chr: char): bool = (not (pos > buf.len)) and (buf[pos] == chr)
```
`isEof` uses `>=` (correct) but `thisIs` uses `>` — at `pos == buf.len` `thisIs`
would read `buf[pos]` out of bounds. In practice every call site guards with
`while pos < buf.len` before calling `thisIs`, so it is currently untriggerable,
but it is an inconsistency waiting to bite if a call site changes. Same family:
`lastIs` guards `pos-1` correctly; `nextIs` is correct.

---

## HYPOTHESIZED BUT DISPROVED (do NOT fix — they are correct)

- **"parseSsWhile/For/Block/Proc/Scope double-increment past the end tag."**
  `consumeBlock` leaves `pos` pointing AT the end tag (it breaks before
  consuming it), and the single `pos.inc` in each `parseSs*` then advances past
  it exactly once. Verified: content *after* `{% endwhile %}`, `{% endfor %}`,
  `{% endblock %}`, `{% endscope %}`, `{% endproc %}`, `{% endcase %}`,
  `{% endwhen %}` all render correctly (`xxxAFTER`, `aaaAFTER`, `BAFTER`, …).
  Not a bug.

- **`lexStr` `pos.dec` skips/re-duplicates content.** `lexStr` breaks on a
  `{`-delimiter without storing it and does `pos.dec`; the main loop's `pos.inc`
  returns `pos` to the `{`, which is then correctly re-examined by
  `lexVar/lexComment/lexEval`. Embedded `{# #}`, `{% %}`, `{{ }}` in text are
  detected fine. Not a bug.

- **`lexInnerStrTripple` / `lexInnerStr` initial slice `buf[pos..pos+2]` OOB.**
  `lexBetween` only calls the triple reader after asserting
  `thisIs('"') and nextIs('"') and nextIs('"',2)`, i.e. 3 quotes exist, so the
  `buf[pos .. pos+2]` slice is always in range. Not triggerable.

- **`whitespaceControl` uses `'\c'`.** In Nim `'\c' == '\r'` (verified), so the
  strip set `{' ', '\n', '\c'}` = space/CR/LF is intentional and correct. Not a
  bug.

- **`mustStrip` `"-"[1 .. ^1]` OOB.** Nim returns `""` for a reversed string
  slice; only the *second* `value[^1]` on the empty result crashes (see P-1).

---

## Notes on build/verification
- The library compiles and its own unittests pass
  (`nim c -r src/nimja/lexer.nim`).
- To run a parser probe the same way the repo does: put the test file under
  `tests/basic/` (or pass `--path:src`) and call `compileTemplateStr` inside a
  `proc` (it targets the implicit `result`). Running control-structure probes
  with a `timeout` — an unguarded `{% while true %}` hangs and floods output.
- Cache is on by default; use `-d:nwtCacheOff` to force fresh lexing.

# Nimja static analysis — lexer + parser: additional bugs found

Source files: `src/nimja/lexer.nim` and `src/nimja/parser.nim`

## Existing documented bugs (from ./nimjaBugs2.md)

The following bugs were already identified in `nimjaBugs2.md`:

- **L-1 (high)** `lexInnerStrTripple` never stops at the `}}` delimiter — it swallows it, treating everything up to EOF as string content.
- **P-1 (high)** `mustStrip` index-out-of-bounds crash on a lone `-` token (e.g. `{{-}}`).
- **P-2 (medium)** `errorOnUnevenBlocks` omits `FsWhen`/`FsEndWhen` from the set passed to `findAll`, so unbalanced `when` blocks are silently accepted.
- **P-3 (low)** `condenseStrings` runs twice over the same nodes (once on FSNodes, once on NwtNodes).
- **P-4 (low)** unreachable `else` in `parseFirstStep`.
- **L-2 (low, latent)** off-by-one in `thisIs` — should be consistent with `isEof`.
- Several hypotheses were disproved and are correct (no action needed).

## Additional bugs found beyond the documented list

### In lexer.nim

**1. `lexInnerStrTripple` delimiter detection is fragile (related to L-1)**

The function checks for the closing delimiter with:
```nim
if thisIs('"') and nextIs('"') and nextIs('"', 2)
```
This requires **three consecutive quotes** after the current position. The actual closing delimiter of a `{{...}}` variable block is only two braces (`}}`). For any valid template where the string content ends with a quote character before `}}` (e.g. `{{"a"}}`), the function fails to recognize the closing delimiter, consumes everything to EOF, and emits an "Endchar expected but not found... '}}'"` error — mangling the token.

The existing test "triple quotes" passes by coincidence because the test string's content ends with `"` followed by `}}`, satisfying the three-quote precondition. A robust fix would check for `}}` instead of three quotes.

**2. Bounds issue in `lexInnerStrTripple` initial slice**

The line:
```nim
result &= buf[pos .. pos + 2] # the '"""'
```
assumes at least two more characters exist after `pos`. If the buffer ends right at the opening delimiter (malformed input), this is an out-of-bounds read. The precondition should be enforced by the caller, but it is a latent crash vector.

### In parser.nim

**3. `astVariable` has no graceful handling for undefined `self.` blocks**

When a variable body starts with `self.` (the special self-block reference) but no block of that name exists in `blocks`, the code falls through to `parseStmt(token.variableBody)`, which tries to parse the body as Nim code and errors out with a cryptic parse error. It should first check whether the block exists and only then attempt to parse the variable body.

**4. `compile` assumes the cache is non-empty when accessing `templateCache[0]`**

The `blockToRender == ""` branch does:
```nim
var base = templateCache[0]
```
While `extend()` always adds entries, this is an unchecked assumption — if the cache were empty for any reason, it would panic. This is a latent issue.

**5. Type signature mismatch in `findAll`**

The function is declared to return `FsNode`:
```nim
func findAll(fsns: seq[FsNode], kind: FsNodeKind | set[FsNodeKind]): FsNode
```
But its implementation yields `NsNode` (a sequence of `NwtNode`). Nim tolerates the mismatch, but it is misleading and could cause confusion.

## Summary

- **2 new bugs** found: lexer delimiter detection fragility (L-1 related), parser undefined self-block handling.
- **3 latent issues** noted: lexer bounds check, compile cache non-empty assumption, findAll type signature.
- All existing documented bugs from `nimjaBugs2.md` remain valid and are not affected by these additions.

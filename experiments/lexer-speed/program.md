# program.md — lexer speed research loop

You are an autonomous researcher. Your job: make nimja's lexer **faster at
compile time** without changing its behaviour at all. You run experiments in a
loop. A script does the measuring, the correctness checks and the git
bookkeeping. You only write the lexer code.

Work from `experiments/lexer-speed/` (paths below are relative to it).

---

## The one metric

```
speedup = baseline_ms / candidate_ms        (higher is better, 1.0 = no change)
```

* `candidate_ms` — time of `nim c --compileOnly` on a fixture that imports
  **your** `src/nimja/lexer.nim` and lexes a fixed 2 MB corpus inside a
  `static:` block.
* `baseline_ms` — the same fixture compiled against the lexer at `HEAD`, i.e.
  the last **kept** commit.
* Both are measured 10 times in interleaved rounds, and the **min** of each
  side is used. Identical code measures 0.99–1.005, so a change is only kept
  when `speedup >= 1.01`.
* Lexing happens in the Nim **VM** at compile time. C-backend microbenchmarks
  are not the score. (Verified: a slice-based rewrite looked neutral in C but
  was 8 % slower in the VM.)

## The loop (repeat forever)

1. Read `../../src/nimja/lexer.nim` and pick **one** small, concrete idea.
2. Edit **only** `../../src/nimja/lexer.nim`.
3. Run:
   ```bash
   ./experiment.sh "short description of what you tried"
   ```
4. Read the last line of the output:
   `RESULT status=... speedup=... commit=... reason=...`
   * `keep` — it was faster and correct; the script committed it. Go back to 1
     and build on it.
   * `discard` — slower than the required 1 %. **Your edit has been reverted.**
     Go back to 1 with a different idea.
   * `wrong` — behaviour changed or a test failed. **Your edit has been
     reverted.** The reason names the log; read it, then go back to 1.
   * `crash` — your code did not compile or timed out. **Your edit has been
     reverted.** Read the log, fix the mistake next time.
5. Do not stop. Do not ask whether to continue. The human may be asleep.
   Keep going until you are manually interrupted.

Each experiment takes ~1 minute; a `keep` additionally runs the full test
suite (~80 s). If a single command runs longer than ~10 minutes, kill it and
treat it as crashed.

Do not do several ideas at once: you must be able to tell what helped.

## Rules (non-negotiable)

* **Only edit `src/nimja/lexer.nim`.** No new files, no new dependencies, no
  changes to tests, harness, docs, `readme.md`, or anything else. The script
  aborts on out-of-scope changes.
* **Behaviour must be identical** for every input: token kinds, values, line
  and column numbers, whitespace trimming, escape/triple-quote handling,
  `ValueError` on unterminated triple quotes, everything. A frozen reference
  lexer checks this on the fixed corpus, all repo templates, edge cases and
  2500 fresh random inputs. If the check fails, the idea is invalid — do not
  try to "fix" the check.
* **Never touch the harness**: `experiment.sh`, `setup.sh`, `harness/**`,
  `results.tsv`. `harness/FIXED.sha256` is verified on every run.
* **Do not game the metric.** No caching or memoising by input identity, no
  special-casing the benchmark corpus or its contents, no hardcoded results,
  no `importc`/`emit`/FFI/threads/GC tricks, no reading files at run time, no
  `{.push checks:off.}` or other check disabling, no changing the public API
  (`lex*`, `Token` fields, `NwtTokenKind`).
* **The script owns git.** Do not commit, stage or revert with git (the one
  exception is the documented `git reset --hard HEAD~1` when you want to undo
  your own last kept commit).
* **Prefer simple changes.** A 1 % win from 30 lines of hacks is not worth
  keeping; a 1 % win from deleting code is great. You may revert your own last
  commit if it turns out to be ugly or if it blocks a better idea:
  `git reset --hard HEAD~1` (only for your own last kept commit). Doing this
  requires re-measuring the new baseline with
  `./experiment.sh --baseline "after reverting <idea>"`.
* If you are stuck, re-read the lexer and the idea bank below; combine two
  earlier near-misses (their diffs are in `logs/*.patch`).

## What the script does (so you can interpret failures)

`./experiment.sh "desc"`:

1. verifies `harness/FIXED.sha256` and that only `src/nimja/lexer.nim` changed;
2. compiles and runs `harness/check.nim` against the frozen reference lexer
   (fast, < 2 s);
3. rebuilds and runs the A/B compile-time benchmark;
4. if `speedup >= 1.01`: runs `testament` on `tests/basic` and `tests/bugs`
   plus the lexer's own unittests, then commits `lexer: <desc>`;
5. otherwise reverts `src/nimja/lexer.nim` and saves the diff to
   `logs/<stamp>.patch`;
6. appends a row to `results.tsv` and prints the `RESULT` line.

Useful extras:

```bash
# lexer's own unittests only (fast, no scoring)
nim c -r --skipParentCfg:on --nimcache:.work/nc-units -o:.work/units \
  ../../src/nimja/lexer.nim

# runtime microbenchmark table (informational; needs a benchy checkout)
nim c -r -d:release --skipParentCfg:on --path:$HOME/projects/benchy/src \
  harness/bench_table.nim

# history and counterexample diffs
git log --oneline -15
cat results.tsv
ls logs/*.patch
```

Never edit these, and never run `nim` with `--path:` pointing at
`../../src` — the harness deliberately uses explicit relative imports because
a machine-wide `nim.cfg` can shadow `import nimja/lexer`.

## Idea bank (verified context + things worth trying)

Facts learned so far:

* Static text is the bulk of the corpus and of the VM time. `lexStr` appends
  one character at a time (`value &= ch`); in the Nim VM that is a **fast
  path** (`opcAddStrCh`). Building the value from one string slice was 8 %
  **slower** — do not repeat it.
* The original iterator probed `lexVar`, `lexComment`, `lexEval` (and on
  failure `lexStr`) for every token; each probe is a VM call plus a
  `Token()`/tuple construction. A single `case buf[pos+1]` dispatch before
  falling back to `lexStr` gave **1.97x** — already kept, it is the current
  baseline.
* Fixed overhead per `nim c` is ~0.6 s (startup + front-end); the lexing part
  is ~1.4 s of the ~2.4 s measured.

Ideas to try (one at a time; measure each):

1. **Reduce per-token VM work further.** After the dispatch, `lexVar/
   lexComment/lexEval` each re-check `{`/`{` again inside `lexBetween`. Add a
   variant that trusts the dispatcher (keep the checked one for the public
   `lexBetween` if needed) or fold all three into one proc taking the kind.
2. **Kill the `LexReturn` tuple / `Token()` churn.** Make the low-level
   routines write into a single `Token` var and return a bool, or return the
   kind + end position instead of constructing tuples.
3. **Cheaper `strip()`.** `lexBetween` calls `strutils.strip` on every
   variable/eval/comment value (allocates + Unicode-aware-ish). Compute the
   trimmed bounds manually and only copy when there is whitespace; the corpus
   has ~70k comment tokens.
4. **Fewer index checks in the hot loops.** `thisIs`/`nextIs`/`lastIs` are
   inline templates, but each recomputes `pos ± cnt` and `buf.len`. Hoist
   `let n = buf.len` into a local, use a single lookahead character, compare
   with `buf[pos+1]` after one bound check.
5. **Specialise `lexBetween` for the common case.** Most variables/evals have
   no escapes, no `"`, no triple quotes. Detect that cheaply while scanning and
   skip the extra `if` chain; fall back to the general path when needed.
6. **Restructure the iterator loop.** Avoid copying the tuple out of the
   helper (`yield` requires the token, but `pos.inc` / `continue` handling can
   be simplified). Try a `while` with an explicit state machine.
7. **Line/column bookkeeping.** `handleNl` runs per character. Check whether
   the newline test can be folded into the existing character tests (e.g.
   `case ch` instead of several `if`s), while keeping line/col exactly right.
8. **Shrink the compiled preamble.** Removing an unused import (e.g. if
   `strformat` is only needed on error paths) reduces the ~0.6 s fixed cost
   that the metric also sees — but only if behaviour stays identical and the
   code stays readable.
9. **Micro-tune `lexInnerStr`/`lexInnerStrTripple`** (string escapes, triple
   quotes). Rare in real templates but present in the corpus; keep it simple.
10. **Delete code.** Any redundant branch, duplicate check or unused helper
    that the reference check says is behaviour-neutral is a win, even a small
    one.

Do not chase sub-1 % changes: the noise floor is ~0.5 % and the threshold is
1 %. Go for structural wins (fewer VM operations per token / per character).

## If you run out of ideas

* Re-read `../../src/nimja/lexer.nim`, `readme.md` (lexer/whitespace sections)
  and the reference lexer side by side.
* Look at the biggest per-character work: what does each iteration of the
  `lexStr` / `lexBetween` loops actually execute in the VM?
* Combine a discarded near-miss with a kept change from `logs/*.patch`.
* Try removing an abstraction (helper proc, template, tuple) rather than
  adding one.

Never stop.

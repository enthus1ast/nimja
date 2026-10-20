# program.md — runtime rendering speed research loop

You are an autonomous researcher. Your job: make the code that nimja's
`compileTemplateStr` **generates** render faster, without changing the rendered
output in any way. You run experiments in a loop. A script does the measuring,
the correctness checks and the git bookkeeping. You only write generator or
runtime-helper code.

Work from `experiments/runtime-speed/` (paths below are relative to it).

---

## The one metric

```
speedup = baseline_ns / candidate_ns        (higher is better, 1.0 = no change)
```

* The same driver program is compiled twice: once with **your** `src` tree
  (candidate) and once with the `src` tree at `HEAD` (baseline, i.e. the last
  kept commit).
* It renders 17 timed workloads in 10 interleaved rounds. Each round runs the
  two binaries back-to-back and compares the summed **process CPU time**
  (user+sys, not wall clock) of that pair; the reported speedup is the
  **median of the 10 round ratios**. Lower candidate time is better.
* Identical code records ~0.99–1.01, so a change is only kept when
  `speedup >= 1.01`; a win below 1.03 is measured a second time, the lower
  value is recorded, and both must clear the threshold.
* This is **runtime** speed. Compile time is not scored here; a change that
  makes code generation slower is allowed as long as the result renders faster
  and the tests pass.

## The loop (repeat forever)

1. Read the per-workload timings from your last run; `logs/*-bench.log`
   contains `case <name>: cand=... base=... speedup=...` for every workload.
2. Pick **one** concrete idea and edit **only**:
   * `src/nimja/parser.nim` (code generation: appends, preallocation, folding,
     loops/ifs/procs), or
   * `src/nimja/nimjautils.nim` (runtime helpers such as `loop`, `cycle`,
     `truncate`, `slugify`, `spaceless`, `nl2br`), or
   * `src/nimja/escaping.nim` (HTML escaping), or
   * `src/nimja.nim` (umbrella module — rarely needed).
3. Run:
   ```bash
   ./experiment.sh "short description of what you tried"
   ```
4. Read the last line:
   `RESULT status=... speedup=... commit=... reason=...`
   * `keep` — faster and byte-identical output; the script committed it.
     Continue from there.
   * `discard` — not fast enough. **Your edit was reverted.** Try something
     else.
   * `wrong` — rendered output differs from the baseline, or the test suite
     failed. **Your edit was reverted.** Read the log, then continue.
   * `crash` — the generated code did not compile / timed out. **Your edit was
     reverted.** Read the log, fix your mistake next time.
5. Do not stop, do not ask whether to continue. The human may be asleep.

One experiment is ~40 s; a `keep` also runs the full test suite (~80 s). If a
command runs longer than ~10 minutes, kill it and treat it as crashed.

## Rules (non-negotiable)

* **Only edit the four files listed above.** No new files, no dependencies, no
  changes to tests, harness, docs or `readme.md`. The script aborts on
  out-of-scope changes and verifies `harness/FIXED.sha256`.
* **Rendered output must be byte-identical** for every template in the harness
  (the gate diffs all of them) and the full test suite must pass. This includes
  whitespace, escaping, loop indices, number formatting and error behaviour.
* **Do not game the benchmark.** No caching/memoising of rendered strings, no
  special-casing the harness templates or their inputs, no hardcoded outputs,
  no `importc`/`emit`/FFI/threads/GC tricks, no disabling runtime checks, no
  changing the public API or template semantics.
* **The script owns git.** Do not commit, stage or revert. The only exception:
  `git reset --hard HEAD~1` to undo your own last kept commit (then re-measure
  the baseline with `./experiment.sh --baseline "after reverting <idea>"`).
* **One experiment at a time.** Do not edit files while a measurement runs.
* **Prefer simple changes.** A 1 % win from 30 lines of hacks is not worth it;
  deleting work is the best kind of win. Do not chase sub-1 % changes: the
  noise floor is ~0.5 % and the threshold is 1 %.

## Where the time goes (baseline, `-d:release`, this machine)

Iteration counts are fixed; these are the per-workload times from the harness.
Use them to decide what is worth optimising.

Current baseline (~36 ms total, after the first campaign):

| workload | time | what it exercises |
|---|---|---|
| `escape` | ~3.0 ms | `htmlEscape` on a value full of `& < > " '` |
| `bigProc` | ~2.6 ms | large template-proc body (preallocated) |
| `vars` | ~2.5 ms | 8 variables and nothing else |
| `static` | ~2.5 ms | long static body + one variable |
| `nested` | ~2.4 ms | for + if + case over tuples |
| `page` | ~2.4 ms | realistic page with if + for |
| `proc` | ~2.3 ms | template-defined proc called 3× |
| `page-anon` | ~2.3 ms | page with empty loop and logged-out branch |
| `loop` | ~2.2 ms | `Loop` object + `cycle()` + first/last per iteration |
| `scalars` | ~2.1 ms | `$` of int/float/bool/char |
| `filters-slugify` | ~1.8 ms | `slugify` (ascii fold, per-char work) |
| `filters-spaceless` | ~2.0 ms | `spaceless` |
| `constBlock` | ~1.6 ms | const folding in a run |
| `filters-nl2br` | ~1.5 ms | `nl2br` |
| `mixedConst` | ~1.4 ms | const variables + runtime variable |
| `filters-truncate` | ~1.4 ms | `truncate` |
| `escape-plain` | ~1.0 ms | escaping a value with nothing to escape |

The profile is now **allocation bound**: a render that outputs a handful of
bytes still costs one `newStringOfCap` (~35 ns) plus the appends, and every
temporary string (`$` of a number, an escaped value, a `seq` literal) adds
another. The remaining wins came from removing allocations and from making the
preallocation estimate good enough that the result never grows.

### Verified findings (from the first campaign)

* **Preallocation dominates small renders.** Templates with no static text got
  no `newStringOfCap` at all and `vars`-style templates were 2.8× slower than
  they needed to be (`constBlock` 6.8×, `mixedConst` 7.7×). A floor of 64 and a
  per-variable allowance fixed that; a floor of 128 measured *worse* (0.92), so
  do not assume bigger is better.
* **`strutils.toLower(string)` is the rune-decoding version from `std/unicode`**
  (758 ns vs 80 ns for `toLowerAscii` on 37 bytes). `slugify` was spending
  ~90 % of its time there.
* **`$` of `int`/`float`/`char`/`bool` allocates a temporary string.** Emitting
  `addInt`/`addFloat`/`dst.add` instead was worth 1.85× on `loop` and 1.36× on
  `scalars`. `$` of a `string` is an inlined identity — leave it alone.
* **`loop()` built two `Option[T]` per iteration** (refcount traffic) even
  though most templates never read `previtem`/`nextitem`; accessors instead of
  fields: 1.86× on `loop`. `cycle(@[...])` also allocated a `seq` per call.
* **Bulk copies beat per-char appends** in `nl2br`/`spaceless`/`truncate`
  (`addSlice` = `setLen` + `copyMem`); `splitWhitespace()` in `truncate`
  allocated a seq plus a string per word.
* **SIMD (nimsimd/SSE2) is *not* a win for short values.** It paid off only for
  escaping long values (1600 chars: 492 → 174 ns, 2.8×) and is neutral below
  ~32 bytes. For scanning, `strutils.find` (a plain loop) matched SIMD on
  40-byte inputs. Vectorize only where the strings are actually long.
* **`.inline` procs with `var` parameters can be a pessimisation**: writing
  through a `var int` cursor prevented register allocation and made the escape
  write pass 2× slower; a `template` fixed it.
* The `loop`, `vars`, `constBlock` and `mixedConst` workloads are the smallest
  and noisiest (0.3–1.6 ms per round): single-run swings of 0.5×–3× happen
  without any real change, so confirm such a case locally (copy the template
  into a scratch driver, `taskset -c 0`) before believing it.

## Idea bank

Already done (do not redo): escaping fast path + SIMD scan, `$`-free
`int`/`float`/`char`/`bool` appends, lazy `previtem`/`nextitem`, allocation-free
`cycle(@[...])`, preallocation floor/allowances/for-body multiplier, bulk-copy
`nl2br`/`spaceless`/`truncate`, one-pass `slugify` with `toLowerAscii`.

What is left is mostly *allocation* and *append* counting:

1. **Per-render allocations.** Every render allocates its `result`; escaped
   values, numbers (`$`), `seq` literals and template-proc calls allocate more.
   Any way to avoid one of those is a win. (Changing `escapeWith`'s contract is
   an API change, so `htmlEscape` must keep returning a value.)
2. **Better output-size estimate.** The estimate cannot know loop lengths or
   value widths. Ideas: count the biggest `if`/`case` branch instead of all of
   them (it currently sums every branch, which over-allocates), weight static
   text by the enclosing `for`-depth, or estimate per-variable size from the
   static text around it. Only worth it when it removes a `realloc`.
3. **Fewer appends.** Adjacent literal + variable appends are already merged;
   look at control-flow boundaries (`if` inside a run currently forces a
   separate append for the literal before it) and `case`/`when` bodies.
4. **Template procs/funcs.** A proc body allocates its own result, which the
   caller then copies. Inlining is not possible, but the prealloc threshold and
   the body's own estimate can be tuned (currently `>= 15` static chars).
5. **`$` on enums / other types.** `char`/`bool`/`int`/`float` are handled;
   enums still go through `$` (a temporary string per value).
6. **`addInt`-style appends inside loops**: check that `{{loop.index}}`-like
   cases now cost nothing extra (they do) and look for other repeated
   conversions (e.g. `{{ i * 2 }}`, `$` of a loop variable in a `case`).
7. **Escaping**: the escaping path allocates the escaped value, then copies it
   into the result. Reducing that to one pass would need a generator-level
   contract change (`escapeWith`), which is out of scope here — but the escaping
   helpers themselves (scan, sizing, `HTMLSafeStr`) can still be tuned.
8. **Delete work.** Any temporary, allocation or repeated conversion the gate
   proves unnecessary is a win.

If you run out of ideas: re-read `src/nimja/parser.nim`'s `ast*` procs, compare
the generated code (`-d:dumpNwtAstPretty` / `-d:dumpNwtMacro`), look at the
per-workload lines in `logs/*-bench.log`, and combine near-misses from
`logs/*.patch`.

Never stop.

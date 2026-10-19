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
* It renders 17 timed workloads and reports the **sum of the per-workload
  minimum nanoseconds** over 10 interleaved rounds. Lower is better.
* Identical code measures 0.995–1.005, so a change is only kept when
  `speedup >= 1.01`; a win below 1.03 is measured a second time and must
  reproduce.
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
Use them to decide what is worth optimising (`loop` and `slugify` dominate).

| workload | time | what it exercises |
|---|---|---|
| `filters-slugify` | ~11.4 ms | `slugify` (unicode folding, per-char work) |
| `loop` | ~10.3 ms | `Loop` object + `cycle()` + first/last per iteration |
| `proc` | ~7.1 ms | template-defined proc called 3× |
| `scalars` | ~5.8 ms | `$` of int/float/bool/char |
| `escape` | ~5.6 ms | `htmlEscape` on a value full of `& < > " '` |
| `escape-plain` | ~5.6 ms | `htmlEscape` on a value with nothing to escape |
| `static` | ~5.5 ms | long static body + one variable |
| `filters-nl2br` | ~5.5 ms | `nl2br` |
| `filters-spaceless` | ~5.2 ms | `spaceless` |
| `mixedConst` | ~4.7 ms | const variables + runtime variable |
| `vars` | ~4.6 ms | 8 variables and nothing else |
| `nested` | ~3.3 ms | for + if + case over tuples |
| `bigProc` | ~3.3 ms | large template-proc body (preallocated) |
| `page` / `page-anon` | ~3.1 ms | realistic page with if + for |
| `constBlock` | ~3.1 ms | const folding in a run |
| `filters-truncate` | ~2.7 ms | `truncate` |

## Idea bank

Start with the biggest workloads; each item is one experiment.

1. **Escaping fast path.** `escapeHtmlChars` always allocates a result and
   appends character by character, even when the value contains no
   `& < > " '`. Scan first and return the input unchanged when possible
   (`HTMLSafeStr` makes that cheap); also copy non-special runs in bulk instead
   of one `add` per character. This targets `escape` and especially
   `escape-plain`.
2. **Escaping is idempotent.** `htmlEscape` on an `HTMLSafeStr` returns it
   unchanged. Check what the generated code does for `{{x|e}}` with
   `escapeWith = htmlEscape` and remove redundant work if the code generator
   emits two escaping calls.
3. **`loop()` helper.** It constructs a `Loop[T]` per iteration, calls
   `a.len()` several times, and builds `Option[T]` prev/next. Hoist the length,
   compute indices incrementally, keep semantics identical (index/first/last/
   revindex/previtem/nextitem/cycle).
4. **String helpers.** `slugify`, `spaceless`, `nl2br`, `truncate` are real
   per-byte loops with allocations. Preallocate with `newStringOfCap`, avoid
   intermediates, use `find`/slice copies for unchanged runs, and skip the
   allocation entirely when the input is already in the target form.
5. **Preallocation of the render result.** `compile` computes an output
   capacity from the final node tree (`staticLen`, `noPreallocatedString`).
   Check whether template procs and the main result get a good `newStringOfCap`
   (the current rule is `>= 64` static chars for proc bodies) and whether the
   estimate can include known-length parts without changing behaviour.
6. **Fewer appends.** How does `astRun`/`astVariable` emit appends? Group
   adjacent literals, fold more constant expressions, or emit a single
   `add` of a concatenated literal when the pieces are static.
7. **`$` vs direct add.** For `string`-typed variables the generated
   `nwtStrProc` call may be redundant. See whether the generator can emit
   `result.add x` when the type is already `string` (or `HTMLSafeStr` under
   escaping) without changing semantics for other types.
8. **Control-flow codegen.** `if`/`for`/`case` bodies currently emit many small
   appends into the same `result`. Look for repeated work per iteration
   (temporary strings, `$` on indices, bounds checks).
9. **Template procs/funcs.** Preallocation already exists for large bodies;
   check small ones and whether locals can be avoided.
10. **Delete work.** Any allocation, temporary, or repeated conversion that the
    gate proves unnecessary is a win.

If you run out of ideas: re-read `src/nimja/parser.nim`'s `ast*` procs, compare
the generated code (`-d:dumpNwtAstPretty` / `-d:dumpNwtMacro`), look at the
per-workload lines in `logs/*-bench.log`, and combine near-misses from
`logs/*.patch`.

Never stop.

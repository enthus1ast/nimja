# Lexer speed autoresearch

An [autoresearch](https://github.com/karpathy/autoresearch)-style loop for
nimja's **compile-time lexer speed**. An agent edits exactly one file
(`src/nimja/lexer.nim`), measures it against the last kept commit, keeps it if
it is faster and behaviour-identical, and otherwise the edit is reverted.

The loop is already wired up: you (or a local model) only ever need

```bash
cd experiments/lexer-speed
# edit ../../src/nimja/lexer.nim
./experiment.sh "what you tried"
```

The last line of the output is
`RESULT status=<keep|discard|wrong|crash> speedup=<x> commit=<sha> reason=<...>`.

## Why compile time is the metric

nimja lexes templates inside the Nim VM at compile time (`compileTemplateStr`
is a macro), so the thing users feel is **VM** lexing speed, not C-backend
speed. A runtime microbenchmark would happily reward changes that do nothing
for real builds (and vice versa: building token values from one slice instead
of per-character `&=` looks fine in C but was measured **8 % slower** in the
VM, see `results.tsv`).

So the score is:

```
nim c --compileOnly  <fixture that lexes a fixed 2 MB corpus in a static: block>
```

compiled once against the candidate lexer and once against the lexer at
`HEAD` (the last kept commit), interleaved in the same run so machine drift
hits both sides equally:

```
speedup = min(baseline_ms) / min(candidate_ms)
```

`min` over 10 interleaved rounds; identical code measures 0.99–1.005, so the
keep threshold is **1.01** (1 %). A run takes ~1 minute; a keep additionally
runs the full test suite (~80 s). The runtime benchy table
(`harness/bench_table.nim`) is available for insight but does not decide
anything.

## Correctness gate (always before speed)

`harness/check.nim` compares the candidate against a frozen copy of the lexer
(`harness/reference/lexer_reference.nim`) token by token — kind, value, line,
column, and raise behaviour — on

1. the fixed 2 MB corpus,
2. every real `*.nimja` template in the repo,
3. ~70 hand-picked edge cases,
4. 2500 structured random inputs with a **fresh random seed every run**.

A would-be keep then also has to pass `testament` `tests/basic/*.nim` +
`tests/bugs/*.nim` and the lexer's own unittests.

This means the lexer's exact observable behaviour is frozen: whitespace
trimming, escapes, triple quotes, line/column math, unterminated-block
handling, even the `ValueError` on unterminated triple-quoted strings.

## Layout

| Path | Purpose |
|------|---------|
| `program.md` | instructions for the research agent (point your model here) |
| `setup.sh` | create `autoresearch-lexer/<tag>`, record the baseline |
| `experiment.sh` | one experiment: check → A/B bench → gate → commit/revert → log |
| `results.tsv` | the experiment log (untracked, tab-separated) |
| `logs/` | per-run logs; `*.patch` keeps the diff of discarded attempts |
| `harness/FIXED.sha256` | integrity list of every file the agent must not touch |
| `harness/corpus/corpus.txt` | fixed 2 MB benchmark corpus |
| `harness/reference/` | frozen lexer + namespace wrapper |
| `harness/check.nim` | correctness comparison |
| `harness/bench_metric.nim` | the A/B compile-time score |
| `harness/bench_table.nim` | human-facing benchy table (runtime, informational) |
| `harness/gen_corpus.py` | how the corpus was generated (do not re-run mid-run) |

`experiment.sh` refuses to run if any file in `FIXED.sha256` changed, or if
anything outside `src/nimja/lexer.nim` was modified/created.

## Quick start

```bash
cd experiments/lexer-speed
./setup.sh                 # branch autoresearch-lexer/lexer-YYYYMMDD + baseline
# now edit ../../src/nimja/lexer.nim
./experiment.sh "my idea"
```

Point a local model at the repo root with a prompt like:

```
Read experiments/lexer-speed/program.md and start the experiment loop.
Never stop until I interrupt you.
```

Everything the model needs to know (commands, metric, rules, idea bank) is in
`program.md`; keep iterating on that file, not on the harness.

## results.tsv

Tab-separated, untracked (do not commit it):

```
commit  candidate_ms  baseline_ms  speedup  rt_mbps  status  description
```

`status`: `keep`, `discard` (slower), `wrong` (behaviour/test failure),
`crash` (did not compile / timed out). Rows for discarded attempts still show
the measured numbers, and their diff is saved in `logs/<stamp>.patch`. Only
`keep` rows advance the branch (the script makes the commit itself).

## Validation record

This harness was validated before hand-off (see `results.tsv` and `logs/`):

* identical code measures `speedup` 0.99–1.005 (noise floor);
* "build static text from one slice" measured 0.92 (slower in the VM) → discarded;
* "single dispatch instead of 3 delimiter probes" measured **1.97** → kept.

## Machine-specific notes

* `$HOME/projects/nim.cfg` (Nimby) adds `--path:nimja/src`, which can shadow
  this checkout. The harness therefore compiles with `--skipParentCfg:on` and
  imports the lexer through explicit relative paths / copies, never through
  `import nimja/lexer`.
* The benchmark is pinned with `taskset -c 0` when available.
* The benchy table needs a benchy checkout:
  `nim c -r -d:release --skipParentCfg:on --path:$HOME/projects/benchy/src harness/bench_table.nim`.

## Branches

`setup.sh` creates `autoresearch-lexer/<tag>` (not `autoresearch/<tag>`,
because the repo already has a branch named `autoresearch`). To adopt the
results of a run:

```bash
git checkout autoresearch
git merge autoresearch-lexer/<tag>
```

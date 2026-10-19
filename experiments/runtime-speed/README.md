# Runtime speed autoresearch

An [autoresearch](https://github.com/karpathy/autoresearch)-style loop for
nimja's **runtime rendering speed**: the speed of the code that
`compileTemplateStr` generates. An agent edits the code generator / runtime
helpers, measures the candidate against the last kept commit, keeps it if it is
faster and renders byte-identical output, otherwise the edit is reverted.

This repository is dedicated to that loop.

```bash
cd experiments/runtime-speed
# edit ../../src/nimja/parser.nim (or nimjautils.nim / escaping.nim)
./experiment.sh "what you tried"
```

The last line of the output is
`RESULT status=<keep|discard|wrong|crash> speedup=<x> commit=<sha> reason=<...>`.

## How the score works

`harness/measure.nim` compiles the same driver twice:

* **candidate** — against a snapshot of the working tree's `src`
  (`--path:.work/cand/src`),
* **baseline** — against `src` extracted from `HEAD` (`git archive HEAD src`).

The driver (`harness/driver.nim` + `harness/templates.nim`) contains 17 timed
workloads (realistic page, static-heavy, variables only, template procs, const
folding, autoescaping, `loop()`, nested control flow, string helpers, scalars)
and renders each with fixed inputs. It never imports `nimja` by name from the
search path, so a machine-wide `nim.cfg` cannot shadow either side.

Then:

1. **Gate**: both binaries run with `GATE=1` and render *all* templates
   (timed ones plus if/case/while/when/scope/proc/func/filter/unicode
   coverage). The outputs must be **byte-identical**.
2. **Bench**: both binaries run in 10 interleaved rounds (alternating which
   side runs first). Per workload the minimum of 5 in-process samples and 10
   rounds is kept, and the per-workload minima are summed:

   ```
   speedup = baseline_ns / candidate_ns
   ```

   Identical code measures 0.995–1.005 on a quiet machine. A keep needs
   `speedup >= 1.01`; wins below 1.03 are re-measured and both measurements
   must clear the threshold (`--baseline` runs are logged as a reference).

A would-be keep must then also pass `testament` on `tests/basic` and
`tests/bugs` (~80 s). Compile time is *not* part of this score (that is a
separate experiment); the generated code only has to compile.

## Layout

| Path | Purpose |
|------|---------|
| `program.md` | instructions for the research agent (point your model here) |
| `setup.sh` | create `autoresearch-runtime/<tag>`, record the baseline |
| `experiment.sh` | one experiment: scope → gate+bench → confirm → test suite → commit/revert |
| `results.tsv` | the experiment log (untracked, tab-separated) |
| `logs/` | per-run logs; `*.patch` keeps the diff of discarded attempts |
| `harness/FIXED.sha256` | integrity list of every file the agent must not touch |
| `harness/templates.nim` | fixed templates + fixed inputs + `renderAll` (gate) |
| `harness/main_body.nim` | timed workloads / gate dump (`GATE=1`) |
| `harness/driver.nim` | `import nimja` + include the body (compiled per side) |
| `harness/measure.nim` | builds both drivers, runs the gate and the A/B benchmark |

`experiment.sh` refuses to run if any file in `FIXED.sha256` changed, or if
files outside the allowed list were modified.

## Quick start

```bash
cd experiments/runtime-speed
./setup.sh                 # branch autoresearch-runtime/runtime-YYYYMMDD + baseline
# now edit ../../src/nimja/parser.nim (or helpers)
./experiment.sh "my idea"
```

Point a local model at this repository with a prompt like:

```
Read experiments/runtime-speed/program.md and start the experiment loop.
Never stop until I interrupt you.
```

Doc edits (`program.md`, `README.md`) must be committed before the next
experiment; the runner aborts on uncommitted out-of-scope changes.

## results.tsv

Tab-separated, untracked (do not commit it):

```
commit  candidate_ns  baseline_ns  speedup  status  description
```

`status`: `keep`, `discard` (slower), `wrong` (rendered output or test suite
differs), `crash` (did not compile / timed out). Discarded diffs are saved in
`logs/<stamp>.patch`; only `keep` rows advance the branch (the script commits).

## Machine-specific notes

* `$HOME/projects/nim.cfg` (Nimby) adds `--path:nimja/src`; the harness passes
  `--skipParentCfg:on` and explicit `--path` at every compile.
* The benchmark is pinned with `taskset -c 0` when available.
* Known pre-existing parser bug (not introduced here): a string node between
  `{% case %}` and the first `{% of %}` (e.g. a newline) raises
  "should not happen: str". `templates.nim` keeps `{% of ... %}` on the same
  line as `{% case ... %}`; do not "fix" that in the harness.

## Branches

`setup.sh` creates `autoresearch-runtime/<tag>` (the repo already has an
`autoresearch` branch, so it cannot be `autoresearch/<tag>`). Adopt a run with

```bash
git checkout autoresearch
git merge autoresearch-runtime/<tag>
```

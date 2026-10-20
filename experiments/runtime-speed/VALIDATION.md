# Harness validation (hand-off record)

The loop was exercised end to end on 2026-10-19 on a machine that was
simultaneously running the research agent's model server and other builds.
Raw rows are in `results.tsv` (untracked, reset by `setup.sh`); logs and
discarded patches are in `logs/` (gitignored).

## Metric tuning (all verified on this machine)

1. **Wall clock was unusable under real load.** The first baseline run
   (identical code) measured `speedup 0.95` with per-workload ratios from 0.60
   to 1.01, because a llama-server and another agent were competing for the
   CPU. `taskset` is not enough when the machine is busy.
2. **Process CPU time (`CLOCK_PROCESS_CPUTIME_ID`) fixed the gross noise.**
   Verified stand-alone: a fixed loop measures 22.1 ms CPU time idle and
   20.9 ms with eight `yes` processes pinned to the same core.
3. **Median of paired per-round ratios removed the remaining drift.** A single
   min-of-minima measurement of identical code still deviated by up to +2 %
   (frequency scaling). The score is now `median(baseline_total /
   candidate_total)` over 10 rounds, where each round runs both binaries
   back-to-back. Recorded identical-code values: 0.9937, 0.9949, 0.9958,
   0.9982, 1.0096.
4. **Marginal wins are re-measured.** Any `speedup` below 1.03 is measured a
   second time; the lower value is recorded and both must clear 1.01.

## Noise floor rows (identical code, no changes)

```
37e4e23  87008049  87336289  1.0038  keep  baseline (unchanged generator)      [wall clock]
37e4e23  86867799  87054236  1.0021  keep  noise check 1                       [wall clock]
37e4e23  86922777  88628125  1.0196  keep  noise check 2                       [wall clock]
37e4e23  87830719  87053206  0.9911  keep  noise check 3                       [wall clock]
728d8f4 142434776 145662807 0.9949  keep  noise check median 1               [CPU + median]
728d8f4  87411779  88171850 0.9958  keep  noise check median 2               [CPU + median]
728d8f4  87365015  87861647 0.9937  keep  noise check median 3               [CPU + median]
728d8f4  87780115  88782196 1.0096  keep  noise check median 4               [CPU + median]
728d8f4  87429666  87510566 0.9982  keep  noise check median 5               [CPU + median]
```

## Kept: escaping fast path → 1.0368

`escapeHtmlChars` always allocated a result and appended character by character,
even for values with nothing to escape. It now scans first and returns the
input unchanged when it contains none of `& < > " '`:

```
candidate_ns: 84905976   baseline_ns: 87615547   speedup: 1.0368
```

`harness/check`-equivalent gate (byte-identical rendered output) passed and the
full gate (`tests/basic`, `tests/bugs`) passed, so the loop committed
`bd1dcc3  runtime: escaping: avoid allocating when nothing needs escaping`.
`escape-plain` dropped from ~5.5 ms to ~3.0 ms.

## Discarded: deliberate slowdown → 0.9703 (revert path verified)

Re-introducing a copy for the "nothing to escape" case (behaviour identical,
slower) was measured and discarded:

```
candidate_ns: 87537236   baseline_ns: 84641227   speedup: 0.9703
```

The working tree was left clean, the diff was saved to `logs/<stamp>.patch`,
and `results.tsv` got a `discard` row.

## Notes

* The gate compares the complete rendered output of every template in
  `harness/templates.nim` (17 timed workloads plus if/case/while/when/scope/
  proc/func/filter/unicode coverage), so any semantic change fails before the
  speed number is considered.
* Pre-existing parser bug found while writing the templates: a string node
  between `{% case %}` and the first `{% of %}` (e.g. a newline) raises
  `should not happen: str`. The harness keeps `{% of ... %}` on the same line.

# Harness validation (hand-off record)

Before hand-off the loop was exercised end to end on 2026-10-19. Logs and
discarded patches are in `logs/` (gitignored); the raw rows are reproduced at
the bottom of this file, because `results.tsv` is reset by `setup.sh` for every
new run.

## Noise floor

Identical code measured against itself, 8–10 interleaved repetitions:

| runs | speedup values |
|------|----------------|
| 5× (older metric) | 1.0057, 0.9994, 1.0058, 1.0028, 0.9989 |
| 4× (raw metric)  | 1.0025, 0.9925, 0.9979, 0.9967 |

So identical code lands in ~0.99–1.005, hence the `speedup >= 1.01` keep
threshold.

## Discarded: static text from one slice → 0.92 (slower)

`lexStr` built `Token.value` with `value &= ch` per character. Replacing that
with a single `buf[start ..< stop]` slice is the obvious C-backend
optimisation, but in the Nim VM `&=` on a string is the fast path
(`opcAddStrCh`) and the slice path was **8 % slower**:

```
candidate_lex_ms: 3855.0   baseline_lex_ms: 3533.0   speedup: 0.9165
```

The checker accepted it (behaviour identical) and the loop discarded it.

## Kept: single opener dispatch instead of three delimiter probes → 1.97

The iterator probed `lexVar`, `lexComment`, `lexEval` for every token before
falling back to `lexStr`, so a plain static-text token paid for three failed
proc calls plus tuple/`Token` construction. Dispatching once on
`buf[pos] == '{'` + `buf[pos + 1]` removed those probes:

```
candidate_lex_ms: 1780.0   baseline_lex_ms: 3509.0   speedup: 1.9713
```

`harness/check.nim` (reference equivalence) passed, and the full gate
(`tests/basic`, `tests/bugs`, lexer unittests) passed, so the loop committed
`d4ea1eb  lexer: single dispatch instead of 3 delimiter probes` on
`autoresearch-lexer/lexer-20261019` (fast-forwarded into `autoresearch`).

Measured on this machine (2 MB corpus, `nim c --compileOnly`): ~4.13 s before,
~2.40 s after (~0.6 s of that is fixed front-end/startup overhead).

## Metric history

The first version subtracted a separately measured no-op fixture to report
"pure VM lexing time". The no-op compile time turned out to swing by up to
400 ms between runs, which polluted the metric by ~25 %. The score is now the
raw interleaved `nim c --compileOnly` time, which is much more stable
(see the noise rows above); the no-op subtraction was removed.

## Raw rows (from the discarded `results.tsv`; logs are in `logs/`)

`lex_ms` rows used the old no-op-subtracted metric, `ms` rows the current raw
total metric. `keep` on a noise row only means "baseline measurement".

```
commit  candidate  baseline  speedup  metric  status   description
175b85b 3497.2     3517.0    1.0057   lex_ms  keep     baseline (unchanged lexer)
175b85b 3501.4     3499.3    0.9994   lex_ms  keep     noise check 2
175b85b 3488.9     3509.1    1.0058   lex_ms  keep     noise check 3
4e4a1b7 3517.0     3527.0    1.0028   lex_ms  keep     noise check 4 (8 reps, pinned)
4e4a1b7 3523.0     3519.0    0.9989   lex_ms  keep     noise check 5 (8 reps, pinned)
4e4a1b7 3855.0     3533.0    0.9165   lex_ms  discard  lexStr: build static text from one slice
d4ea1eb 1780.0     3509.0    1.9713   lex_ms  keep     single dispatch instead of 3 delimiter probes
d4ea1eb 1392.0     1401.0    1.0065   lex_ms  keep     noise check on the new baseline
9ffd0b2 2423.0     2429.0    1.0025   ms      keep     noise check 7 (raw total metric)
9ffd0b2 2416.0     2398.0    0.9925   ms      keep     noise check 8 (raw total metric)
64a8793 2406.0     2401.0    0.9979   ms      keep     noise check 9 (10 reps)
64a8793 2404.0     2396.0    0.9967   ms      keep     noise check 10 (10 reps)
0a8ebd5 2396.0     2396.0    1.0000   ms      keep     baseline (unchanged lexer)
```

# Harness validation (hand-off record)

Before hand-off the loop was exercised end to end on 2026-10-19. Raw rows are
in `results.tsv` (untracked); logs and discarded patches are in `logs/`
(gitignored). This file is the durable summary.

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

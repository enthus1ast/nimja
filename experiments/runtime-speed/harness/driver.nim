## The benchmark/gate driver.
##
## It is compiled twice by `harness/measure.nim`: once with `--path` pointing at
## the candidate `src` tree and once at the baseline (`HEAD`) `src` tree. The
## templates in `templates.nim` are compiled by whichever code generator that
## tree contains, which is exactly what this experiment measures.
##
## This file is FIXED. Do not modify it.
import nimja

include "main_body.nim"

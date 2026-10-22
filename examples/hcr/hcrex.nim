import nimja/hcrutils # Nimja's hot code reloading utilities
import shared # for the TestObj that is also used in tmpls.nim
import asyncdispatch, os
type
    # You must declare the proc definition from your tmpls.nim here as well.
    ProcNoParam = proc (): string {.gcsafe, stdcall.}
    ProcTestObj = proc (to: TestObj): string {.gcsafe, stdcall.}
    ProcId = proc (id: string): string {.gcsafe, stdcall.}
    ProcSeq = proc (a: seq[string]): string {.gcsafe, stdcall.}
    ProcIS = proc (ii: int, ss: string): string {.gcsafe, stdcall.}

# We watch the templates folder for change (and also tmpls.nim implicitly)
let cw = newChangeWatcher(@[getAppDir() / "templates/"])
cw.ccparams = "  "
asyncCheck cw.recompile() # if a change is detected we recompile tmpls.nim

const to = TestObj(foo: "foo!")

# This example renders every template once, so it needs no web framework.
# In a real application you would call `dyn` from your webserver's handlers.
# Note: `dyn` declares `procptr` in the calling scope, so each call needs its own
# `block`.
proc renderAll() =
  block: echo dyn(ProcNoParam, "myindex")
  block: echo dyn(ProcId, "detail", "123")
  block: echo dyn(ProcSeq, "error", @["a", "b", "c"])
  block: echo dyn(ProcIS, "about", 1234, "foobaa")
  block: echo dyn(ProcTestObj, "oop", to)

renderAll()
waitFor sleepAsync(2_000)

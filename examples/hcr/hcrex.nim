import nimja/hcrutils # Nimja's hot code reloading utilities
import shared # for the TestObj that is also used in tmpls.nim
import jester, os
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

routes:
  get "/":
    resp dyn(ProcNoParam, "myindex")

  get "/id/@id":
    resp dyn(ProcId, "detail", @"id")

  get "/error":
    resp dyn(ProcSeq, "error", @["a", "b", "c"])

  get "/about":
    resp dyn(ProcIS, "about", 1234, "foobaa")

  get "/oop":
    resp dyn(ProcTestObj, "oop", to)


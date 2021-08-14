import asynchttpserver, asyncdispatch
import nimja/parser
import os, random # os and random are later used in the templates, so imported here

############
import system/nimscript
import compiler/nimeval
import compiler/ast
import compiler/llstream
import compiler/pathutils
import compiler/renderer # To get the correct `$` procedure
import os

echo cmpic("asdf", "asdf")

# for p in @[
#     stdlib,
#     stdlib / "pure",
#     stdlib / "core",
#     stdlib / "pure" / "collections"
#   ]:
#   conf.searchPaths.add(AbsoluteDir p)

let stdlib = findNimStdLibCompileTime()
echo stdlib
var inter = createInterpreter(
  """C:\Users\david\projects\nimja\examples\fromReadme\dyn.nims""",
  [
    stdlib,
    $toAbsoluteDir("./"),
    """C:\Users\david\projects\nimja\src""",
    stdlib / "pure",
    stdlib / "core",
    stdlib / "pure/collections"
  ],
  defines = @[("nimscript", "true"), ("nimconfig", "true")],
  registerOps = true
)

let path = toAbsolute("dyn.nims", toAbsoluteDir("./"))
proc call(): string =
  var script = llStreamOpen(filename = path, mode = fmRead)
  try:
    inter.evalScript(script)
  except:
    ## This seems to not being catchable
    echo "cannot execute!"
    echo getCurrentExceptionMsg()

  for sym in inter.exportedSymbols:
    echo sym.name.s, " = ", inter.getGlobalValue(sym)

  let sym = inter.selectUniqueSymbol("ret")
  let ret = inter.getGlobalValue(sym)
  return ret.strVal
  script.llStreamClose()

############

proc main {.async.} =
  var server = newAsyncHttpServer()

  proc cb(req: Request) {.async, gcsafe.} =
    await req.respond(Http200, call())

  server.listen Port(8080)
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(cb)
    else:
      poll()

asyncCheck main()
runForever()
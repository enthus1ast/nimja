import asynchttpserver, asyncdispatch
import nimja/parser
import os, random # os and random are later used in the templates, so imported here

# type
#   User = object
#     name: string
#     lastname: string
#     age: int

# proc renderIndex(title: string, users: seq[User]): string =
#   ## the `index.nwt` template is transformed to nim code.
#   ## so it can access all variables like `title` and `users`
#   ## the return variable could be `string` or `Rope` or
#   ## anything which has a `&=`(obj: YourObj, str: string) proc.
#   compileTemplateFile(getScriptDir() / "index.nwt")


############
import system/nimscript
import compiler/nimeval
import compiler/ast
import compiler/llstream
import compiler/pathutils
import os

echo cmpic("asdf", "asdf")
var inter = createInterpreter(
  # "dyn.nims",
  """C:\Users\david\projects\nimja\examples\fromReadme\dyn.nims""",
  [
    findNimStdLibCompileTime(),
    $toAbsoluteDir("./"),
    """C:\Users\david\projects\nimja\src""",
    """C:\Users\david\.choosenim\toolchains\nim-1.4.8\lib\pure\""",
    """C:\Users\david\.choosenim\toolchains\nim-1.4.8\lib\core\""",
    """C:\Users\david\.choosenim\toolchains\nim-#head\lib\pure\collections\"""
  ],
  # defines = @[nimscript],
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
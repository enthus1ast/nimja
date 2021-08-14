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
while true:
  var script = llStreamOpen(filename = path, mode = fmRead)
  try:
    inter.evalScript(script)
  except:
    echo "cannot execute!"
    echo getCurrentExceptionMsg()
  # let ret = getGlobalValue(inter, PSym)
  # echo repr inter
  let sym = inter.selectUniqueSymbol("ret")
  # echo sym.
  let ret = inter.getGlobalValue(sym)
  # sym
  echo ret.strVal
  # sleep(1000)
  script.llStreamClose()
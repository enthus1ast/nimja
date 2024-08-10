discard """
  joinable: false
"""
{.define: dumpNwtMacro.}
{.define: dumpNwtAst.}
include ../../src/nimja/parser
# import unittest

# echo "#############################"
# echo "getScriptDir:                       :",  getScriptDir()
# echo "getScriptDirProc:                   :",  getScriptDirProc()
# echo "getScriptDirMacro:                  :",  getScriptDirMacro()
# echo "getScriptDirII:                     :",  getScriptDirII()
# echo "getScriptDirIItemplate              :",  getScriptDirIItemplate()
# echo "getScriptDirIItemplate2             :",  getScriptDirIItemplate2()
# echo "currentSourcePath().parentDir() user:", currentSourcePath().parentDir()
# template ii(): string =
#   instantiationInfo(-1, true).filename.parentDir()
# echo "instantiationInfo(-1, true).filename:", ii
# echo "#############################"

# proc inner(): string =
#   # compileTemplateFile("doubleExtends" / "inner.nimja", baseDir = getScriptDir())
#   # compileTemplateFile("doubleExtends" / "inner.nimja", baseDir = "") #, baseDir = currentSourcePath().parentDir())
#   compileTemplateFile(getScriptDir() / "doubleExtends" / "inner.nimja", baseDir = "") #, baseDir = currentSourcePath().parentDir())
# echo inner()


proc outer(): string =
  echo "#############################"
  echo currentSourcePath()
  echo currentSourcePath().parentDir()
  echo "#############################"
  const baseDir = currentSourcePath().parentDir()
  # compileTemplateFile("doubleExtends" / "outer.nimja", baseDir = baseDir)
  # echo "GSCD: ", getScriptDir()
  compileTemplateFile("doubleExtends" / "outer.nimja", baseDir = getScriptDir())
  # compileTemplateFile("doubleExtends" / "outer.nimja")
assert outer() == "baseouterouterbase"

# proc base(): string =
#   compileTemplateFile(getScriptDir() / "doubleExtends" / "base.nimja")
# echo base()


# assert foo() == "baseouterinnerouterbase"

# check "baseouterinnerouterbase" == inner()
# check "baseouterouterbase" == outer()
# check "basebase" == base()

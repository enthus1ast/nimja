discard """
  joinable: false
"""
{.define: dumpNwtMacro.}
{.define: dumpNwtAst.}
include ../../src/nimja/parser
import unittest

# proc inner(): string =
#   compileTemplateFile(getScriptDir() / "doubleExtends" / "inner.nwt")
# echo inner()

proc outer(): string =
  compileTemplateFile(getScriptDir() / "doubleExtends" / "outer.nwt")
echo outer()

# proc base(): string =
#   compileTemplateFile(getScriptDir() / "doubleExtends" / "base.nwt")
# echo base()


# assert foo() == "baseouterinnerouterbase"

# check "baseouterinnerouterbase" == inner()
# check "baseouterouterbase" == outer()
# check "basebase" == base()
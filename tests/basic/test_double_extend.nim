discard """
  joinable: false
"""
{.define: dumpNwtMacro.}
{.define: dumpNwtAst.}
include ../../src/nimja/parser
# import unittest

# proc inner(): string =
#   compileTemplateFile(getScriptDir() / "doubleExtends" / "inner.nimja")
# echo inner()

proc outer(): string =
  compileTemplateFile(getScriptDir() / "doubleExtends" / "outer.nimja")
assert outer() == "baseouterouterbase"

# proc base(): string =
#   compileTemplateFile(getScriptDir() / "doubleExtends" / "base.nimja")
# echo base()


# assert foo() == "baseouterinnerouterbase"

# check "baseouterinnerouterbase" == inner()
# check "baseouterouterbase" == outer()
# check "basebase" == base()
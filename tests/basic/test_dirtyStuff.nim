discard """
  joinable: false
"""
## This is stuff normally not done in a template engine
## but *we can*, since we evaluate to nim code, so we test (maybe its useful ;) )

import ../../src/nimja

block:
  proc test(): string = compileTemplateStr("{% proc foo(): string = return \"FOO!!\" %}{{foo()}}")
  doAssert test() == "FOO!!"

block:
  proc test(): string = compileTemplateStr("""
{%
var ii = 123
proc foo(): string = return "FOO!!"
result.add foo() & $ii
%}""")
  doAssert test() == "FOO!!123"

block:
  proc test(): string = compileTemplateStr("""SOME STUFF{% result = "" %}""")
  doAssert test() == ""


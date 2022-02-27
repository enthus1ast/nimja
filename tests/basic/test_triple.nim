discard """
  joinable: false
"""
import nimja, os
import strutils

block:
  proc foo(): string =
    compileTemplateFile(getScriptDir() / "triple.html")
  doAssert foo() == "FOO\10BAA\13\10" # TODO why newline at the end?

## TODO should escape triple quotes possible?
# block:
#   proc foo(): string =
#     compileTemplateFile(getScriptDir() / "triple2.html")
#   echo repr foo()
#   # doAssert foo() == "FOO\10\"\"\"BAA\13\10"


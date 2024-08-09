discard """
  joinable: false
"""
import ../../src/nimja
import os
import strutils

block:
  proc foo(): string =
    compileTemplateFile(getScriptDir() / "triple.nimja")
  doAssert foo() == "FOO\10BAA\13\10" # TODO why newline at the end?

## TODO should escape triple quotes possible?
# block:
#   proc foo(): string =
#     compileTemplateFile(getScriptDir() / "triple2.nimja")
#   echo repr foo()
#   # doAssert foo() == "FOO\10\"\"\"BAA\13\10"


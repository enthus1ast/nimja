discard """
  joinable: false
  errormsg: '''circular extends detected'''
  file: "bug_circular.nimja"
"""
import ../../src/nimja
import os

# A template extending itself used to recurse until the VM max call
# depth was reached; it should now be detected and reported.
proc test(): string =
  compileTemplateFile("bug_circular.nimja", baseDir = getScriptDir())

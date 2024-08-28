discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

test "import proc module in master":
  proc tchild(): string =
    compileTemplateFile("procmodule/importInMaster/template_child.nimja", baseDir = getScriptDir())
  check "foo" == tchild()

test "import proc module in child":
  proc tchild(): string =
    compileTemplateFile("procmodule/importInChild/template_child.nimja", baseDir = getScriptDir())
  check "foo" == tchild()



discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

import theModule/theModule

proc baseRender(): string =
  return moduleRender() 

proc baseRender2(): string =
  compileTemplateStr("{{moduleRender()}}")

proc baseRender3(): string =
  # compileTemplateFile()
  tmpls("{{moduleRender()}}")

suite "import module":
  test "compileTemplateFile (from module)":
    check "FROM THE FILE" == baseRender().strip() # why need strip?

  test "compileTemplateFile (from ctf -> module)":
    check "FROM THE FILE" == baseRender2().strip() # why need strip?

  test "tmpls (from ctf -> module)":
    check "FROM THE FILE" == baseRender3().strip() # why need strip?

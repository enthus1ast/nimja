discard """
  joinable: false
"""
include ../../src/nimja/parser
import sequtils, strutils, unittest


iterator foo(): string =
  var ii = 123
  compileTemplateStr("foo{{ii}}baa", iter = true)

proc baa(): string =
  var ii = 123
  compileTemplateStr("foo{{ii}}baa", iter = false)

check baa() == "foo123baa"
check toSeq(foo()).join("") == "foo123baa"
check baa() == "foo123baa"

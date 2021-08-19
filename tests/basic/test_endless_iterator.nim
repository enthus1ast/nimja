discard """
  joinable: false
"""
include ../../src/nimja/parser
import sequtils, strutils, unittest


iterator foo(): string =
  var ii = 123
  compileTemplateStr("{%while true%}foo{{ii}}baa<br>\n{%endwhile%}", iter = true)

var idx = 0
var outp = ""
for elem in foo():
  outp &= elem
  if idx == 15: break
  idx.inc

check outp == "foo123baa<br>\n".repeat(5)

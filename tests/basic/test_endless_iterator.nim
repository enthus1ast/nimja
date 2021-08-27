discard """
  joinable: false
"""
include ../../src/nimja/parser
import sequtils, strutils, unittest


iterator foo(): string =
  compileTemplateStr("{%while 1==1%}foo{%endwhile%}", iter = true)

var idx = 0
var outp = ""
for elem in foo():
  outp &= elem
  if idx == 5: break
  idx.inc

check outp == "foo".repeat(6)
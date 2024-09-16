discard """
  joinable: false
  errormsg: '''not all cases are covered; missing: {ccc, ddd}'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

type Foo = enum
  aaa, bbb, ccc, ddd
var foo: Foo = aaa
discard tmplf("case" / "case3.nimja", baseDir = getScriptDir(), context = {ee: ddd})

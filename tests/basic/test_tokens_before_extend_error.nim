discard """
  joinable: false
  errormsg: '''unhandled exception: Invalid token(s) before {%extend%}: @[(kind: NStr, strBody: " "), (kind: NEval, evalBody: "invalid"), (kind: NStr, strBody: "  "), (kind: NExtends, extendsPath: "../templates/blockMaster.html")] [ValueError]'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

const foo = compile(""" {% invalid %}  {%extends "../templates/blockMaster.html"%}""")
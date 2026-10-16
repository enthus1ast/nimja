discard """
  joinable: false
  errormsg: '''unhandled exception: Invalid token(s) before {%extend%}'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

const foo = compile(""" {% invalid %}  {%extends "../templates/blockMaster.nimja"%}""")
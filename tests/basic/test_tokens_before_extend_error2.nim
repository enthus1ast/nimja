discard """
  joinable: false
  errormsg: '''unhandled exception: only one extend is allowed! [ValueError]'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

const foo = compile("""{%extends "../templates/blockMaster.html"%}{%extends "../templates/blockMaster.html"%}""")
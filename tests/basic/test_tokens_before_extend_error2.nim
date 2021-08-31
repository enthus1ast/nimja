discard """
  joinable: false
  errormsg: '''unhandled exception: found multiple extends'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

const foo = compile("""{%extends "../templates/blockMaster.html"%}{%extends "../templates/blockMaster.html"%}""")
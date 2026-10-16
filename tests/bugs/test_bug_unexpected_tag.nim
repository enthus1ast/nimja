discard """
  joinable: false
  errormsg: '''Unexpected template tag (unbalanced or misplaced): FsElse'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

# A stray {% else %} used to raise an internal "[SS] NOT IMPL" error with
# the raw FsNode representation; it should name the offending tag instead.
const foo = compile("A{% else %}B")

discard """
  joinable: false
  errormsg: '''unhandled exception: uneven when's'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

# missing {% endwhen %}
const foo = compile("{% when true %}B")

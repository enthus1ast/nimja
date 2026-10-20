discard """
  joinable: false
  errormsg: '''unhandled exception: `when` is missing `endwhen`'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

# missing {% endwhen %}
const foo = compile("{% when true %}B")

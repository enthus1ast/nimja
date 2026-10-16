discard """
  joinable: false
  errormsg: '''unhandled exception: uneven block's'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

# missing {% endblock %}
const foo = compile("{% block content %}B")

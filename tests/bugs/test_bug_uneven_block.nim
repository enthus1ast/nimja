discard """
  joinable: false
  errormsg: '''unhandled exception: `block` is missing `endblock`'''
  file: "parser.nim"
"""
include ../../src/nimja/parser

# missing {% endblock %}
const foo = compile("{% block content %}B")

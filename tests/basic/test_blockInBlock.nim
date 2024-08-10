discard """
  joinable: false
"""
import ../../src/nimja/parser
import unittest

test "one block":
  block:
    proc child1(): string =
      compileTemplateStr("{% extends test_block_in_block/master.nimja %}{%block inner%}newinner{%endblock%}", baseDir = getScriptDir())
    check child1() == "outer1newinnerouter2"

test "two blocks":
  block:
    proc child2(): string =
      compileTemplateStr("{% extends test_block_in_block/master.nimja %}{%block outer%}newouter{%endblock%}", baseDir = getScriptDir())
    check child2() == "newouter"

discard """
  joinable: false
"""
import ../../src/nimja/parser
import unittest

test "one block":
  block:
    proc child1(): string =
      compileTemplateStr("{% extends test_block_in_block/master.nwt %}{%block inner%}newinner{%endblock%}")
    check child1() == "outer1newinnerouter2"

test "two blocks":
  block:
    proc child2(): string =
      compileTemplateStr("{% extends test_block_in_block/master.nwt %}{%block outer%}newouter{%endblock%}")
    check child2() == "newouter"
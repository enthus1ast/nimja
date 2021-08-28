include ../../src/nimja/parser
import ../../src/nimja/lexer
import sequtils
import unittest

let tokens = toSeq(lex("{%block outer%}outer1{%block inner%}inner{% endblock inner%}outer2{% endblock outer%}"))
# echo tokens

let fs = parseFirstStep(tokens)
# echo fs

var pos = 0
let ss = parseSecondStep(fs, pos)
echo ss

test "one block":
  block:
    proc child1(): string =
      compileTemplateStr("{% extends test_block_in_block/master.nwt %}{%block inner%}newinner{%endblock%}")
    echo child1()
    check child1() == "outer1newinnerouter2"

test "two blocks":
  block:
    proc child2(): string =
      compileTemplateStr("{% extends test_block_in_block/master.nwt %}{%block outer%}newouter{%endblock%}")
    echo child2()
    check child2() == "newouter"
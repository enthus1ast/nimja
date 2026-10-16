discard """
import sequtils
import unittest
import ../../src/nimja/lexer

suite "lexer bugs (L-1: triple-quoted strings swallowing }}:)",
       "bounds check in lexInnerStrTripple":

  test "triple-quoted string with content ending in quote is not mangled":
    check toSeq(lex("""{{"a"}}""")) == @[newToken(NwtVariable, "\"a\"")]

  test "triple-quoted string with foo content is not mangled":
    check toSeq(lex("""{{"foo"}}""")) == @[newToken(NwtVariable, "\"foo\"")]

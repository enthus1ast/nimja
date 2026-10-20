discard """
  joinable: false
"""
import sequtils
import unittest
import ../../src/nimja/lexer

proc newToken(kind: NwtTokenKind, value: string, line = 0): Token =
  return Token(kind: kind, value: value, line: line)

proc `==`(a, b: Token): bool =
  ## compare token content; line/col are covered by the lexer's own tests
  a.kind == b.kind and a.value == b.value

suite "lexer string handling bugs":
  test "escaped quote inside a single quoted string is kept intact":
    # compiled template body: {{ "a\"b" }}
    check toSeq(lex("""{{ "a\"b" }}""")) == @[newToken(NwtVariable, "\"a\\\"b\"")]

  test "backslash escape inside eval string is kept intact":
    # compiled template body: {% let re = "\\.(jpg|png)" %}
    check toSeq(lex("""{% let re = "\\.(jpg|png)" %}""")) ==
      @[newToken(NwtEval, "let re = \"\\\\.(jpg|png)\"")]

  test "}} inside a quoted string is not treated as block end":
    check toSeq(lex("""{{ "}}" }}""")) == @[newToken(NwtVariable, "\"}}\"")]

  test "unterminated triple quoted string raises a clear error":
    expect ValueError:
      discard toSeq(lex("{{\"\"\"}}"))

  test "terminated triple quoted string still works":
    check toSeq(lex("{{\"\"\"foo\"\"\"}}")) == @[newToken(NwtVariable, "\"\"\"foo\"\"\"")]

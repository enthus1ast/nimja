discard """
joinable: false
"""
import sequtils
import ../../src/nimja/lexer
import unittest

proc newToken(kind: NwtTokenKind, value: string): Token =
  return Token(kind: kind, value: value)


suite "tokenizer":
  test "NwtString":
    check toSeq(lex("hello")) == @[newToken(NwtString, "hello")]
    check toSeq(lex("body { background-color: blue; }")) == @[
      newToken(NwtString, "body { background-color: blue; }")
    ]
    check toSeq(lex("foo {baa}")) == @[newToken(NwtString, "foo {baa}")]

  test "NwtVariable":
    check toSeq(lex("{{var}}")) == @[newToken(NwtVariable, "var")]
    check toSeq(lex("{{ var }}")) == @[newToken(NwtVariable, "var")]
    check toSeq(lex("{{var}}{{var}}")) == @[
      newToken(NwtVariable, "var"),
      newToken(NwtVariable, "var")
    ]
    check toSeq(lex("{{\"a str\"}}")) == @[newToken(NwtVariable, "\"a str\"")]

  test "NwtComment":
    check toSeq(lex("{#i am a comment#}")) == @[
      newToken(NwtComment, "i am a comment")
    ]
    check toSeq(lex("{# i am a comment #}")) == @[
      newToken(NwtComment, "i am a comment")
    ]

  test "NwtEval":
    check toSeq(lex("{%raw%}")) == @[newToken(NwtEval, "raw")]
    check toSeq(lex("{% raw %}")) == @[newToken(NwtEval, "raw")]
    check toSeq(lex("{% for each in foo %}")) == @[
      newToken(NwtEval, "for each in foo")]



  test "NwtString broken":
    check toSeq(lex("{ nope }")) == @[newToken(NwtString, "{ nope }")]
    check toSeq(lex("{nope}")) == @[newToken(NwtString, "{nope}")]
    check toSeq(lex("{nope")) == @[newToken(NwtString, "{nope")]
    check toSeq(lex("nope}")) == @[newToken(NwtString, "nope}")]

  test "NwtString broken { / }":
    check toSeq(lex("{")) == @[newToken(NwtString, "{")]
    check toSeq(lex("}")) == @[newToken(NwtString, "}")]

  test "NwtVariable str with lonely/broken \"{{\"":
    check toSeq(lex("""{{ "{{" }}""")) == @[newToken(NwtVariable, "\"{{\"")] # <-- fails

  test "NwtVariable str with lonely/broken \"}}\"":
    check toSeq(lex("""{{ "}}" }}""")) == @[newToken(NwtVariable, "\"}}\"")]

  test "NwtVariable str with lonely/broken \"{%\"":
      check toSeq(lex("""{{ "{%" }}""")) == @[newToken(NwtVariable, "\"{%\"")]

  test "NwtVariable str with lonely/broken \"%}\"":
      check toSeq(lex("""{{ "%}" }}""")) == @[newToken(NwtVariable, "\"%}\"")]

  test "NwtVariable str with lonely/broken \"{#\"":
      check toSeq(lex("""{{ "{#" }}""")) == @[newToken(NwtVariable, "\"{#\"")]

  test "NwtVariable str with lonely/broken \"#}\"":
      check toSeq(lex("""{{ "#}" }}""")) == @[newToken(NwtVariable, "\"#}\"")]

  test "NwtBlock":
    check toSeq(lex("""{%block 'first'%}{%blockend%}""")) == @[
      newToken(NwtEval, "block 'first'"),
      newToken(NwtEval, "blockend")
    ]

  test "NwtBlock inner":
    check toSeq(lex("""{%block 'first'%}{%block inner%}{%blockend%}{%blockend%}""")) == @[
      newToken(NwtEval, "block 'first'"),
      newToken(NwtEval, "block inner"),
      newToken(NwtEval, "blockend"),
      newToken(NwtEval, "blockend"),
    ]

  test "unsorted":
    assert toSeq(lex("foo {{baa}} {baa}")) == @[
      newToken(NwtString, "foo "),
      newToken(NwtVariable, "baa"),
      newToken(NwtString, " {baa}")
    ]

  # test "extractTemplateName":
  #   check extractTemplateName("""extends "foobaa.html" """) == "foobaa.html"
  #   check extractTemplateName("""extends "foobaa.html"""") == "foobaa.html"
  #   check extractTemplateName("""extends 'foobaa.html'""") == "foobaa.html"
  #   check extractTemplateName("""extends foobaa.html""") == "foobaa.html"
  #   check extractTemplateName("""extends foobaa.html""") == "foobaa.html"
  #   check extractTemplateName(toSeq(lex("""{% extends "foobaa.html" %}"""))[0].value) == "foobaa.html"
  #   block:
  #     var tokens = toSeq(lex("""{% extends "foobaa.html" %}{% extends "goo.html" %} """))
  #     check extractTemplateName(tokens[0].value) == "foobaa.html"
  #     check extractTemplateName(tokens[1].value) == "goo.html"
  #   block:
  #     var tokens = toSeq(lex("""{% extends foobaa.html %}{% extends goo.html %}"""))
  #     check extractTemplateName(tokens[0].value) == "foobaa.html"
  #     check extractTemplateName(tokens[1].value) == "goo.html"
  #   block:
  #     var tokens = toSeq(lex("""{%extends "foobaa.html" %}{% extends 'goo.html' %}"""))
  #     check extractTemplateName(tokens[0].value) == "foobaa.html"
  #     check extractTemplateName(tokens[1].value) == "goo.html"
  #   block:
  #     var tokens = toSeq(lex("""{%extends foobaa.html%}"""))
  #     check extractTemplateName(tokens[0].value) == "foobaa.html"

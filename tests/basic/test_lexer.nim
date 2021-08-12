discard """
joinable: false
"""
import sequtils
import ../../src/nimja/nwtTokenizer
import unittest

suite "tokenizer":
  test "NwtString":
    check toSeq(nwtTokenize("hello")) == @[newToken(NwtString, "hello")]
    check toSeq(nwtTokenize("body { background-color: blue; }")) == @[
      newToken(NwtString, "body { background-color: blue; }")
    ]
    check toSeq(nwtTokenize("foo {baa}")) == @[newToken(NwtString, "foo {baa}")]

  test "NwtVariable":
    check toSeq(nwtTokenize("{{var}}")) == @[newToken(NwtVariable, "var")]
    check toSeq(nwtTokenize("{{ var }}")) == @[newToken(NwtVariable, "var")]
    check toSeq(nwtTokenize("{{var}}{{var}}")) == @[
      newToken(NwtVariable, "var"),
      newToken(NwtVariable, "var")
    ]
    check toSeq(nwtTokenize("{{\"a str\"}}")) == @[newToken(NwtVariable, "\"a str\"")]

  test "NwtComment":
    check toSeq(nwtTokenize("{#i am a comment#}")) == @[
      newToken(NwtComment, "i am a comment")
    ]
    check toSeq(nwtTokenize("{# i am a comment #}")) == @[
      newToken(NwtComment, "i am a comment")
    ]

  test "NwtEval":
    check toSeq(nwtTokenize("{%raw%}")) == @[newToken(NwtEval, "raw")]
    check toSeq(nwtTokenize("{% raw %}")) == @[newToken(NwtEval, "raw")]
    check toSeq(nwtTokenize("{% for each in foo %}")) == @[
      newToken(NwtEval, "for each in foo")]



  test "NwtString broken":
    check toSeq(nwtTokenize("{ nope }")) == @[newToken(NwtString, "{ nope }")]
    check toSeq(nwtTokenize("{nope}")) == @[newToken(NwtString, "{nope}")]
    check toSeq(nwtTokenize("{nope")) == @[newToken(NwtString, "{nope")]
    check toSeq(nwtTokenize("nope}")) == @[newToken(NwtString, "nope}")]

  test "NwtString broken { / }":
    check toSeq(nwtTokenize("{")) == @[newToken(NwtString, "{")]
    check toSeq(nwtTokenize("}")) == @[newToken(NwtString, "}")]

  test "NwtVariable str with lonely/broken \"{{\"":
    check toSeq(nwtTokenize("""{{ "{{" }}""")) == @[newToken(NwtVariable, "\"}}\"")] # <-- fails

  test "NwtVariable str with lonely/broken \"}}\"":
    check toSeq(nwtTokenize("""{{ "}}" }}""")) == @[newToken(NwtVariable, "\"{{\"")]

  test "NwtVariable str with lonely/broken \"{%\"":
      check toSeq(nwtTokenize("""{{ "{%" }}""")) == @[newToken(NwtVariable, "\"{%\"")]

  test "NwtVariable str with lonely/broken \"%}\"":
      check toSeq(nwtTokenize("""{{ "%}" }}""")) == @[newToken(NwtVariable, "\"%}\"")]

  test "NwtVariable str with lonely/broken \"{#\"":
      check toSeq(nwtTokenize("""{{ "{#" }}""")) == @[newToken(NwtVariable, "\"{#\"")]

  test "NwtVariable str with lonely/broken \"#}\"":
      check toSeq(nwtTokenize("""{{ "#}" }}""")) == @[newToken(NwtVariable, "\"#}\"")]

  test "NwtBlock":
    check toSeq(nwtTokenize("""{%block 'first'%}{%blockend%}""")) == @[
      newToken(NwtEval, "block 'first'"),
      newToken(NwtEval, "blockend")
    ]

  test "NwtBlock inner":
    check toSeq(nwtTokenize("""{%block 'first'%}{%block inner%}{%blockend%}{%blockend%}""")) == @[
      newToken(NwtEval, "block 'first'"),
      newToken(NwtEval, "block inner"),
      newToken(NwtEval, "blockend"),
      newToken(NwtEval, "blockend"),
    ]

  test "unsorted":
    assert toSeq(nwtTokenize("foo {{baa}} {baa}")) == @[
      newToken(NwtString, "foo "),
      newToken(NwtVariable, "baa"),
      newToken(NwtString, " {baa}")
    ]

  test "extractTemplateName":
    check extractTemplateName("""extends "foobaa.html" """) == "foobaa.html"
    check extractTemplateName("""extends "foobaa.html"""") == "foobaa.html"
    check extractTemplateName("""extends 'foobaa.html'""") == "foobaa.html"
    check extractTemplateName("""extends foobaa.html""") == "foobaa.html"
    check extractTemplateName("""extends foobaa.html""") == "foobaa.html"
    check extractTemplateName(toSeq(nwtTokenize("""{% extends "foobaa.html" %}"""))[0].value) == "foobaa.html"
    block:
      var tokens = toSeq(nwtTokenize("""{% extends "foobaa.html" %}{% extends "goo.html" %} """))
      check extractTemplateName(tokens[0].value) == "foobaa.html"
      check extractTemplateName(tokens[1].value) == "goo.html"
    block:
      var tokens = toSeq(nwtTokenize("""{% extends foobaa.html %}{% extends goo.html %}"""))
      check extractTemplateName(tokens[0].value) == "foobaa.html"
      check extractTemplateName(tokens[1].value) == "goo.html"
    block:
      var tokens = toSeq(nwtTokenize("""{%extends "foobaa.html" %}{% extends 'goo.html' %}"""))
      check extractTemplateName(tokens[0].value) == "foobaa.html"
      check extractTemplateName(tokens[1].value) == "goo.html"
    block:
      var tokens = toSeq(nwtTokenize("""{%extends foobaa.html%}"""))
      check extractTemplateName(tokens[0].value) == "foobaa.html"

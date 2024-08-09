discard """
joinable: false
"""
import sequtils
import ../../src/nimja/lexer
import unittest

proc newToken(kind: NwtTokenKind, value: string, line = 0): Token =
  return Token(kind: kind, value: value, line: line)

# echo "#####"
# # for elem in lex("{"):
# #   echo elem
# echo toSeq(lex("foo\n{{baa}}\n\n\n{{baa}}baz"))

# echo "#####"

# quit()

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

  test "NwtString broken {":
    check toSeq(lex("{")) == @[newToken(NwtString, "{")]
  test "NwtString broken }":
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
    check toSeq(lex("foo {{baa}} {baa}")) == @[
      newToken(NwtString, "foo "),
      newToken(NwtVariable, "baa"),
      newToken(NwtString, " {baa}")
    ]

  ## TODO a token.line should always point to the _BEGINNING_ of the token right?
  # test "lines":
  #   check toSeq(lex("foo\n{{baa}}\n{baa}")) == @[
  #     newToken(NwtString, "foo\n", 0),
  #     newToken(NwtVariable, "baa", 1),
  #     newToken(NwtString, "\n{baa}", 1), # this s
  #   ]
    # echo toSeq(lex("foo\n{{ba\na}}\n{baa}"))
    # echo toSeq(lex("foo\n{{baa}}\n\n\n{baa}"))
    # check toSeq(lex("foo\n{{baa}}\n{baa}")) == @[
    #   newToken(NwtString, "foo "),
    #   newToken(NwtVariable, "baa"),
    #   newToken(NwtString, " {baa}")
    # ]


  test "#16":
    let tokens = toSeq(lex("""{#
    {% var idx = 0 %}
    {%while true%}
      <div class="row m-4">
        {% for title in @["foo", "baa", "baz", "asdf", "afsdfasdfkl" , "asdfasdf"] %}
          <div class="col-4">
            <div class="card" style="width: 18rem;">
              <img src="..." class="card-img-top" alt="...">
              <div class="card-body">
                <h5 class="card-title">{{title}}</h5>
                <p class="card-text">Some quick example text to build on the card title and make up the bulk of the card's content.</p>
                <a href="#" class="btn btn-primary">Go somewhere</a>
              </div>
            </div>
          </div>
        {% endfor %}
      </div>
      {% idx.inc %}
      {% if idx > 2 %}{% break %}{% endif %}
    {% endwhile %}
    #}"""))

    check tokens.len == 1
    check tokens[0].kind == NwtComment


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

discard """
  joinable: false
"""
# see  #12

include ../../src/nimja/parser
import sequtils, unittest

block:
  var beforeCondens = @[
    NwtNode(kind: NStr, strBody: "foo"),
    NwtNode(kind: NComment, commentBody: "comment"),
    NwtNode(kind: NStr, strBody: "foo"),
    NwtNode(kind: NComment, commentBody: "comment"),
    NwtNode(kind: NStr, strBody: "foo")
  ]

  var beforeCondens2 = @[
    NwtNode(kind: NStr, strBody: "foo"),
    NwtNode(kind: NStr, strBody: "foo"),
    NwtNode(kind: NStr, strBody: "foo")
  ]

  var afterCondense = @[
    NwtNode(kind: NStr, strBody: "foofoofoo")
  ]

  # Cannot compare directly because of:
  # Error: parallel 'fields' iterator does not work for 'case' objects
  check toSeq(condenseStrings(beforeCondens))[0].kind == afterCondense[0].kind
  check toSeq(condenseStrings(beforeCondens))[0].strBody == afterCondense[0].strBody

  check toSeq(condenseStrings(beforeCondens2))[0].kind == afterCondense[0].kind
  check toSeq(condenseStrings(beforeCondens2))[0].strBody == afterCondense[0].strBody

  const val = toSeq(compile("""foo{#comment#}foo{#comment#}foo""").condenseStrings)
  check val[0].kind == afterCondense[0].kind
  check val[0].strBody == afterCondense[0].strBody

block:
  var beforeCondens = @[
    NwtNode(kind: NStr, strBody: "foo"),
    NwtNode(kind: NStr, strBody: "foo"),
    NwtNode(kind: NVariable, variableBody: "varBody"),
    NwtNode(kind: NStr, strBody: "foo"),
    NwtNode(kind: NStr, strBody: "foo")
  ]
  var afterCondense = @[
    NwtNode(kind: NStr, strBody: "foofoo"),
    NwtNode(kind: NVariable, variableBody: "varBody"),
    NwtNode(kind: NStr, strBody: "foofoo")
  ]

  for idx in 0 .. 2:
    check toSeq(condenseStrings(beforeCondens))[idx].kind == afterCondense[idx].kind

    case toSeq(condenseStrings(beforeCondens))[idx].kind
    of NVariable:
      check toSeq(condenseStrings(beforeCondens))[idx].variableBody == afterCondense[idx].variableBody
    of NStr:
      check toSeq(condenseStrings(beforeCondens))[idx].strBody == afterCondense[idx].strBody
    else:
      discard

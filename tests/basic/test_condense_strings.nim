discard """
  joinable: false
"""
# see  #12

include ../../src/nimja/parser
import sequtils, unittest

when defined(noCondenseStrings):
  echo "noCondenseStrings is set, this test is invalid. Quitting"
  quit()

block:
  var beforeCondense = @[
    FsNode(kind: FsStr, value: "foo"),
    FsNode(kind: FsStr, value: "foo"),
    FsNode(kind: FsStr, value: "foo")
  ]

  var afterCondense = @[
    FsNode(kind: FsStr, value: "foofoofoo")
  ]

  check condenseStrings(beforeCondense) == afterCondense


block:
  var beforeCondense = @[
    FsNode(kind: FsStr, value: "foo"),
    FsNode(kind: FsStr, value: "foo"),
    FsNode(kind: FsVariable, value: "varBody"),
    FsNode(kind: FsStr, value: "foo"),
    FsNode(kind: FsStr, value: "foo")
  ]
  var afterCondense = @[
    FsNode(kind: FsStr, value: "foofoo"),
    FsNode(kind: FsVariable, value: "varBody"),
    FsNode(kind: FsStr, value: "foofoo")
  ]

  check condenseStrings(beforeCondense) == afterCondense


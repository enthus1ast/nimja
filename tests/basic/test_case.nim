discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import os

# import macros
# dumpAstGen:
#   case "FOO" & "BAA"
#   of "foo":
#     discard
#   of "baa":
#     discard
#   else:
#     discard

# # nnkStmtList.newTree(
# #   nnkCaseStmt.newTree(
# #     newIdentNode("str"),
# #     nnkOfBranch.newTree(
# #       newLit("foo"),
# #       nnkStmtList.newTree(
# #         nnkDiscardStmt.newTree(
# #           newEmptyNode()
# #         )
# #       )
# #     ),
# #     nnkOfBranch.newTree(
# #       newLit("baa"),
# #       nnkStmtList.newTree(
# #         nnkDiscardStmt.newTree(
# #           newEmptyNode()
# #         )
# #       )
# #     ),
# #     nnkElse.newTree(
# #       nnkStmtList.newTree(
# #         nnkDiscardStmt.newTree(
# #           newEmptyNode()
# #         )
# #       )
# #     )
# #   )
# # )


suite "case":
  test "basic test":
    var str = "foo"
    check "foo" == tmplf(getScriptDir() / "case.nimja")

    str = "baa"
    check "baa" == tmplf(getScriptDir() / "case.nimja")

    str = "baz"
    check "baz" == tmplf(getScriptDir() / "case.nimja")

    str = "asdf"
    check "nothing" == tmplf(getScriptDir() / "case.nimja")

  test "complex test":
    check "AB" == tmpls("""{%- case "a" & "b" -%}{%- of "ab" -%}AB{%endcase%}""")
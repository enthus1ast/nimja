discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import os

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
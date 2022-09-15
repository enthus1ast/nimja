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

  test "complex test 2":
    type Foo = enum
      aaa, bbb, ccc, ddd
    var foo: Foo = aaa
    var isNothing: bool
    check "AAA" == tmplf(getScriptDir() / "case2.nimja", {ee: foo})
    check "BBB" == tmplf(getScriptDir() / "case2.nimja", {ee: Foo.bbb})
    check "CCC" == tmplf(getScriptDir() / "case2.nimja", {ee: ccc})

    isNothing = true
    check "nothing" == tmplf(getScriptDir() / "case2.nimja", {ee: ddd})

    isNothing = false
    check "something" == tmplf(getScriptDir() / "case2.nimja", {ee: ddd})



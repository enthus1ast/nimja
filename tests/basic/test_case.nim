discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import os

suite "case":
  test "basic test":
    var str = "foo"
    check "foo" == tmplf("case" / "case.nimja", baseDir = getScriptDir())

    str = "baa"
    check "baa" == tmplf(getScriptDir() / "case" / "case.nimja") # getScriptDir works in THAT case!

    str = "baz"
    check "baz" == tmplf(getScriptDir() / "case" / "case.nimja")

    str = "asdf"
    check "nothing" == tmplf(getScriptDir() / "case" / "case.nimja")

  test "complex test":
    check "AB" == tmpls("""{%- case "a" & "b" -%}{%- of "ab" -%}AB{%endcase%}""")

  test "complex test 2":
    type Foo = enum
      aaa, bbb, ccc, ddd
    var foo: Foo = aaa
    var isNothing: bool
    check "AAA" == tmplf("case" / "case2.nimja", baseDir = getScriptDir(), context = {ee: foo})
    check "BBB" == tmplf("case" / "case2.nimja", baseDir = getScriptDir(), context = {ee: Foo.bbb})
    check "CCC" == tmplf("case" / "case2.nimja", baseDir = getScriptDir(), context = {ee: ccc})

    isNothing = true
    check "nothing" == tmplf("case" / "case2.nimja", baseDir = getScriptDir(), context = {ee: ddd})

    isNothing = false
    check "something" == tmplf("case" / "case2.nimja", baseDir = getScriptDir(), context = {ee: ddd})



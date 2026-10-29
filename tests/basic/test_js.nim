# Test that nimja compiles and basic functionality works when targeting JS.
# This file is compiled with `nim js`. No js/dom dependency — just string
# operations and the template engine itself.

discard """
  joinable: false
"""
import ../../src/nimja
import unittest

block:
  proc testBasic(name: string): string =
    compileTemplateStr("Hello {{name}}!")

  test "basic variable":
    check testBasic("Nim") == "Hello Nim!"

block:
  proc testLoop(items: openArray[string]): string =
    compileTemplateStr("{% for (loop, item) in items.loop() %}{{item}}{% endfor %}")

  test "loop iteration":
    check testLoop(@["a", "b", "c"]) == "abc"

block:
  proc testIf(flag: bool): string =
    compileTemplateStr("{% if flag %}yes{% else %}no{% endif %}")

  test "if/else true":
    check testIf(true) == "yes"

  test "if/else false":
    check testIf(false) == "no"

block:
  proc testIfNested(a: bool, b: bool): string =
    compileTemplateStr("{% if a %}{% if b %}ab{% endif %}{% endif %}")

  test "nested if both true":
    check testIfNested(true, true) == "ab"

  test "nested if a false":
    check testIfNested(false, true) == ""

block:
  proc testHtmlEscape(x: string): string =
    compileTemplateStr("{{x | e}}")

  test "html escape":
    check testHtmlEscape("<b>bold</b>") == "&lt;b&gt;bold&lt;/b&gt;"

block:
  proc testVarInt(n: int): string =
    compileTemplateStr("{{n}}")

  test "integer variable":
    check testVarInt(42) == "42"

block:
  proc testVarFloat(f: float): string =
    compileTemplateStr("{{f}}")

  test "float variable":
    check testVarFloat(3.14) == "3.14"

block:
  proc testComments(): string =
    compileTemplateStr("before{# comment #}after")

  test "comments stripped":
    check testComments() == "beforeafter"

block:
  proc testEval(): string =
    compileTemplateStr("{% var x = 42 %}{{x}}")

  test "var eval":
    check testEval() == "42"

block:
  proc testConcat(): string =
    compileTemplateStr("{{\"a\" ~ \"b\" ~ \"c\"}}")

  test "string concat":
    check testConcat() == "abc"

block:
  proc testWhile(): string =
    compileTemplateStr("{% var i = 0 %}{% while i < 3 %}{{i}}{% inc i %}{% endwhile %}")

  test "while loop":
    check testWhile() == "012"

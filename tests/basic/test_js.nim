# Test that nimja compiles and basic functionality works when targeting JS.
# This file is compiled with `nim js`. No js/dom dependency — just string
# operations and the template engine itself.

discard """
  joinable: false
"""
import ../../src/nimja

proc testBasic(name: string): string =
  compileTemplateStr("Hello {{name}}!")

proc testLoop(items: openArray[string]): string =
  compileTemplateStr("{% for (loop, item) in items.loop() %}{{item}}{% endfor %}")

proc testIf(flag: bool): string =
  compileTemplateStr("{% if flag %}yes{% else %}no{% endif %}")

proc testIfNested(a: bool, b: bool): string =
  compileTemplateStr("{% if a %}{% if b %}ab{% endif %}{% endif %}")

proc testHtmlEscape(x: string): string =
  compileTemplateStr("{{x | e}}")

proc testVarInt(n: int): string =
  compileTemplateStr("{{n}}")

proc testVarFloat(f: float): string =
  compileTemplateStr("{{f}}")

proc testComments(): string =
  compileTemplateStr("before{# comment #}after")

proc testEval(): string =
  compileTemplateStr("{% var x = 42 %}{{x}}")

proc testConcat(): string =
  compileTemplateStr("{{\"a\" ~ \"b\" ~ \"c\"}}")

proc testWhile(): string =
  compileTemplateStr("{% var i = 0 %}{% while i < 3 %}{{i}}{% inc i %}{% endwhile %}")

doAssert testBasic("Nim") == "Hello Nim!"
doAssert testLoop(@["a", "b", "c"]) == "abc"
doAssert testIf(true) == "yes"
doAssert testIf(false) == "no"
doAssert testIfNested(true, true) == "ab"
doAssert testIfNested(false, true) == ""
doAssert testHtmlEscape("<b>bold</b>") == "&lt;b&gt;bold&lt;/b&gt;"
doAssert testVarInt(42) == "42"
doAssert testVarFloat(3.14) == "3.14"
doAssert testComments() == "beforeafter"
doAssert testEval() == "42"
doAssert testConcat() == "abc"
doAssert testWhile() == "012"

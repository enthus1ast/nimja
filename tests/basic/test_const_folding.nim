discard """
  joinable: false
"""
import ../../src/nimja
import unittest

const
  name = "World"
  number = 42
  pi = 3.14

var calls = 0
proc sideEffect(): string =
  calls.inc
  "x"

suite "const folding (#53)":
  test "consts are folded into the surrounding strings":
    proc test(): string =
      compileTemplateStr("Hello {{ name }}, {{ number }}, {{ pi }}!")
    check test() == "Hello World, 42, 3.14!"

  test "runtime values take the non folded branch":
    proc test(x: string): string =
      compileTemplateStr("A {{ name }} B {{ x }} C")
    check test("dyn") == "A World B dyn C"

  test "consts fold with escaping":
    proc test(): string =
      compileTemplateStr("<b>{{ name }}</b>", escapeWith = htmlEscape)
    check test() == "<b>World</b>"

  test "consts fold in iterators":
    iterator it(): string =
      compileTemplateStr("A {{ name }} B", iter = true)
    var s = ""
    for x in it(): s.add x
    check s == "A World B"

  test "string literals still work (not folded)":
    proc test(): string =
      compileTemplateStr("A {{ \"lit\" }} B")
    check test() == "A lit B"

  test "proc calls are not folded (no compile time side effect)":
    calls = 0
    proc test(): string =
      compileTemplateStr("A {{ sideEffect() }} B")
    check test() == "A x B"
    check calls == 1

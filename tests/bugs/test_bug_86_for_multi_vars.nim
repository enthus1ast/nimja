discard """
  joinable: false
"""
import ../../src/nimja
import unittest

type
  Model = object
    foo: string
    baa: string

suite "for loop with multiple variables (#86)":
  test "fieldPairs keeps the iterator expression":
    ## `astFor` used to overwrite `nnkForStmt[2]`, which is the iterator
    ## expression as soon as the loop has more than one variable, so the
    ## `fieldPairs(...)` call disappeared from the generated code.
    # note: `fieldPairs` needs `for name, val in ...`, not `for (name, val) in ...`
    proc render(m: Model): string =
      compileTemplateStr("{% for name, val in fieldPairs(m) %}{{name}}={{val}};{% endfor %}")
    check render(Model(foo: "foo", baa: "baa")) == "foo=foo;baa=baa;"

  test "index/value pairs still destructure":
    proc render(items: seq[string]): string =
      compileTemplateStr("{% for (idx, val) in items.pairs() %}{{idx}}:{{val}};{% endfor %}")
    check render(@["a", "b"]) == "0:a;1:b;"

  test "three loop variables":
    proc render(a: seq[(string, int, bool)]): string =
      compileTemplateStr("{% for x, y, z in a.items %}{{x}}{{y}}{{z}};{% endfor %}")
    check render(@[("a", 1, true), ("b", 2, false)]) == "a1true;b2false;"

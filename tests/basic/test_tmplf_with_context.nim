discard """
  joinable: false
"""
import ../../src/nimja
import os

block:
  # test tmplf without context
  doAssert "foo" == tmplf("foo.nimja", baseDir = getScriptDir())

block:
  type
    Rax = object
      aa: string
      bb: float
  var rax = Rax(aa: "aaaa", bb: 13.37)
  var ii = 123
  doAssert "idx: 123, aa: aaaa, nodes: aaaa, 13.37" ==
    tmplf(
      "tmplf_with_context.nimja", baseDir = getScriptDir(),
      context = {
        idx: ii,
        aa: rax.aa,
        nodes: rax
      }
    )

block:
   type
     Rax = object
       aa: string
       bb: float
   var rax = Rax(aa: "aaaa", bb: 13.37)
   var foo = 123
   doAssert "13.37123" == tmpls("""{% if node.aa == "aaaa" %}{{node.bb}}{% endif %}{{baa}}""", baseDir = getScriptDir(), context = {node: rax, baa: foo})

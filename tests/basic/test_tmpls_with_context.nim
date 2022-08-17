discard """
  joinable: false
"""
import ../../src/nimja

block:
  type
    Rax = object
      aa: string
      bb: float
  var rax = Rax(aa: "aaaa", bb: 13.37)
  var ii = 123
  doAssert "idx: 123, aa: aaaa, nodes: aaaa, 13.37" ==
    tmpls("idx: {{idx}}, aa: {{aa}}, nodes: {{nodes.aa}}, {{nodes.bb}}",
      idx = ii,
      aa = rax.aa,
      nodes = rax
    )

block:
  type
    Rax = object
      aa: string
      bb: float
  var rax = Rax(aa: "aaaa", bb: 13.37)
  var foo = 123
  doAssert "13.37123" == tmpls("""{% if node.aa == "aaaa" %}{{node.bb}}{% endif %}{{baa}}""", node = rax, baa = foo)

block:
  # test if nimja templates can change stuff
  type
    Rax = object
      aa: string
      bb: float
  var rax = Rax(aa: "aaaa", bb: 13.37)
  var foo = 123
  doAssert "42.0" == tmpls("""{% if node.aa == "aaaa" %}{%node.bb = 42.0%}{% endif %}{{node.bb}}""", node = rax, baa = foo)
  doAssert 42.0 == rax.bb

block:
  # test if nimja templates can change stuff
  type
    Rax = object
      aa: string
      bb: float
  var rax = Rax(aa: "aaaa", bb: 13.37)
  var foo = 123
  proc render(): string =
    compileTemplateStr("foo", iter = false, varname = "result", node = rax)
  # doAssert "42.0" == tmpls("""{% if node.aa == "aaaa" %}{%node.bb = 42.0%}{% endif %}{{node.bb}}""", node = rax, baa = foo)
  # doAssert 42.0 == rax.bb


# block:
  # test if context can contain procs/funcs
  # proc foo(ii: int): string = return "foo" & $ii
  # doAssert "foo321" == tmpls("{{baa(321)}}", baa = foo(123))
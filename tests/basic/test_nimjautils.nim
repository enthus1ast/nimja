discard """
  joinable: false
"""
import nimja
import nimja/nimjautils
import sequtils

type
  Elem = object
    baa*: string

proc foo(elems: seq[Elem]): string =
  compileTemplateStr("""
{% for (loop, elem) in elems.loop() %}
  {{ elem.baa }}
{% endfor %}
  """)

let elems = @[Elem(baa: "one"), Elem(baa: "two")]
echo foo(elems)
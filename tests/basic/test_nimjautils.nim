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
{# {% for (zaa, elem) in elems.loop() %} #}
{% for (zaa, elem) in elems.loop() %}
  {{ elem.baa }}
{% endfor %}
  """)

let elems = @[Elem(baa: "one"), Elem(baa: "two")]
echo foo(elems)
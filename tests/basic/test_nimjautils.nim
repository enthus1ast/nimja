discard """
  joinable: false
"""
import nimja
import nimja/nimjautils
import strutils

type
  Elem = object
    baa*: string

proc foo(elems: seq[Elem]): string =
  compileTemplateStr("""
{% for (loop, row) in elems.loop() %}{{ loop.index0 }}{{ loop.index }}{{ loop.revindex0 }}{{ loop.revindex }}{{ loop.length }}{% if loop.first %}The first item{% endif %}{% if loop.last %}The last item{% endif %}{% if loop.previtem.isSome() %}{{ loop.previtem.get() }}{% endif %}{% if loop.nextitem.isSome() %}{{ loop.nextitem.get() }}{% endif %}<li class="{{ loop.cycle(@["odd", "even"]) }}">{{row}}</li>
{% endfor %}
  """)

let elems = @[Elem(baa: "one"), Elem(baa: "two")]
let renderLines = foo(elems).splitLines()
assert renderLines[0] == """01122The first item(baa: "two")<li class="odd">(baa: "one")</li>"""
assert renderLines[1] == """12012The last item(baa: "one")<li class="even">(baa: "two")</li>"""
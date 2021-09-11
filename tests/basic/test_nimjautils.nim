discard """
  joinable: false
"""
import ../../src/nimja
import ../../src/nimja/nimjautils
import strutils, os
import unittest


type
  Elem = object
    baa*: string

suite "nimjautils":
  test "loop":
    proc foo(elems: seq[Elem]): string =
      compileTemplateStr("""
    {% for (loop, row) in elems.loop() %}{{ loop.index0 }}{{ loop.index }}{{ loop.revindex0 }}{{ loop.revindex }}{{ loop.length }}{% if loop.first %}The first item{% endif %}{% if loop.last %}The last item{% endif %}{% if loop.previtem.isSome() %}{{ loop.previtem.get() }}{% endif %}{% if loop.nextitem.isSome() %}{{ loop.nextitem.get() }}{% endif %}<li class="{{ loop.cycle(@["odd", "even"]) }}">{{row}}</li>
    {% endfor %}
      """)

    let elems = @[Elem(baa: "one"), Elem(baa: "two")]
    let renderLines = foo(elems).splitLines()
    check renderLines[0].strip() == """01122The first item(baa: "two")<li class="odd">(baa: "one")</li>"""
    check renderLines[1].strip() == """12012The last item(baa: "one")<li class="even">(baa: "two")</li>"""

  test "tilde (~)":
    proc testTilde(name: auto): string =
      compileTemplateStr("""{{ "Hello " ~ name ~ "!" }}""")
    check testTilde("Nim") == "Hello Nim!"
    check testTilde(1) == "Hello 1!"
    check testTilde(0.123) == "Hello 0.123!"

  test "includeRaw":
    proc test(): string =
      let path = (getScriptDir()  / "basic" / "includeRawT.txt")
      compileTemplateStr("""pre{{ includeRaw(path) }}suf""")
    check test() == "pre123suf"

  test "truncate":
    check truncate("foo baa", 7) == "foo baa"
    check truncate("foo baa", 3) == "foo..."
    check truncate("foo baa", 4) == "foo..."
    let lorem = "Lorem ipsum, dolor sit amet consectetur adipisicing elit. Rem voluptates odio tempore voluptas beatae eum consequatur laudantium totam. Delectus fuga eveniet ab cum nulla aperiam iste ducimus odio fugit voluptas."
    check truncate(lorem, 65, false).len == 65 + "...".len
    check truncate(lorem, 65, true).len <= 65 + "...".len
    check truncate(lorem, 65, true) == "Lorem ipsum, dolor sit amet consectetur adipisicing elit. Rem..."

    proc test(lorem: string): string =
      compileTemplateStr("{{lorem.truncate(65)}}")
    check test(lorem) == "Lorem ipsum, dolor sit amet consectetur adipisicing elit. Rem..."



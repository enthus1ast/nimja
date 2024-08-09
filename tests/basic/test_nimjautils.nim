discard """
  joinable: false
"""
import ../../src/nimja
import ../../src/nimja/nimjautils
import strutils, os
import unittest
import sequtils


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
      let path = (getScriptDir() / "includeRawT.txt")
      compileTemplateStr("""pre{{ includeRaw(path) }}suf""")
    check test() == "pre123suf"

  test "includeRawStatic":
    proc test(): string =
      const path = (getScriptDir()  / "includeRawT.txt") # TODO why is there a difference to the test above??
      compileTemplateStr("""pre{{ includeRawStatic(path) }}suf""")
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

  test "nl2br":
    check "foo\nbaa".nl2br == "foo<br>\nbaa"
    check "foo\nbaa".nl2br(false) == "foo<br>baa"
    check "foo\n\n\nbaa".nl2br == "foo<br>\n<br>\n<br>\nbaa"

  test "spaceless":
    check "<foo>\n\nbaa  </foo>".spaceless == "<foo> baa </foo>"
    check "<foo tag='tag tag'>\n\nbaa  </foo>".spaceless == "<foo tag='tag tag'> baa </foo>"
    check "<foo>baa  baz</foo>".spaceless == "<foo>baa baz</foo>"

  test "short if `?`":
    proc foo(isDisabled: bool): string =
      compileTemplateStr("""{% ?isDisabled: "disabled" %}""")
    check "disabled" == foo(true)
    check "" == foo(false)

  test "short if `?`, iterator":
    iterator foo(isDisabled: bool): string =
      compileTemplateStr("""{% ?isDisabled: "disabled" %}""", iter = true)
    check "disabled" == toSeq(foo(true))[0]
    check toSeq(foo(false)).len() == 0

  test "filter `|`":
    proc foo(): string =
      compileTemplateStr("""{{"foo baa baz" | slugify()}}""")
    check foo() == "foo-baa-baz"

  test "filter `|` with params":
    proc fil(a: string, b: int, c: float): string =
      a.repeat(b) & $c
    proc foo(): string =
      compileTemplateStr("""{{"foo" | fil(3, 0.1337)}}""")
    check foo() == "foofoofoo0.1337"


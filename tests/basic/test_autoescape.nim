discard """
  joinable: false
"""
import ../../src/nimja
import unittest

const badvar = "A-<->-\"-&-'-b"
const escaped = "A-&lt;-&gt;-&quot;-&amp;-&#39;-b"

proc bracketEscape(s: string): string = "[" & s & "]"
proc starEscape[T](x: T): HTMLSafeStr = HTMLSafeStr("*" & $x & "*")

suite "autoescape":
  test "escapeWith = htmlEscape escapes variables":
    proc test(): string =
      let num = 2
      compileTemplateStr("{{ badvar }}{{ num }}", escapeWith = htmlEscape)
    check test() == escaped & "2"

  test "|safe prevents escaping":
    proc test(): string =
      compileTemplateStr("{{ badvar|safe }}", escapeWith = htmlEscape)
    check test() == badvar

  test "no escapeWith (default) does not escape":
    proc test(): string =
      compileTemplateStr("{{ badvar }}")
    check test() == badvar

  test "|e filter escapes explicitly":
    proc test(): string =
      compileTemplateStr("{{ badvar|e }}")
    check test() == escaped

  test "|htmlEscape filter escapes explicitly":
    proc test(): string =
      compileTemplateStr("{{ badvar|htmlEscape }}")
    check test() == escaped

  test "escaping is idempotent (|e with htmlEscape)":
    proc test(): string =
      compileTemplateStr("{{ badvar|e }}", escapeWith = htmlEscape)
    check test() == escaped

  test "non string values are escaped too":
    proc test(): string =
      compileTemplateStr("{{ 42 }}{{ true }}", escapeWith = htmlEscape)
    check test() == "42true"

  test "tmpls supports escapeWith":
    check tmpls("{{ \"a<b>\" }}", escapeWith = htmlEscape) == "a&lt;b&gt;"

  test "iterator body escapes":
    iterator it(): string =
      compileTemplateStr("{{ badvar }}", iter = true, escapeWith = htmlEscape)
    var s = ""
    for x in it(): s.add x
    check s == escaped

suite "custom escaping (escapeWith)":
  test "compileTemplateStr uses the given proc":
    proc test(): string =
      compileTemplateStr("{{ badvar }}", escapeWith = bracketEscape)
    check test() == "[" & badvar & "]"

  test "tmpls uses the given proc":
    check tmpls("{{ badvar }}", escapeWith = bracketEscape) == "[" & badvar & "]"

  test "custom proc may return HTMLSafeStr":
    proc test(): string =
      compileTemplateStr("{{ 42 }}", escapeWith = starEscape)
    check test() == "*42*"

  test "iterator body uses the given proc":
    iterator it(): string =
      compileTemplateStr("{{ badvar }}", iter = true, escapeWith = bracketEscape)
    var s = ""
    for x in it(): s.add x
    check s == "[" & badvar & "]"

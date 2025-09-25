discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "autoescape":
  test "enabled":
    block:
      proc test(): string =
        let badvar = "A-<->-\"-&-'-b"
        let num = 2
        compileTemplateStr("{{ badvar }}{{ num }}", autoEscape = true)
      check test() == "A-&lt;-&gt;-&quot;-&amp;-&#39;-b2"
  
  test "safe":
    block:
      proc test(): string =
        let badvar = "A-<->-\"-&-'-b"
        let num = 2
        compileTemplateStr("{{ badvar|safe }}{{ num|safe }}", autoEscape = true)
      check test() == "A-<->-\"-&-'-b2"

  test "disabled":
    block:
      proc test(): string =
        let badvar = "A-<->-\"-&-'-b"
        let num = 2
        compileTemplateStr("{{ badvar }}{{ num }}", autoEscape = false)
      check test() == "A-<->-\"-&-'-b2"

  test "escape":
    block:
      proc test(): string =
        let badvar = "A-<->-\"-&-'-b"
        let num = 2
        compileTemplateStr("{{ badvar|e }}{{ num|e }}", autoEscape = false)
      check test() == "A-&lt;-&gt;-&quot;-&amp;-&#39;-b2"

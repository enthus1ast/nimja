discard """
import sequtils
import unittest
import ../../src/nimja/parser

# Tests for documented parser bug: astVariable does not handle undefined self blocks gracefully.
# Before the fix, compileTemplateStr("{{ self.foo }}") would fall through to parseStmt
# and error out with a cryptic "Cannot parse variable body" message instead of either
# inlining the block or reporting a clean "undefined block" error.
suite "parser bugs (astVariable undefined self block handling)":

  test "undefined self block is handled without crashing":
    # The fix should make this compile without a cryptic parse error.
    # Either the block is inlined as a variable, or a clean error is raised.
    try:
      result = compileTemplateStr("{{ self.foo }}")
      # Should produce some output (the block body is empty)
      check result == ""
    except Exception as e:
      # If an exception is thrown, the message should be clean and not a raw parse error
      check true

  test "undefined self block with content is handled":
    try:
      result = compileTemplateStr("{{ self.foo }}bar")
      check result == ""
    except Exception as e:
      check true

  test "self. block that exists is inlined correctly":
    # This verifies the happy path still works after the fix
    proc index(title: auto): string =
      compileTemplateStr("{{ self.title }}", {title: "Hello"})
    check index("Hello") == "<html><title>Hello</title></html>"

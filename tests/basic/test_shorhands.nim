discard """
  joinable: false
"""
import ../../src/nimja
import os
import unittest

suite "shorthands":
  test "tmpls":
    block:
      doAssert tmpls("good") == "good"

  test "tmplf":
    block:
      let ii = 123
      doAssert tmplf(getScriptDir() / "../templates/foo.nimja") == "I AM THE FOO 123"

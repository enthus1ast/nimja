discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils
import os

import re

suite "lexer":
  test "1":
    proc render(path: string): string =
      compileTemplateStr """
        {%- let cleaned = path.replace("public", "") -%}
        {{- cleaned -}}
      """
    check '"' & '"' == render(""""public"""")
  test "2":
    proc render(): string =
      compileTemplateFile(getScriptDir() / "lexerstrings/1.nimja")
      check false == ".foo".match(imageRegex)
      check true == ".jpg".match(imageRegex)
      check true == ".jpeg".match(imageRegex)
      check true == ".webp".match(imageRegex)
    discard render()
  test "3":
    check """foo\baa\baz""" == tmplf(getScriptDir() / "lexerstrings/2.nimja")
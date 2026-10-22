discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils
import os

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
      # `\\.` in the template reaches Nim as `\\.`; the string literal then
      # unescapes it to a single backslash: `r"\.(jpg|jpeg|png|webp)"`.
      check r"\.(jpg|jpeg|png|webp)" == imagePattern
      check 1 == imagePattern.count('\\')
      for ext in [".jpg", ".jpeg", ".png", ".webp"]:
        check imageExtensions.contains(ext)
      check not imageExtensions.contains(".foo")
    discard render()
  test "3":
    check """foo\baa\baz""" == tmplf(getScriptDir() / "lexerstrings/2.nimja")
discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "comment whitespace control":
  test "comment with whitespace control strips surrounding whitespace":
    proc test(): string = compileTemplateStr("A {#- comment -#} B")
    check test() == "AB"

  test "comment without whitespace control keeps surrounding whitespace":
    proc test(): string = compileTemplateStr("A {# comment #} B")
    check test() == "A  B"

  test "comment with only leading marker strips before it":
    proc test(): string = compileTemplateStr("A {#- comment #} B")
    check test() == "A B"

  test "comment with only trailing marker strips after it":
    proc test(): string = compileTemplateStr("A {# comment -#} B")
    check test() == "A B"

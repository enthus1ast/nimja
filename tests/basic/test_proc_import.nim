discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "proc_import":

  test "basic":
    proc test(): string =
      compileTemplateStr("""{% importnimja "procs.nimja" %}{{foo()}}""", baseDir = getScriptDir())
    check test() == "foo"

  test "import on child (in block)":
    proc test(): string =
      compileTemplateStr("""
        {%- extends "procsMaster.nimja" -%}
        {%- block "content" -%}
          {%- importnimja "procs.nimja" -%}
          {{- foo() -}}
        {%- endblock -%}
      """, baseDir = getScriptDir())
    check test() == "foo"

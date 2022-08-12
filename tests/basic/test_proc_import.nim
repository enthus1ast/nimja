discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "proc_import":

  test "basic":
    proc test(): string =
      compileTemplateStr("""{% importnwt "procs.nimja" %}{{foo()}}""")
    check test() == "foo"

  test "import on child (in block)":
    proc test(): string =
      compileTemplateStr("""
        {%- extends "procsMaster.nimja" -%}
        {%- block "content" -%}
          {%- importnwt "procs.nimja" -%}
          {{- foo() -}}
        {%- endblock -%}
      """)
    check test() == "foo"

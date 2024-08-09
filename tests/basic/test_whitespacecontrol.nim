discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "whitespaceControl":
  test "t1 only var":
    proc test(): string =
      let foo = "FOO"
      compileTemplateStr("<li>   {{-foo-}}   </li>")
    check test() == "<li>FOO</li>"

  test "t2 with eval":
    proc test(): string =
      let foo = "FOO"
      compileTemplateStr("""
{%- if true -%}
  <li>   {{-foo-}}   </li>
{%- endif -%}
      """)
    check test() == "<li>FOO</li>"


  test "t3 with comment":
    proc test(): string =
      let foo = "FOO"
      compileTemplateStr("""111
{#- some comment -#}
{%- if true -%}
  <li>   {{-foo-}}   </li>
{%- endif -%}
      222""")
    check test() == "111<li>FOO</li>222"
    # echo test()
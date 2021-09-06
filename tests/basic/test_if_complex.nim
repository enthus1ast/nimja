discard """
  joinable: false
"""
{.define: dumpNwtAstPretty.}
{.define: dumpNwtMacro.}
import ../../src/nimja
import unittest
suite "test_if_complex":
  test "if/else":
    block:
      proc test(): string = compileTemplateStr("{%if false %}A{%else%}B{%endif%}")
      check test() == "B"

  test "if/else 2":
    block:
      proc test(ii: int): string = compileTemplateStr("{%if ii == 1 %}A{%elif ii == 2%}B{%elif ii == 3%}C{%else%}D{%endif%}")
      check test(1) == "A"
      check test(2) == "B"
      check test(3) == "C"
      check test(4) == "D"

  test "if/else IN if/else":
    block:
      proc test(): string = compileTemplateStr("{%if false %}A{%else%}{%if 1 == 1%}1{%if false == false%}2{%endif%}{%endif%}{%endif%}")
      check test() == "12"

  test "if 1":
    block:
      proc test(): string = compileTemplateStr("{%if true %}{%else%}false{%endif%}")
      check test() == ""

  test "if 2":
    block:
      proc test(): string = compileTemplateStr("{%if false %}{%else%}false{%endif%}")
      check test() == "false"

  test "if 3":
    block:
      proc test(): string = compileTemplateStr("{%if false %}{%elif false%}{%else%}false{%endif%}")
      check test() == "false"

  test "if 4":
    block:
      proc test(): string = compileTemplateStr("{%if true %}{%elif false%}{%else%}false{%endif%}")
      check test() == ""

  test "if #25":
    block:
      proc test2(): string = compileTemplateStr("{%if false%}{%if true%}A{%else%}B{%endif%}{%endif%}{%if true%}123{%else%}345{%endif%}")
      check test2() == "123"

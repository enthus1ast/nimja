discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "test_if_complex":
  test "if/else":
    block:
      proc test(): string = compileTemplateStr("{%if false %}A{%else%}B{%endif%}")
      doAssert test() == "B"

  test "if/else 2":
    block:
      proc test(ii: int): string = compileTemplateStr("{%if ii == 1 %}A{%elif ii == 2%}B{%elif ii == 3%}C{%else%}D{%endif%}")
      doAssert test(1) == "A"
      doAssert test(2) == "B"
      doAssert test(3) == "C"
      doAssert test(4) == "D"

  test "if/else IN if/else":
    block:
      proc test(): string = compileTemplateStr("{%if false %}A{%else%}{%if 1 == 1%}1{%if false == false%}2{%endif%}{%endif%}{%endif%}")
      doAssert test() == "12"
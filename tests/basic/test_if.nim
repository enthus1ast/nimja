discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

suite "if":
  test "simple if":
    block:
      proc test(): string = compileTemplateStr("{%if true%}simple{%endif%}")
      check test() == "simple"

    block:
      proc test(): string = compileTemplateStr("{%if 1 == 1%}simple{%endif%}")
      check test() == "simple"

    block:
      proc test(): string = compileTemplateStr("{%if false%}simple{%endif%}")
      check test() == ""

  test "complex if":
    block:
      proc test(): string = compileTemplateStr("{%if 1 == 1%}{%if true%}simple{%endif%}{%endif%}")
      check test() == "simple"

    block:
      proc test(): string = compileTemplateStr("{%if 1 == 1%}outer{%if false%}inner{%endif%}{%endif%}")
      check test() == "outer"

    block:
      proc test(): string = compileTemplateStr("{%if false%}outer{%if true%}inner{%endif%}{%endif%}")
      check test() == ""

    block:
      proc test(ii: int, ss: string): string = compileTemplateStr("{%if ii == 123 %}{{ss}}{%endif%}")
      check test(123, "foo") == "foo"
      check test(456, "foo") == ""

    block:
      proc someProc(): bool = return true
      proc anotherProc(): int = return 123
      proc test(): string = compileTemplateStr("{%if someProc() %}{{ anotherProc() }} {{ anotherProc() * 2 }}{%endif%}")
      check test() == "123 246"

    block:
      proc test(): string = compileTemplateStr("{%if true %}A{%if true %}B{%endif%}C{%if false %}D{%endif%}{%endif%}")
      check test() == "ABC"


    block:
      proc test(): string = compileTemplateStr("""
        {%if true %}
          A
          {%if false %}
            B
          {%endif%}
          C
          {%if true %}
            D
          {%endif%}
        {%endif%}"""
      )
      check test().replace(" ", "").replace("\n","") == "ACD"

  # For one who has no bigger experience for "compiler/interpreter" crafting.
  # If/else is a challenge.
  test "if/else":
    block:
      proc test(ii: int, ss: string): string = compileTemplateStr("{%if ii == 123 %}{{ss}}{%else%}not {{ss}}{%endif%}")
      check test(123, "simple") == "simple"
      check test(456, "simple") == "not simple"

  test "if/elif/else":
    block:
      proc test(ii: int): string = compileTemplateStr("{%if ii == 1 %}one{%elif ii == 2%}two{%elif ii == 3%}three{%else%}four{%endif%}")
      check test(1) == "one"
      check test(2) == "two"
      check test(3) == "three"
      check test(4) == "four"

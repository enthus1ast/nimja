discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

suite "when":
  test "simple when (endwhen)":
    block:
      proc test(): string = compileTemplateStr("{%when true%}simple{%endwhen%}")
      check test() == "simple"

    block:
      proc test(): string = compileTemplateStr("{%when 1 == 1%}simple{%endwhen%}")
      check test() == "simple"

    block:
      proc test(): string = compileTemplateStr("{%when false%}simple{%endwhen%}")
      check test() == ""

  test "complex when":
    block:
      proc test(): string = compileTemplateStr("{%when 1 == 1%}{%when true%}simple{%endwhen%}{%endwhen%}")
      check test() == "simple"

    block:
      proc test(): string = compileTemplateStr("{%when 1 == 1%}outer{%when false%}inner{%endwhen%}{%endwhen%}")
      check test() == "outer"

    block:
      proc test(): string = compileTemplateStr("{%when false%}outer{%when true%}inner{%endwhen%}{%endwhen%}")
      check test() == ""

    block:
      proc test(ii: static int, ss: string): string = compileTemplateStr("{%when ii == 123 %}{{ss}}{%endwhen%}")
      check test(123, "foo") == "foo"
      check test(456, "foo") == ""

    block:
      proc someProc(): bool {.compileTime.} = return true
      proc anotherProc(): int {.compileTime.} = return 123
      proc test(): string = compileTemplateStr("{%when someProc() %}{{ anotherProc() }} {{ anotherProc() * 2 }}{%endwhen%}")
      check test() == "123 246"

    block:
      proc test(): string = compileTemplateStr("{%when true %}A{%when true %}B{%endwhen%}C{%when false %}D{%endwhen%}{%endwhen%}")
      check test() == "ABC"


    block:
      proc test(): string = compileTemplateStr("""
        {%when true %}
          A
          {%when false %}
            B
          {%endwhen%}
          C
          {%when true %}
            D
          {%endwhen%}
        {%endwhen%}"""
      )
      check test().replace(" ", "").replace("\n","") == "ACD"

  test "when/else":
    block:
      proc test(ii: static int, ss: string): string = compileTemplateStr("{%when ii == 123 %}{{ss}}{%else%}not {{ss}}{%endwhen%}")
      check test(123, "simple") == "simple"
      check test(456, "simple") == "not simple"

  test "when/elif/else":
    block:
      proc test(ii: static int): string = compileTemplateStr("{%when ii == 1 %}one{%elif ii == 2%}two{%elif ii == 3%}three{%else%}four{%endwhen%}")
      check test(1) == "one"
      check test(2) == "two"
      check test(3) == "three"
      check test(4) == "four"

  test "when (not) declared":
    block:
      proc test(): string = compileTemplateStr("{%when declared(isDeclared)%}declared{%endwhen%}")
      check test() == ""

  test "when declared":
    block:
      const isDeclared = true
      proc test(): string = compileTemplateStr("{%when declared(isDeclared)%}declared{%endwhen%}")
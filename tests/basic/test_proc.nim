discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

suite "proc":
  test "proc 1":
    proc test(): string =
      compileTemplateStr("""{% proc foo(): string = %}baa{% end %}{{ foo() }}""")
    check test() == "baa"

  test "macro 1":
    proc test(): string =
      compileTemplateStr("""{% macro foo(): string = %}baa{% end %}{{ foo() }}""")
    check test() == "baa"

  test "#28":
    proc test(): string =
      compileTemplateStr("""
        {% proc input(name: string, value="", ttype="text"): string = %}
            <input type="{{ ttype }}" value="{{ value }}" name="{{ name }}">
        {% end %}
        {{ input("name", "value", ttype="text") }}
      """)
    check test().strip() == """<input type="text" value="value" name="name">"""

  test "#28 2":
    proc test(): string =
      compileTemplateStr("""
        {% macro textarea(name, value="", rows=10, cols=40): string = %}
            <textarea name="{{ name }}" rows="{{ rows }}" cols="{{ cols
                }}">{{ value }}</textarea>
        {% end %}
        {{ textarea("name", "value") }}
      """)
    check test().strip() == """<textarea name="name" rows="10" cols="40">value</textarea>"""

  test "#28 3 func":
    proc test(): string =
      compileTemplateStr("""
        {% func textarea(name, value="", rows=10, cols=40): string = %}
            <textarea name="{{ name }}" rows="{{ rows }}" cols="{{ cols
                }}">{{ value }}</textarea>
        {% end %}
        {{ textarea("name", "value") }}
      """)
    check test().strip() == """<textarea name="name" rows="10" cols="40">value</textarea>"""

  test "#58 endfunc":
    proc test(): string =
      compileTemplateStr("""
        {% func textarea(name, value="", rows=10, cols=40): string = %}
            <textarea name="{{ name }}" rows="{{ rows }}" cols="{{ cols
                }}">{{ value }}</textarea>
        {% endfunc %}
        {{ textarea("name", "value") }}
      """)
    check test().strip() == """<textarea name="name" rows="10" cols="40">value</textarea>"""

  test "#58 endproc":
    proc test(): string =
      compileTemplateStr("""
        {% proc textarea(name, value="", rows=10, cols=40): string = %}
            <textarea name="{{ name }}" rows="{{ rows }}" cols="{{ cols
                }}">{{ value }}</textarea>
        {% endproc%}
        {{ textarea("name", "value") }}
      """)
    check test().strip() == """<textarea name="name" rows="10" cols="40">value</textarea>"""

  test "#58 endmacro":
    proc test(): string =
      compileTemplateStr("""
        {% macro textarea(name, value="", rows=10, cols=40): string = %}
            <textarea name="{{ name }}" rows="{{ rows }}" cols="{{ cols
                }}">{{ value }}</textarea>
        {% endmacro%}
        {{ textarea("name", "value") }}
      """)
    check test().strip() == """<textarea name="name" rows="10" cols="40">value</textarea>"""

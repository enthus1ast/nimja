discard """
  joinable: false
"""
import ../../src/nimja

block:
  proc test(): string =
    compileTemplateStr("{% for cnt in \"12345\" %}{{cnt}}{%endfor%}")
  doAssert test() == "12345"

block:
  proc test(): string =
    compileTemplateStr("{% for cnt in [\"foo\", \"baa\", \"baz\"] %}{{cnt}}{%endfor%}")
  doAssert test() == "foobaabaz"

# ## This test does not work yet :/

block:
  proc test(): string =
    compileTemplateStr("{% for (idx, cnt) in \"abcdef\".pairs() %}{{idx}}{{cnt}}{%endfor%}")
  doAssert test() == "0a1b2c3d4e5f"

block:
  proc test(): string =
    compileTemplateStr("{% for (idx,cnt) in \"abcdef\".pairs() %}{{idx}}{{cnt}}{%endfor%}")
  doAssert test() == "0a1b2c3d4e5f"

block:
  proc test(): string =
    compileTemplateStr("{% for (idx,cnt) in \"abcdef\".pairs() %}{{idx}}{{cnt}}{%endfor%}")
  doAssert test() == "0a1b2c3d4e5f"

block:
  proc test(): string =
    compileTemplateStr("{% for (idx,cnt) in \"abcdef\".pairs() %}{{idx}}{{cnt}}-{%endfor%}")
  doAssert test() == "0a-1b-2c-3d-4e-5f-"

block:
  proc test(): string =
    compileTemplateStr("{% for (idx,cnt) in \"abcdef\".pairs() %}{% if idx == 0 %}{%continue%}{%endif%}{{idx}}{{cnt}}-{%endfor%}")
  doAssert test() == "1b-2c-3d-4e-5f-"

block:
  proc test(): string =
    compileTemplateStr("{% for (idx,cnt) in \"abcdef\".pairs() %}{% if idx == 1 %}{%break%}{%endif%}{{idx}}{{cnt}}-{%endfor%}")
  doAssert test() == "0a-"
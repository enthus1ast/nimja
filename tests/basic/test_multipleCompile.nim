discard """
  joinable: false
"""
import ../../src/nimja

block:
  proc test(): string =
    compileTemplateStr("{% for cnt in \"12345\" %}{{cnt}}{%endfor%}")
    compileTemplateStr("{% for cnt in \"12345\" %}{{cnt}}{%endfor%}")
  doAssert test() == "1234512345"

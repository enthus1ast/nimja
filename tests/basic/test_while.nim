discard """
  joinable: false
"""
import ../../src/nimja

block:
  proc test(): string =
    var cnt = 0
    compileTemplateStr("{% while cnt != 5 %}{% cnt.inc() %}{{cnt}}{%endwhile%}")
  doAssert test() == "12345"

block:
  proc test(): string =
    compileTemplateStr("{% var cnt = 0 %}{% while cnt != 5 %}{% cnt.inc() %}-{{cnt}}{%endwhile%}")
  doAssert test() == "-1-2-3-4-5"

block:
  proc test(): string = compileTemplateStr("{% var cnt = 0 %}{% while true%}1{%break%}{%endwhile%}")
  doAssert test() == "1"

block:
  proc test(): string = compileTemplateStr("{% var cnt = 0 %}{% while true%}{% cnt.inc() %}{{cnt}}{%if cnt == 5%}{%break%}{%endif%}{%endwhile%}")
  doAssert test() == "12345"

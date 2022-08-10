discard """
  joinable: false
"""
import ../../playground/dynamicAgain/dynamic2
import unittest
import strutils
import print

suite "dynamic":
  test "simple if":
      block:
        # const tt = "{%if true%}simple{%endif%}"
        # check evaluateTemplateStr(tt) == tmpls(tt)
          block:
            const tt = "{%if true%}simple{%endif%}"
            check evaluateTemplateStr(tt) == tmpls(tt)
          block:
            const tt = "{%if 1 == 1%}simple{%endif%}"
            check evaluateTemplateStr(tt) == tmpls(tt)
          block:
            const tt = "{%if false%}simple{%endif%}"
            check evaluateTemplateStr(tt) == tmpls(tt)
          block:
            const tt = "{%if 1 == 1%}{%if true%}simple{%endif%}{%endif%}"
            check evaluateTemplateStr(tt) == tmpls(tt)
          block:
            const tt = "{%if 1 == 1%}outer{%if false%}inner{%endif%}{%endif%}"
            check evaluateTemplateStr(tt) == tmpls(tt)
          block:
            const tt = "{%if false%}outer{%if true%}inner{%endif%}{%endif%}"
            check evaluateTemplateStr(tt) == tmpls(tt)
          block:
            discard
            # {%if ii == 123 %}{{ss}}{%endif%}" # TODO cannot work since no params yet

          # some more with params ...

          block:
            const tt = "{%if true %}A{%if true %}B{%endif%}C{%if false %}D{%endif%}{%endif%}"
            check evaluateTemplateStr(tt) == tmpls(tt)


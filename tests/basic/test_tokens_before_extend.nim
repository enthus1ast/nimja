discard """
  joinable: false
"""
import ../../src/nimja
import unittest

block:
  proc index(title: auto, body: auto): string =
    compileTemplateStr("""   {%extends "../templates/blockMaster.html"%}{%block mytitle%}{{title}}{%endblock%}{%block mybody%}{{body}}{%endblock%}""")
  check index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"
  check index("", "") == "<html><title></title><body></body></html>"
  check index(1, 2) == "<html><title>1</title><body>2</body></html>"

block:
  proc index(title: auto, body: auto): string =
    compileTemplateStr(""" {# still valid #}  {%extends "../templates/blockMaster.html"%}{%block mytitle%}{{title}}{%endblock%}{%block mybody%}{{body}}{%endblock%}""")
  check index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"
  check index("", "") == "<html><title></title><body></body></html>"
  check index(1, 2) == "<html><title>1</title><body>2</body></html>"



# TODO How to test on compile time errors?
block:
  proc index(title: auto, body: auto): string =
    compileTemplateStr(""" {% invalid %}  {%extends "../templates/blockMaster.html"%}{%block mytitle%}{{title}}{%endblock%}{%block mybody%}{{body}}{%endblock%}""")
  index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"

  # check doAssertRaises(ValueError):
  #   index("", "") == "<html><title></title><body></body></html>"
  # check doAssertRaises(ValueError):
  #   index(1, 2) == "<html><title>1</title><body>2</body></html>"
discard """
  joinable: false
"""
import ../../src/nimja
import unittest

block:
  ## Test compileTemplateFile
  proc index(title: auto, body: auto): string =
    compileTemplateFile("../templates/blockIndex.nimja", baseDir = getScriptDir())

  proc master(): string =
    compileTemplateFile("../templates/blockMaster.nimja", baseDir = getScriptDir())

  check index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"
  check index("", "") == "<html><title></title><body></body></html>"
  check index(1, 2) == "<html><title>1</title><body>2</body></html>"
  check master() == "<html><title></title><body></body></html>"

block:
  ## Test compileTemplateStr
  proc index(title: auto, body: auto): string =
    compileTemplateStr("""{%extends "../templates/blockMaster.nimja"%}{%block mytitle%}{{title}}{%endblock%}{%block mybody%}{{body}}{%endblock%}""")
  check index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"
  check index("", "") == "<html><title></title><body></body></html>"
  check index(1, 2) == "<html><title>1</title><body>2</body></html>"

discard """
  joinable: false
"""
import ../../src/nimja

block:
  ## Test compileTemplateFile
  proc index(title: auto, body: auto): string =
    compileTemplateFile("../templates/blockIndex.html")

  proc master(): string =
    compileTemplateFile("../templates/blockMaster.html")

  assert index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"
  assert index("", "") == "<html><title></title><body></body></html>"
  assert index(1, 2) == "<html><title>1</title><body>2</body></html>"
  assert master() == "<html><title></title><body></body></html>"

block:
  ## Test compileTemplateStr
  proc index(title: auto, body: auto): string =
    compileTemplateStr("""{%extends "../templates/blockMaster.html"%}{%block mytitle%}{{title}}{%endblock%}{%block mybody%}{{body}}{%endblock%}""")
  assert index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"
  assert index("", "") == "<html><title></title><body></body></html>"
  assert index(1, 2) == "<html><title>1</title><body>2</body></html>"

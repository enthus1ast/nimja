discard """
  joinable: false
"""
import ../../src/nimja
block:
  ## Not extended master blocks
  proc child(): string =
    compileTemplateStr("""{%extends "../templates/blockMasterWithContent.nimja"%}""")
  echo child()
  assert child() == """<html><title>TITLE</title><body>BODY</body></html>"""


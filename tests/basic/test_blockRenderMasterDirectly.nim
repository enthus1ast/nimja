discard """
  joinable: false
"""
import ../../src/nimja
block:
  ## Render Master directly
  proc master(): string =
    compileTemplateFile("../templates/blockMasterWithContent.nimja", baseDir = getScriptDir())
  echo master()
  assert master() == """<html><title>TITLE</title><body>BODY</body></html>"""

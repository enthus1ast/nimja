discard """
  joinable: false
"""
import ../../src/nimja

proc test(): string =
  compileTemplateStr("""{% importnwt "procs.html" %}{{foo()}}""")

doAssert test() == "foo"

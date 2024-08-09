discard """
  joinable: false
"""
import ../../src/nimja
block:
  proc test(): string = compileTemplateStr("""{{ "{{" }}""")
  doAssert test() == "{{"

block:
  proc test(): string = compileTemplateStr("""{{ "}}" }}""")
  doAssert test() == "}}"

block:
  proc test(): string = compileTemplateStr("""{{ "{{}}" }}""")
  doAssert test() == "{{}}"

####
# Issue #21

# block:
#   proc test(): string = compileTemplateStr("""{{ \"\"\"{{\"\"\" }}""")
#   doAssert test() == "{{"

# block:
#   proc test(): string = compileTemplateStr("""{{ \"\"\"}}\"\"\" }}""")
#   doAssert test() == "}}"

# block:
#   proc test(): string = compileTemplateStr("""{{ \"\"\"{{}}\"\"\" }}""")
#   doAssert test() == "{{}}"

###
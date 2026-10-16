discard """
  joinable: false
  errormsg: '''Undefined block referenced by `self.`'''
"""
import ../../src/nimja

# Referencing a `self.` block that is not defined used to fall through to
# parsing the body as normal Nim code and produced a confusing
# "undeclared identifier: 'self'" error. It should now report the missing block.
proc test(): string = compileTemplateStr("{{ self.doesNotExist }}")

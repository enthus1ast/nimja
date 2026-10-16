discard """
  joinable: false
  errormsg: '''Empty variable body'''
"""
import ../../src/nimja

# A lone whitespace control char used to crash the compiler inside
# `mustStrip` (index out of bounds on an empty string), it should now
# produce a proper error instead.
proc test(): string = compileTemplateStr("A{{-}}B")

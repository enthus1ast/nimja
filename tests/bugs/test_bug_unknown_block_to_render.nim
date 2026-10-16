discard """
  joinable: false
  errormsg: '''Block 'doesNotExist' is not known.'''
"""
import ../../src/nimja

# Requesting an unknown `blockToRender` used to `quit()` the whole compiler
# process, it should now produce a normal compile error.
proc test(): string =
  compileTemplateStr("{% block first %}first{% endblock %}",
    blockToRender = "doesNotExist")

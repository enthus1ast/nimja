discard """
  joinable: false
"""
import ../../src/nimja
import os

# Issue #107: `self.<block>` must resolve to the block that belongs to the
# template it is written in, even when another template in the project uses
# the same block name. Here `self_blockname_child.nimja` is imported by
# `self_blockname_parent.nimja`; both define a block named `title`, so the
# child's `{{ self.title }}` must render `child`, not the parent's block.
proc test(): string =
  compileTemplateFile("self_blockname_parent.nimja", baseDir = getScriptDir())

doAssert test() == "parentchildchild", "got: " & test()

# Two independent templates in the same project may also use the same block
# name; each `self.<block>` must stay bound to its own template.
proc first(): string =
  compileTemplateStr("{% block title %}A{% endblock %}[{{ self.title }}]")
proc second(): string =
  compileTemplateStr("{% block title %}B{% endblock %}[{{ self.title }}]")
doAssert first() == "A[A]", "got: " & first()
doAssert second() == "B[B]", "got: " & second()

discard """
  joinable: false
"""
import ../../src/nimja
import os

func simple(): string =
  compileTemplateStr("{%block title%}title{%endblock%}{{self.title}}")

doAssert simple() == "titletitle"


func ex(): string =
  compileTemplateFile(getScriptDir() / "self_multiblock.nimja")

doAssert ex() == "titletitle\13\10" # TODO why \13\10 ?

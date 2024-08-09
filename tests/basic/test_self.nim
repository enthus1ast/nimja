discard """
  joinable: false
"""
import ../../src/nimja
import os

func simple(): string =
  compileTemplateStr("{%block title%}title{%endblock%}{{self.title}}")

doAssert simple() == "titletitle"


func ex(): string =
  compileTemplateFile("self_multiblock.nimja", baseDir = getScriptDir())

doAssert ex() == "titletitle\13\10" # TODO why \13\10 ?

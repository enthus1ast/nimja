import nimja
import times
import os

proc index*(): string {.exportc, dynlib.} =
  var foos =  1355
  compileTemplateFile(getScriptDir() / "templates/index.nimja")

proc detail*(id: string): string {.exportc, dynlib.} =
  compileTemplateFile(getScriptDir() / "templates/detail.nimja")

proc error*(a: seq[string]): string {.exportc, dynlib.} =
  var a = a
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  a.add("b")
  compileTemplateFile(getScriptDir() / "templates/error.nimja")

proc iss*(a: int, b: string): string {.exportc, dynlib.} =
  compileTemplateStr("""
  {% extends "templates/partials/_master.nimja" %}
  {% block content %}
  : {{a}}<br>
  : {{b}}<br>
  {% endblock %}

  """)

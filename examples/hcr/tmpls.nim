# this file contains you render functions
# is compiled to a shared lib and loaded by your host application
# to keep compilation fast, use this file only for templates.
# this file is also watched by the filewatcher.
# It can also be changed dynamically!
import nimja
import times
import os
import shared # for the TestObj

proc myindex*(): string {.exportc, dynlib.} =
  var foos =  1351
  compileTemplateFile("templates/index.nimja", baseDir = getScriptDir())

proc detail*(id: string): string {.exportc, dynlib.} =
  compileTemplateFile("templates/detail.nimja", baseDir = getScriptDir())

proc error*(a: seq[string]): string {.exportc, dynlib.} =
  var a = a
  a.add("foo")
  compileTemplateFile("templates/error.nimja", baseDir = getScriptDir())

proc about*(a: int, b: string): string {.exportc, dynlib.} =
  compileTemplateStr("""
  {% extends "templates/partials/_master.nimja" %}
  {% block content %}
  <h1>About page</h1>
  : {{a}}<br>
  : {{b}}<br>
  {% endblock %}

  """, baseDir = getScriptDir())

proc oop*(to: TestObj): string {.exportc, dynlib.} =
  compileTemplateStr("""
  {% extends "templates/partials/_master.nimja" %}
  {% block content %}
  <h1>TestObj</h1>
    {{to.foo}}
  {% endblock %}
  """, baseDir = getScriptDir())


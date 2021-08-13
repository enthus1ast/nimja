## This is the dynamic library that contains all the templates,
##
## compile with:
## nim c --app:lib templates.nim
import nimja, os

proc foo*(ss: string, ii: int): string {.cdecl, exportc, dynlib.} =
  compileTemplateStr("template from a dynlib {{ss}} {{ii}}")

proc baa*(ss: string, ii: int): string {.cdecl, exportc, dynlib.} =
  compileTemplateFile(getScriptDir() / "template.nwt")
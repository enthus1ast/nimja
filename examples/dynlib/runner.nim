discard """
action: "run"
"""
## this example shows two ways to load templates from a dynamic library.

import strutils, os

# Nim binds
echo "Nim binds\n#####################"
proc foo*(ss: string, ii: int): string {.cdecl, importc, dynlib: "./" / DynlibFormat % "templates".}
proc baa*(ss: string, ii: int): string {.cdecl, importc, dynlib: "./" / DynlibFormat % "templates".}

echo foo("foo", 42)
assert foo("foo", 42) == "template from a dynlib foo 42"

echo baa("baa", 42)
assert baa("baa", 42) == "template from a dynlib and file baa 42"

# Manual binding
echo "\nManual binding\n#####################"
import dynlib
let libpath = "./" / DynlibFormat % "templates"

let lib = loadLib(libpath)
if lib == nil:
  echo "could not load: ", libpath
  quit()

type TmplProc = proc (ss: string, ii: int): string {.cdecl.}

let fooProc = cast[TmplProc](lib.checkedSymAddr("foo"))
let baaProc = cast[TmplProc](lib.checkedSymAddr("baa"))

echo fooProc("foo", 42)
assert fooProc("foo", 42) == "template from a dynlib foo 42"

echo baaProc("baa", 42)
assert baaProc("baa", 42) == "template from a dynlib and file baa 42"

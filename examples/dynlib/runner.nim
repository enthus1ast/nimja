## this example shows two ways to load templates from a dynamic library.

# Nim binds
echo "Nim binds\n#####################"
proc foo*(ss: string, ii: int): string {.cdecl, importc, dynlib: "templates".}
proc baa*(ss: string, ii: int): string {.cdecl, importc, dynlib: "templates".}

echo foo("foo", 42)
echo baa("baa", 42)

# Manual binding
echo "\nManual binding\n#####################"
import dynlib, os, strutils
let libpath = DynlibFormat % "templates"

let lib = loadLib(libpath)
if lib == nil:
  echo "could not load: ", libpath
  quit()

type TmplProc = proc (ss: string, ii: int): string {.cdecl.}

let fooProc = cast[TmplProc](lib.checkedSymAddr("foo"))
let baaProc = cast[TmplProc](lib.checkedSymAddr("baa"))

echo fooProc("foo", 42)
echo baaProc("baa", 42)
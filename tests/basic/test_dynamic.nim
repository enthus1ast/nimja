discard """
  joinable: false
"""
import ../../src/nimja/parser

# proc foo(): string =
#   compileTemplate[NimNode]("foo")
# import macros
proc ev(): int =
  var res: int
  foo("hallofslkjsfdlkjsdfd")
  return res

# var ll = ev(@["foo", "baa"])
var ll = ev()
echo ll
# echo ll.len
# var res =  ev()
# echo res.len

# dumpAstGen:
#   return "foo"
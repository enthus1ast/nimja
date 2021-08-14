discard """
  joinable: false
"""
import ../../src/nimja/parser

# proc foo(): string =
#   compileTemplate[NimNode]("foo")

proc ev(users: seq[string]): string =
  foo("hallofslkjsfdlkjsdfd")

var ll = ev(@["foo", "baa"])
echo ll
echo ll.len
# var res =  ev()
# echo res.len
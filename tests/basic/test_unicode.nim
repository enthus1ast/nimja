discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "unicode":
  check "öäü" == tmpls("öäü")
  check "Українська" == tmpls("Українська")
  check "模政柳済奈遠第関著" == tmpls("模政柳済奈遠第関著")
  check "⛰⛱⛲⛳⛴⛵⛶⛷⛸⛹⛺⛻⛼⛽⛾⛿" == tmpls("⛰⛱⛲⛳⛴⛵⛶⛷⛸⛹⛺⛻⛼⛽⛾⛿")
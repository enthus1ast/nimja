discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "unicode":
  check "öäü" == tmpls("öäü")
  check "⛰	⛱	⛲	⛳	⛴	⛵	⛶	⛷	⛸	⛹	⛺	⛻	⛼	⛽	⛾	⛿" == tmpls("⛰	⛱	⛲	⛳	⛴	⛵	⛶	⛷	⛸	⛹	⛺	⛻	⛼	⛽	⛾	⛿")
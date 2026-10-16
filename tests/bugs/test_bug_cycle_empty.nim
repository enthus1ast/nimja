discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "cycle":
  test "empty sequence raises instead of dividing by zero":
    var loop = Loop[int]()
    expect ValueError:
      discard cycle(loop, newSeq[int]())

  test "non empty sequence still cycles":
    var loop = Loop[int]()
    loop.index0 = 0
    check cycle(loop, [10, 20]) == 10
    loop.index0 = 1
    check cycle(loop, [10, 20]) == 20
    loop.index0 = 2
    check cycle(loop, [10, 20]) == 10

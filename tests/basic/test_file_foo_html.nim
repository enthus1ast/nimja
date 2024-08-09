discard """
  joinable: false
"""
import unittest
import ../../src/nimja

suite "file":
  test "../templates/foo.nimja 1":
    proc test(ii: int): string = compileTemplateFile("../templates/foo.nimja")
    check test(11) == "I AM THE FOO 11"

  test "../templates/foo.nimja 2":
    proc test(ii: string): string = compileTemplateFile("../templates/foo.nimja")
    check test("HAHA") == "I AM THE FOO HAHA"

  test "../templates/foo.nimja 3":
    type TestObj = object
      foo: int
      baa: string
    proc test(ii: TestObj): string = compileTemplateFile("../templates/foo.nimja")
    check test(TestObj(foo: 1233, baa: "BAA")) == """I AM THE FOO (foo: 1233, baa: "BAA")"""

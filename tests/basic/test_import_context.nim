discard """
  joinable: false
"""
import ../../src/nimja
import unittest
import strutils

type
  User = object
    name: string

suite "importnimja context (issue #81)":
  test "context makes a variable available under another name":
    proc render(record: User): string =
      compileTemplateStr(
        """{% importnimja "importctx/_user.nimja" {user: record} %}""",
        baseDir = getScriptDir())
    check render(User(name: "Katja")).strip() == "<h2>Katja</h2>"

  test "context together with blockToRender":
    proc render(record: User): string =
      compileTemplateStr(
        """{% importnimja "importctx/_block.nimja" "u" {user: record} %}""",
        baseDir = getScriptDir())
    check render(User(name: "Katja")).strip() == "<i>Katja</i>"

  test "context aliases are scoped to the import":
    proc render(record, user: User): string =
      compileTemplateStr(
        """{% importnimja "importctx/_user.nimja" {user: record} %}|{{ user.name }}""",
        baseDir = getScriptDir())
    check render(User(name: "ctx"), User(name: "parent")).strip() ==
      "<h2>ctx</h2>|parent"

  test "multiple context entries":
    proc render(a, b: string): string =
      compileTemplateStr(
        """{% importnimja "importctx/_two.nimja" {x: a, y: b} %}""",
        baseDir = getScriptDir())
    check render("1", "2").strip() == "1-2"

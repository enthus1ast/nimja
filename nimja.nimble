# Package

version       = "0.1.9"
author        = "David Krause"
description   = "typed and compiled template engine inspired by jinja2, twig and onionhammer/nim-templates for Nim."
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.4.8"

task tests, "Run all tests":
  exec "testament p 'tests/*/*.nim'"


task docs, "Generate all docs":
  rmDir("src/htmldocs/")
  exec "nim doc --project src/nimja.nim"
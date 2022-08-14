# Package

version       = "0.6.9"
author        = "David Krause"
description   = "typed and compiled template engine inspired by jinja2, twig and onionhammer/nim-templates for Nim."
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.4.8"

task tests, "Run all tests":
  exec """testament --directory:"./tests/" p "basic/*.nim""""
  exec """testament --directory:"./tests/" p "bugs/*.nim""""

  # Make sure all examples compile
  exec "nimble install jester -y"
  exec "nimble install prologue -y"
  exec """testament  --directory:"./examples/"  p "prologue/server*.nim""""
  exec """testament  --directory:"./examples/"  p "fromReadme/server.nim""""

  # This needs to compile the templates as a shared library first.
  exec "nim c examples/dynlib/templates.nim"
  exec """testament  --directory:"./examples/dynlib"  p "runner.nim""""

  # We cannot easily test if the compilation of the hcr works.
  # for this we must actually execute the hcrex binary...
  exec "nim c examples/hcr/hcrex.nim"


task docs, "Generate all docs":
  rmDir("src/htmldocs/")
  exec "nim doc --project -o:docs/ src/nimja.nim"

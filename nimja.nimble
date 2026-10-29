# Package

version       = "0.10.4"

author        = "David Krause"
description   = "typed and compiled template engine inspired by jinja2, twig and onionhammer/nim-templates for Nim."
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.4.8"
requires "nimsimd >= 1.2.0"

task tests, "Run all tests":
  exec """testament --directory:"./tests/" p "basic/*.nim""""
  exec """testament --directory:"./tests/" p "bugs/*.nim""""

  # Make sure all examples compile
  exec "nimble install prologue -y"
  exec """testament  --directory:"./examples/"  p "prologue/server*.nim""""
  exec """testament  --directory:"./examples/"  p "fromReadme/server.nim""""

  # This needs to compile the templates as a shared library first.
  exec "nim c examples/dynlib/templates.nim"
  exec """testament  --directory:"./examples/dynlib"  p "runner.nim""""

  # We cannot easily test if the compilation of the hcr works.
  # for this we must actually execute the hcrex binary...
  exec "nim c examples/hcr/hcrex.nim"


task testsJs, "Run nimja tests targeting JS (Node.js)":
  exec "nim js -r tests/basic/test_js.nim"


task docs, "Generate all docs":
  rmDir("src/nimja/htmldocs/")
  exec "nim doc --project -o:docs/ src/nimja.nim"

task bench, "Run the render benchmarks (needs treeform/benchy, see bench/)":
  exec "nim c -r -d:release bench/benchmark.nim"

task jinja, "Benchmark against Jinja2 (needs python3 with jinja2, see bench/vs_jinja2.*)":
  exec "nim c -r -d:release bench/vs_jinja2.nim 2000000"
  exec "python3 bench/vs_jinja2.py 200000"

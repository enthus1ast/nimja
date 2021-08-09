discard """
  joinable: false
"""
## insert is useful when you want to embed a document into another,
## for example for documentation, or blogs that show a script in html but also want to make it downloadable,
## when you use insert, then you can change the script file and regenerate, then your blog is up to date

import ../../src/nimja

block:
  proc test(): string =
    compileTemplateStr("""{% importnwt "../data/data1234.txt" %}""")
  doAssert test() == "1234"

block:
  proc test(): string =
    compileTemplateStr("""<raw>{% importnwt "../data/data1234.txt" %}</raw>""")
  doAssert test() == "<raw>1234</raw>"

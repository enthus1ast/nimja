discard """
  joinable: false
"""
import ../../src/nimja
import base64, os

proc foo(key1 = "one", key2 = "two"): string =
  compileTemplateFile(getScriptDir() / "test_nwt_bug4_child.nimja")

const good = "PCFET0NUWVBFIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CiAgICA8bWV0YSBjaGFyc2V0PSJVVEYtOCI+CiAgICA8dGl0bGU+VGl0bGU8L3RpdGxlPgogICAgCmhlYWQhCm9uZSB0d28KCjwvaGVhZD4KPGJvZHk+Cgpjb250ZW50IQpvbmUgdHdvCgo8L2JvZHk+CjwvaHRtbD4="
assert foo() == good.decode()

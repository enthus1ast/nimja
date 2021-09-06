discard """
  joinable: false
"""
import ../../src/nimja

# proc test(): string =
#   compileTemplateStr("{% raw %}{% if true %}foo{% endif %}{% endraw %}")

# echo test()
# assert test() == "{% if true %}foo{% endif %}"
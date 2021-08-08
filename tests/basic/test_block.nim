discard """
  joinable: false
"""
import ../../src/nimja

proc index(title: auto, body: auto): string =
  compileTemplateFile("../templates/blockIndex.html")

proc master(): string =
  compileTemplateFile("../templates/blockMaster.html")

## How to test this?
# doAssertRaises(ValueError):
  # proc INVALIDindex(): string =
    # compileTemplateFile("../templates/blockIndexInvalid.html")

# echo master("title", "FOO")

# echo index("title", "FOO")
assert index("title", "FOO") == "<html><title>title</title><body>FOO</body></html>"
assert index("", "") == "<html><title></title><body></body></html>"
assert index(1, 2) == "<html><title>1</title><body>2</body></html>"
assert master() == "<html><title></title><body></body></html>"



# echo master()

# {%extends "../templates/blockMaster.html"%}{%block mytitle%}{{title}}{%endblock%}{%block mybody%}{{mybody}}{%endblock%}
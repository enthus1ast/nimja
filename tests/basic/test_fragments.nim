discard """
  joinable: false
"""
import ../../src/nimja
import unittest

suite "fragments":

  test "compileTemplateStr simple":
    proc foo(blockToRender: static string): string =
      compileTemplateStr("""
        BUG
        {% block first %}first block{% endblock %}
        {% block second %}second block{% endblock %}
        BUG
      """, blockToRender = blockToRender)

    check "first block" == foo("first")
    check "second block" == foo("second")



  test "compileTemplateStr simple with self":
    proc foo(blockToRender: static string): string =
      compileTemplateStr("""
        BUG
        {% block first %}first{{self.inner}}block{% endblock %}
        {% block second %}second{{self.inner}}block{% endblock %}
        {% block inner %} inner {% endblock %}
        BUG
      """, blockToRender = blockToRender)

    check "first inner block" == foo("first")
    check "second inner block" == foo("second")


  test "compileTemplateStr simple with var":
    proc foo(ii: int, blockToRender: static string): string =
      compileTemplateStr("""
        BUG
        {% block first %}first{{self.inner}}block{% endblock %}
        {% block second %}second{{self.inner}}block{% endblock %}
        {% block inner %} {{ii}} {% endblock %}
        BUG
      """, blockToRender = blockToRender)

    check "first 1337 block" == foo(1337, "first")
    check "second 1337 block" == foo(1337, "second")




  test "compileTemplateFile simple":
    proc foo(fileToRender: static string, blockToRender: static string): string =
      compileTemplateFile(fileToRender, blockToRender = blockToRender, baseDir = getScriptDir())
    check "title from index" == foo("fragments/index.nimja", "title") ## TODO test this error message!
    check "content from index" == foo("fragments/index.nimja", "content") ## TODO test this error message!

    check "title to replace" == foo("fragments/base.nimja", "title") ## TODO test this error message!
    check "content to replace" == foo("fragments/base.nimja", "content") ## TODO test this error message!


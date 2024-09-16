discard """
  joinable: false
"""
import ../../src/nimja
import unittest, strutils, strformat

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


  test "compileTemplateStr with inner block":
    proc foo(blockToRender: static string): string =
      compileTemplateStr("""
        BUG
        {% block first %}first{% block inner%} inner {% endblock %}block{% endblock %}
        BUG
      """, blockToRender = blockToRender)
    check "first inner block" == foo("first")
    check " inner " == foo("inner")


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
    check "title from index" == foo("fragments/index.nimja", "title") 
    check "content from index" == foo("fragments/index.nimja", "content") 
    check "title to replace" == foo("fragments/base.nimja", "title") 
    check "content to replace" == foo("fragments/base.nimja", "content") 


  test "importnimja simple":
    proc foo(fileToRender: static string, blockToRender: static string): string =
      compileTemplateStr("{% importnimja " & fileToRender & " " & blockToRender & " %}", 
        baseDir = getScriptDir())
      result = result.strip()
    check "title from index" == foo("fragments/index.nimja", "title")
    check "content from index" == foo("fragments/index.nimja", "content")
    check "title to replace" == foo("fragments/base.nimja", "title")
    check "content to replace" == foo("fragments/base.nimja", "content")


  test "tmpls":
    check "title" == tmpls("bug{%block title%}title{%endblock%}bug", 
      baseDir = getScriptDir(), blockToRender = "title")

    check "titleinner" == tmpls("bug{%block title%}title{%block inner%}inner{%endblock%}{%endblock%}bug", 
      baseDir = getScriptDir(), blockToRender = "title")

    check "inner" == tmpls("bug{%block title%}title{%block inner%}inner{%endblock%}{%endblock%}bug", 
      baseDir = getScriptDir(), blockToRender = "inner")

  test "tmplf":
    check "title from index" == tmplf("fragments/index.nimja", blockToRender = "title", baseDir = getScriptDir()) 
    check "content from index" == tmplf("fragments/index.nimja", blockToRender = "content", baseDir = getScriptDir()) 
    check "title to replace" == tmplf("fragments/base.nimja", blockToRender = "title", baseDir = getScriptDir()) 
    check "content to replace" == tmplf("fragments/base.nimja", blockToRender = "content", baseDir = getScriptDir())      
    


# suite "fragments stolen":

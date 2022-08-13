import nimja
import dom
import strutils

proc renderIndex(): string =
  compileTemplateStr("{%extends master.html%}{%block content%}{% for idx in 0..10 %}foo baa baz<br>{%endfor%}{%endblock%}")

proc renderItem(item: string): string =
  compileTemplateStr("{%extends master.html%}{%block content%}{% for idx in 0..10 %}ITEMA {{idx}} {{item}}<br>{%endfor%}{%endblock%}")

proc renderArticle(article: int): string =
  compileTemplateStr("""
    {%extends master.html%}{%block content%}
      {% if article == 1 %}
        {% importnimja article1.html %}
      {% elif article == 2 %}
        {% importnimja article2.html %}
      {% endif %}
    {%endblock%}
  """)

proc render*(str: string) {.exportc.} =
  document.body.innerHTML = str

proc index*() {.exportc.} =
  render(renderIndex())

proc article*(article: int) {.exportc.} =
  render(renderArticle(article))

proc itemA(item: cstring) {.exportc.} =
  render(renderItem($item))

index()
# For reference how jinja2 handles stuff.
import jinja2
templateLoader = jinja2.FileSystemLoader(searchpath="./")
templateEnv = jinja2.Environment(loader=templateLoader)


def render(path):
  template = templateEnv.get_template(path)
  return template.render()

def renderStr(str):
  template = templateEnv.from_string(str)
  return template.render(foo = "FOO")

# print(renderStr("""
# <li>
#   {#- foo -#}
#   {%- if true %}
#     {{ foo }}
#   {%- endif %}
# </li>
# """))

print(renderStr("""
<li>
  {%- if true %}
    {{- -3 }}
  {%- endif %}
</li>
"""))


# print(render("doubleExtends/inner.nwt"))
# print(render("doubleExtends/outer.nwt"))
# print(render("doubleExtends/base.nwt"))



# print(render("doubleExtends/innerSkipOne.nwt"))
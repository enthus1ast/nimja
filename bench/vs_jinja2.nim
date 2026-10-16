## Same template as vs_jinja2.py, rendered many times.
## Build: nim c -d:release -d:danger bench/vs_jinja2.nim   (run with `nimble jinja` too)
import nimja
import std/[times, strformat, os, strutils]

type
  User = object
    name: string
    age: int

const src = "<html><head><title>{{ title }}</title></head><body>{% if loggedIn %}<p>Welcome!</p>{% else %}<p>Please log in.</p>{% endif %}<ul>{% for user in users %}<li>{{ user.name }} ({{ user.age }})</li>{% endfor %}</ul></body></html>"

proc renderPage(title: string, users: seq[User], loggedIn: bool): string =
  compileTemplateStr(src)

let users = @[
  User(name: "Katja", age: 32),
  User(name: "David", age: 32),
  User(name: "Foo", age: 21),
  User(name: "Bar", age: 44),
]

let n = if paramCount() >= 1: parseInt(paramStr(1)) else: 1_000_000

var s: string
for i in 0 ..< 1000: # warmup
  s = renderPage("Users", users, true)
writeFile("/tmp/nimja_out.html", s)

let start = epochTime()
for i in 0 ..< n:
  s = renderPage("Users", users, true)
let elapsed = epochTime() - start

echo &"nimja  {n} renders in {elapsed:.4f}s = {elapsed / float(n) * 1e6:.3f} us/render = {float(n) / elapsed:.0f} renders/s"

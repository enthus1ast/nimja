#!/usr/bin/env python3
"""Same template as vs_jinja2.nim, rendered many times with Jinja2.

Run with jinja2 on the path, e.g.:
    nix-shell -p python3Packages.jinja2 --run "python3 bench/vs_jinja2.py 100000"
"""
import sys
import time

from jinja2 import Template

src = "<html><head><title>{{ title }}</title></head><body>{% if loggedIn %}<p>Welcome!</p>{% else %}<p>Please log in.</p>{% endif %}<ul>{% for user in users %}<li>{{ user.name }} ({{ user.age }})</li>{% endfor %}</ul></body></html>"

t = Template(src)
users = [
    {"name": "Katja", "age": 32},
    {"name": "David", "age": 32},
    {"name": "Foo", "age": 21},
    {"name": "Bar", "age": 44},
]

n = int(sys.argv[1]) if len(sys.argv) > 1 else 100_000

s = ""
for _ in range(1000):  # warmup
    s = t.render(title="Users", users=users, loggedIn=True)
with open("/tmp/jinja2_out.html", "w") as f:
    f.write(s)

start = time.perf_counter()
for _ in range(n):
    s = t.render(title="Users", users=users, loggedIn=True)
elapsed = time.perf_counter() - start

print(f"jinja2 {n} renders in {elapsed:.4f}s = {elapsed / n * 1e6:.3f} us/render = {n / elapsed:.0f} renders/s")

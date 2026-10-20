# Nimja vs Jinja2

`vs_jinja2.nim` and `vs_jinja2.py` render the **same** template with the same
data; both parse/compile the template once and time only `render`, after a
warmup. The rendered HTML is written to `/tmp/nimja_out.html` and
`/tmp/jinja2_out.html` and is byte-identical.

```bash
nimble jinja
# or
nim c -r -d:release bench/vs_jinja2.nim 2000000
nix-shell -p python3Packages.jinja2 --run "python3 bench/vs_jinja2.py 200000"
```

Template (static markup, `if`/`else`, a `for` loop, attribute access):

```twig
<html><head><title>{{ title }}</title></head><body>{% if loggedIn %}<p>Welcome!</p>{% else %}<p>Please log in.</p>{% endif %}<ul>{% for user in users %}<li>{{ user.name }} ({{ user.age }})</li>{% endfor %}</ul></body></html>
```

Nim 2.2.4 `-d:release`, Python 3.13 + Jinja2 3.1.6, `taskset -c 0`
(min of 3 runs, 4 users):

| | time / render | renders / s |
|---|---:|---:|
| **nimja** | ~0.234 us | ~4.28 M |
| jinja2 | ~11.82 us | ~0.084 M |

≈ **50x faster** (the exact factor depends on the template; more text and more
loop iterations widen the gap further because there is no interpreter loop).

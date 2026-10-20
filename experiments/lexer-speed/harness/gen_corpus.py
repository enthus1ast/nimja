#!/usr/bin/env python3
"""Generate the FIXED lexer benchmark corpus.

The corpus is checked in (harness/corpus/corpus.txt) and its sha256 is listed in
harness/FIXED.sha256. Do NOT regenerate it while a run is in progress -- the
metric is only comparable against an identical corpus. Regeneration is only
needed if someone deliberately starts a new experiment generation.

Composition (in this order, repeated until >= TARGET bytes):
  * every *.nimja file in the repo (real templates, all syntax features)
  * readme.md (doc prose: mostly static text, plus embedded template examples)
  * playground/bigmaster.nimja (the largest real template)
  * a deterministic synthetic block that stresses variables, comments, evals,
    strings, escapes, triple-quoted strings and unicode.

The synthetic block only uses real, documented template syntax, so lexing it
must be correct.
"""

import hashlib
import os
import sys

TARGET = 2_000_000
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(HERE, "corpus", "corpus.txt")


def real_part() -> str:
    parts = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in {".git", "nimcache", ".work"})
        for name in sorted(filenames):
            if name.endswith(".nimja"):
                with open(os.path.join(dirpath, name), encoding="utf-8") as f:
                    parts.append(f.read())
    for rel in ("readme.md", "playground/bigmaster.nimja"):
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            parts.append(f.read())
    # `\n` separators keep the concatenation from creating bogus delimiters
    return "\n".join(parts)


SYNTH = r'''
<div class="row">
  <h1>{{ page.title }}</h1>
  <p>{{ user.name }} ({{ user.email }}) joined {{ user.joinedAt }}</p>
  {% for item in items %}
    <li id="item-{{ loop.index }}" class="item {% if item.active %}active{% else %}inactive{% endif %}">{{ item.label }}</li>
  {% endfor %}
  {% if loggedIn and not user.banned %}
    <a href="/profile/{{ user.id }}">profile</a>
  {% endif %}
  {# a short comment #}
  {# a longer comment, with {braces} and %percent% and #hash# inside #}
  {% when defined(foo) %}
    <span>{{ "quoted \"string\" with braces { }" }}</span>
  {% end %}
  <p>{{ "triple: " & """raw " inner " text""" }}</p>
  <p>Escaped delimiters: \{\{ not a variable \}\} and \{% not a statement %\}.</p>
  <p>Unicode: äöü ß ñ 日本語 🎉 — «guillemets»</p>
  <p>{{ cycle("odd", "even") }} {{ truncate(text, 30) }} {{ slugify("Foo Bar!") }}</p>
  {% raw %}<script>if (a < b && c > d) { x = "{"; }</script>{% endraw %}
</div>
'''


def main() -> int:
    blob = real_part() + "\n" + SYNTH
    out = []
    size = 0
    while size < TARGET:
        out.append(blob)
        size += len(blob.encode("utf-8"))
    data = "".join(out).encode("utf-8")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(data)
    print(f"wrote {OUT}: {len(data)} bytes")
    print(f"sha256 {hashlib.sha256(data).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

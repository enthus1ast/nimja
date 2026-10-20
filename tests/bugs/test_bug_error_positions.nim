discard """
  joinable: false
"""
include ../../src/nimja/parser
import unittest

## Verifies the compile-time position attached to template errors
## (`NimjaError.line`/`col` are 0 based). The macro layer turns these into
## `file(line, col)` compiler diagnostics; calling `compile` directly lets us
## assert the exact position.

suite "template error positions":
  test "missing endif reports the `if` tag":
    try:
      discard compile("#heading\n{% if true %}\nmissing endif\n")
      check false
    except NimjaError as e:
      check e.line == 1
      check e.col == 0

  test "unexpected tag reports its own position":
    try:
      discard compile("xx{% else %}")
      check false
    except NimjaError as e:
      check e.line == 0
      check e.col == 2

  test "duplicated block reports the position of the duplicate":
    try:
      discard compile("{% block t %}a{% endblock %}\n{% block t %}b{% endblock %}")
      check false
    except NimjaError as e:
      check e.line == 1
      check e.col == 0

  test "position survives a multi line triple quoted string":
    # the newline inside the string must not shift the following line
    try:
      discard compile("{{ \"\"\"a\nb\"\"\" }}\n{% else %}")
      check false
    except NimjaError as e:
      check e.line == 2
      check e.col == 0

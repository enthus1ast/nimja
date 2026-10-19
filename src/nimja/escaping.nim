## HTML escaping helpers.
##
## These back the `|e` / `|safe` filters and the `escapeWith` option of the
## template compilation procs. Escaping is **idempotent**: an `HTMLSafeStr`
## (e.g. produced by `safe`) is never escaped twice.

type
  HTMLSafeStr* = distinct string
    ## a string that is already HTML escaped / safe to insert into HTML

func escapeHtmlChars(s: string): string =
  ## escapes the HTML special characters `& < > " '`
  var hasSpecial = false
  for ch in s:
    case ch
    of '&', '<', '>', '"', '\'':
      hasSpecial = true
      break
    else:
      discard
  if not hasSpecial:
    # Nothing to escape: keep the string instead of allocating a copy.
    return s
  result = newStringOfCap(s.len + s.len shr 2)
  for ch in s:
    case ch
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add ch

proc `$`*(str: HTMLSafeStr): string {.borrow.}
proc add*(x: var string, str: HTMLSafeStr) {.borrow.}

proc htmlEscape*[T](x: T): HTMLSafeStr =
  ## Converts `x` to a string and escapes HTML special characters
  ## (to prevent XSS). Idempotent: an `HTMLSafeStr` is returned unchanged.
  ##
  ## .. code-block:: Nim
  ##  {{ "something<b>bold</b>" | htmlEscape }}
  when x is HTMLSafeStr:
    x
  else:
    escapeHtmlChars($x).HTMLSafeStr

proc safe*[T](x: T): HTMLSafeStr =
  ## Marks `x` as already escaped / safe to insert into HTML.
  ## Useful with `escapeWith = htmlEscape`.
  ##
  ## .. code-block:: Nim
  ##  {{ "something&lt;b&gt;bold&lt;/b&gt;" | safe }}
  HTMLSafeStr($x)

proc e*[T](x: T): HTMLSafeStr =
  ## `htmlEscape` alias, idempotent like `htmlEscape`.
  ##
  ## .. code-block:: Nim
  ##  {{ "something<b>bold</b>" | e }}
  htmlEscape(x)

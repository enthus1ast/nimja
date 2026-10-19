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
  for c in s:
    case c
    of '&', '<', '>', '"', '\'':
      hasSpecial = true
      break
    else: discard
  if not hasSpecial:
    return s
  # Single pass, buffer write.
  result = newStringOfCap(s.len * 3)
  result.setLen(s.len * 3)
  var p = 0
  for c in s:
    case c
    of '&': result[p]='&';inc p;result[p]='a';inc p;result[p]='m';inc p;result[p]='p';inc p;result[p]=';';inc p
    of '<': result[p]='&';inc p;result[p]='l';inc p;result[p]='t';inc p;result[p]=';';inc p
    of '>': result[p]='&';inc p;result[p]='g';inc p;result[p]='t';inc p;result[p]=';';inc p
    of '"': result[p]='&';inc p;result[p]='q';inc p;result[p]='u';inc p;result[p]='o';inc p;result[p]='t';inc p;result[p]=';';inc p
    of '\'': result[p]='&';inc p;result[p]='#';inc p;result[p]='3';inc p;result[p]='9';inc p;result[p]=';';inc p
    else: result[p]=c;inc p
  result.setLen(p)

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

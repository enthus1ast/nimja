## HTML escaping helpers.
##
## These back the `|e` / `|safe` filters and the `escapeWith` option of the
## template compilation procs. Escaping is **idempotent**: an `HTMLSafeStr`
## (e.g. produced by `safe`) is never escaped twice.
##
## The scan for characters that need escaping is vectorized with SSE2 when
## compiling for x86 (SSE2 is part of the x86-64 baseline, so no runtime check
## is needed); other targets run the same algorithm with a scalar scan.

when defined(js) or defined(nimscript):
  const htmlEscapeSimd = false
elif (defined(amd64) or defined(i386)):
  import nimsimd/sse2
  import std/bitops
  const htmlEscapeSimd = true
else:
  const htmlEscapeSimd = false

type
  HTMLSafeStr* = distinct string
    ## a string that is already HTML escaped / safe to insert into HTML

const htmlEscExtra: array[128, int8] = block:
  ## how many extra bytes a character needs when escaped
  var a: array[128, int8]
  a[int('&')] = 4  # -> &amp;
  a[int('<')] = 3  # -> &lt;
  a[int('>')] = 3  # -> &gt;
  a[int('"')] = 5  # -> &quot;
  a[int('\'')] = 4 # -> &#39;
  a

func escExtra(c: char): int {.inline.} =
  if uint8(c) < 128'u8: int(htmlEscExtra[int(c)]) else: 0

const
  ampExtra = 4
  ltExtra = 3
  gtExtra = 3
  quotExtra = 5
  aposExtra = 4

when htmlEscapeSimd:
  func specialMask(v: M128i): int32 {.inline.} =
    ## bit `i` is set when byte `i` is one of `& < > " '`
    mm_movemask_epi8(
      mm_or_si128(
        mm_or_si128(mm_cmpeq_epi8(v, mm_set1_epi8('&')),
                    mm_cmpeq_epi8(v, mm_set1_epi8('<'))),
        mm_or_si128(
          mm_or_si128(mm_cmpeq_epi8(v, mm_set1_epi8('>')),
                      mm_cmpeq_epi8(v, mm_set1_epi8('"'))),
          mm_cmpeq_epi8(v, mm_set1_epi8('\'')))))

  func extrasOf(v: M128i): int {.inline.} =
    ## exact number of bytes escaping the 16 bytes in `v` adds
    ampExtra * countSetBits(mm_movemask_epi8(mm_cmpeq_epi8(v, mm_set1_epi8('&')))) +
    ltExtra * countSetBits(mm_movemask_epi8(mm_cmpeq_epi8(v, mm_set1_epi8('<')))) +
    gtExtra * countSetBits(mm_movemask_epi8(mm_cmpeq_epi8(v, mm_set1_epi8('>')))) +
    quotExtra * countSetBits(mm_movemask_epi8(mm_cmpeq_epi8(v, mm_set1_epi8('"')))) +
    aposExtra * countSetBits(mm_movemask_epi8(mm_cmpeq_epi8(v, mm_set1_epi8('\''))))

template writeEscaped(c: char) =
  ## writes one escaped character at `result[p]`; a template (not a proc) so
  ## that `p` stays in a register instead of being written back through a
  ## pointer on every character
  case c
  of '&': result[p]='&';inc p;result[p]='a';inc p;result[p]='m';inc p;result[p]='p';inc p;result[p]=';';inc p
  of '<': result[p]='&';inc p;result[p]='l';inc p;result[p]='t';inc p;result[p]=';';inc p
  of '>': result[p]='&';inc p;result[p]='g';inc p;result[p]='t';inc p;result[p]=';';inc p
  of '"': result[p]='&';inc p;result[p]='q';inc p;result[p]='u';inc p;result[p]='o';inc p;result[p]='t';inc p;result[p]=';';inc p
  of '\'': result[p]='&';inc p;result[p]='#';inc p;result[p]='3';inc p;result[p]='9';inc p;result[p]=';';inc p
  else: discard

template writeChar(c: char) =
  ## copies or escapes one character (single dispatch, no table lookup)
  case c
  of '&', '<', '>', '"', '\'':
    writeEscaped(c)
  else:
    result[p] = c
    inc p

func lengthEscaped(s: string): int =
  ## how many bytes escaping `s` adds; 0 means "nothing to escape"
  let n = s.len
  var i = 0
  when htmlEscapeSimd:
    # counting the specials per character class is cheaper than walking the
    # string byte by byte, especially for long strings
    while i + 16 <= n:
      let space = specialMask(mm_loadu_si128(unsafeAddr s[i]))
      if space == 0:
        i += 16
      else:
        result += extrasOf(mm_loadu_si128(unsafeAddr s[i]))
        i += 16
  while i < n:
    result += escExtra(s[i])
    inc i

func escapeExact(s: string, extra: int): string =
  ## escapes `s` into a buffer of exactly `s.len + extra` bytes
  let n = s.len
  result = newStringOfCap(n + extra)
  result.setLen(n + extra)
  var i = 0
  var p = 0
  when htmlEscapeSimd:
    while i + 16 <= n:
      if specialMask(mm_loadu_si128(unsafeAddr s[i])) == 0:
        copyMem(addr result[p], unsafeAddr s[i], 16)
        p += 16
        i += 16
      else:
        let stop = i + 16
        while i < stop:
          writeChar(s[i])
          inc i
  while i < n:
    writeChar(s[i])
    inc i
  result.setLen(p)

func escapeHtmlChars(s: string): string =
  ## escapes the HTML special characters `& < > " '`
  let n = s.len
  if n == 0: return s
  if n <= 32:
    # short values (the common case in templates): one pass, with a buffer
    # that is large enough for the worst case (every char is `"`, 6 bytes)
    var hasSpecial = false
    for c in s:
      if escExtra(c) != 0:
        hasSpecial = true
        break
    if not hasSpecial: return s
    let cap = n * 6
    result = newStringOfCap(cap)
    result.setLen(cap)
    var p = 0
    for c in s:
      writeChar(c)
    result.setLen(p)
    return
  let extra = lengthEscaped(s)
  if extra == 0: return s
  escapeExact(s, extra)

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

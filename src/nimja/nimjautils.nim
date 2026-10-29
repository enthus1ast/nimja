import std/options
export options
import sharedhelper
import escaping
export escaping
import std/strutils
import std/parseutils
import unidecode
import std/[os, mimetypes, uri, tables, macros, enumerate]
export uri

type
  Loop*[T] = object
    index*: int ## which element (start from 1)
    index0*: int ## which elemen (start from 0)
    first*: bool ## if this is the first loop iteration
    last*: bool ## if this is the last loop iteration
    length*: int ## the length of the seq, (same as mySeq.len())
    revindex0*: int ## which element, counted from the end (last one is 0)
    revindex*: int ## which element, counted from the end (last one is 1)
    when not defined(js) and not defined(nimscript):
      src: ptr UncheckedArray[T] ## the iterated data (borrowed, never freed here)
    else:
      src: pointer ## JS/NimScript: unused placeholder
  Loopable*[T] = concept x {.explain.}
    x.len() is int
    x[int] is T
    x.items is T

const allowedCharsInSlug* = Letters + Digits

func addSlice(dst: var string, src: string, a, b: int) {.inline.} =
  ## Appends `src[a..b]` (inclusive) with a single bulk copy. Cheaper than
  ## appending char by char, and cheaper than slicing (which allocates).
  if b < a: return
  let k = b - a + 1
  let old = dst.len
  dst.setLen(old + k)
  when defined(js) or defined(nimscript):
    ## JS/NimScript backend: no copyMem / unsafeAddr — copy byte-by-byte
    var j = a
    while j <= b:
      dst.add(src[j])
      inc j
  else:
    copyMem(addr dst[old], unsafeAddr src[a], k)

func previtem*[T](loop: Loop[T]): Option[T] {.inline.} =
  ## the item of the previous loop iteration (if any)
  when defined(js) or defined(nimscript):
    ## JS/NimScript: src is unused, return none
    none(T)
  else:
    if loop.index0 > 0 and loop.src != nil:
      some(loop.src[loop.index0 - 1])
    else:
      none(T)

func nextitem*[T](loop: Loop[T]): Option[T] {.inline.} =
  ## the item of the next loop iteration (if any)
  when defined(js) or defined(nimscript):
    ## JS/NimScript: src is unused, return none
    none(T)
  else:
    if loop.index0 + 1 < loop.length and loop.src != nil:
      some(loop.src[loop.index0 + 1])
    else:
      none(T)

proc cycleItems*[T](loop: Loop, elems: openArray[T]): T {.inline.} =
  if elems.len == 0:
    raise newException(ValueError, "nimja: cycle() called with an empty sequence")
  return elems[loop.index0 mod elems.len]

macro cycle*(loop, elems: untyped): untyped =
  ## within a loop you can cycle through elements:
  ##
  ## .. code-block:: Nim
  ##   {% for (loop, row) in rows.loop() %}
  ##       <li class="{{ loop.cycle(@["odd", "even"]) }}">{{ row }}</li>
  ##   {% endfor %}
  ##
  ## A literal `@[...]` argument is rewritten to an array literal: same values,
  ## but the array lives on the stack instead of allocating a fresh `seq` on
  ## every single call.
  var elems2 = elems
  if elems2.kind == nnkPrefix and elems2.len == 2 and
     elems2[0].kind in {nnkIdent, nnkSym} and eqIdent(elems2[0], "@") and
     elems2[1].kind == nnkBracket and elems2[1].len > 0:
    elems2 = elems2[1]
  result = newCall(bindSym"cycleItems", loop, elems2)

# iterator loop*[T](a: Loopable[T]): tuple[loop: Loop[T], val: T] = # TODO cannot access fields in the template; why?
iterator loop*[T](a: openArray[T]): tuple[loop: Loop[T], val: T] {.inline.} =
  ## yields a `Loop` object with every item.
  ## Inside the loop body you have access to the following fields.
  ##
  ## .. code-block:: Nim
  ##   {% for (loop, row) in rows.loop() %}
  ##       {{ loop.index0 }}
  ##       {{ loop.index }}
  ##       {{ loop.revindex0 }}
  ##       {{ loop.revindex }}
  ##       {{ loop.length }}
  ##       {% if loop.first %}The first item{% endif %}
  ##       {% if loop.last %}The last item{% endif %}
  ##       {% if loop.previtem.isSome() %}{{ loop.previtem.get() }}{% endif %}
  ##       {% if loop.nextitem.isSome() %}{{ loop.nextitem.get() }}{% endif %}
  ##       <li class="{{ loop.cycle(@["odd", "even"]) }}">{{row}}</li>
  ##   {% endfor %}
  ##
  # TODO this should be a concept, but does not work why?
  # however, the element you iterate over must match the Concept `Loopable`.
  # This means you can propably not use loop() with an iterator, since they do not have a `len()` and `[]`
  let n = a.len()
  when defined(js) or defined(nimscript):
    ## JS/NimScript backend: no unsafeAddr / UncheckedArray — src is nil
    var lp = Loop[T](length: n, src: cast[pointer](nil))
  else:
    let src = if n > 0: cast[ptr UncheckedArray[T]](unsafeAddr a[0]) else: nil
    var lp = Loop[T](length: n, src: src)
  var idx = 0
  for each in a:
    lp.index = idx + 1
    lp.index0 = idx
    lp.first = idx == 0
    lp.last = idx == n - 1
    lp.revindex0 = n - (idx + 1)
    lp.revindex = n - idx
    inc idx
    yield (lp, each)


template `~`*(aa, bb: untyped): string =
  ## ~ (tilde)
  ## Converts all operands into strings and concatenates them.
  ## like: `$aa & $bb`
  ##
  ## `{{ "Hello " ~ name ~ "!" }}` would return (assuming name is set to 'Nim') Hello Nim!.
  $aa & $bb

proc includeRaw*(path: string): string =
  ## Includes the content of a file literally without any parsing
  ## Good for documentation etc..
  ## This includes on runtime!
  ## For a compile time include see `includeRawStatic`
  result = read(path)

proc includeRawStatic*(path: static string): string =
  ## Includes the content of a file literally without any parsing
  ## Good for documentation etc..
  ## This includes at compiletime!
  ## For a runtimetime include see `includeRaw`
  const cont = staticRead(path)
  return cont

proc includeStaticAsDataurl*(path: static string, mimeOverride: static string = ""): string =
  ## Includes a ressource as a dataurl on compile time.
  const mimedb = mimes.toTable()
  const (_, _, ext) = splitFile(path)
  const mime =
    if mimeOverride == "":
      mimedb.getOrDefault(ext.strip(chars = {'.'}))
    else:
      mimeOverride
  const content = staticRead(path).getDataUri(mime)
  return content

proc truncate*(str: string, num: Natural, preserveWords = true, suf = "..."): string =
  ## truncates a string to "num" characters.
  ## when the string was truncated it appends the `suf` to the text.
  ## if `preserveWords` is true it will not cut words in half but
  ## the output string could be shorter than `num` characters.
  if str.len <= num: return str
  if preserveWords == false:
    return str[0 .. num - 1] & suf
  else:
    result = newStringOfCap(num + suf.len)
    # the same words `splitWhitespace` would produce, but without allocating a
    # seq and a string per word on every call
    let n = str.len
    var i = 0
    var idx = 0
    while i < n:
      while i < n and str[i] in Whitespace: inc i
      if i >= n: break
      let wStart = i
      while i < n and str[i] notin Whitespace: inc i
      let wLen = i - wStart
      if result.len + wLen <= num:
        if idx != 0:
          result.add " "
        addSlice(result, str, wStart, i - 1)
        inc idx
      else:
        result.add suf
        break


func nl2br*(str: string, keepNl = true): string =
  ## Converts all \n to <br>
  ## if keepNL == true: newlines will still be in the output.
  result = newStringOfCap(str.len)
  let n = str.len
  var start = 0
  while start < n:
    let found = str.find('\n', start)
    if found < 0:
      addSlice(result, str, start, n - 1)
      break
    addSlice(result, str, start, found - 1)
    result.add("<br>")
    if keepNl:
      result.add '\n'
    start = found + 1

func spaceless*(str: string): string =
  ## Removes unneeded whitespaces between html tags,
  ## warning, this is NOT smart.
  ## So it will destroy `<textarea>` and `<pre>` content!
  result = newStringOfCap(str.len)
  let n = str.len
  var i = 0
  var start = 0 # start of the pending run that can be copied in bulk
  var intag = false
  while i < n:
    let ch = str[i]
    if intag:
      if ch == '>':
        addSlice(result, str, start, i) # the whole tag, '>' included
        intag = false
        start = i + 1
      inc i
    elif ch == '<':
      addSlice(result, str, start, i - 1) # text before the tag
      inc i
      intag = true
      start = i - 1
    elif ch in Whitespace:
      addSlice(result, str, start, i - 1)
      var j = i + 1
      while j < n and str[j] in Whitespace: inc j
      if j - i > 1:
        result.add ' ' # only one whitespace for multiple ones
      else:
        result.add ch
      i = j
      start = i
    else:
      inc i
  if not intag:
    addSlice(result, str, start, n - 1)

proc slugify*(str: string, seperator = "-", allowedChars = allowedCharsInSlug): string =
  ## converts any string to an url friendly one.
  ## Removes any special chars and replaces non ASCII runes to their ASCII representation.
  # Fast path: pure ASCII skips unidecode entirely
  var cleaned: string
  var isAscii = true
  for c in str:
    if c < '\x01' or c > '\x7f':
      isAscii = false
      break
  # `toLowerAscii` is enough in *both* branches: the input is ASCII here, and
  # `unidecode` only ever produces ASCII. `strutils.toLower` is re-exported
  # from `std/unicode` and decodes runes (~10x slower for nothing).
  #
  # Strip, lower-case and filter in a single pass: `strip()` and `toLowerAscii()`
  # each allocated a temporary string before.
  let src = if isAscii: str else: str.unidecode()
  var first = 0
  var last = src.len - 1
  while first <= last and src[first] in Whitespace: inc first
  while last >= first and src[last] in Whitespace: dec last
  result = newStringOfCap(last - first + 1)
  for i in first .. last:
    let ch = toLowerAscii(src[i])
    if ch in Whitespace:
      result.add seperator
    elif ch in allowedChars:
      result.add ch

template `?`*(con, body: untyped): untyped =
  ## shorthand `if` eg. for toggling html classes.
  ##
  ## .. code-block:: Nim
  ##  <input class="{% ?isDisabled: "disable" %}">
  ##
  when compiles(result.add body): # TODO find a better way to test for iterator
    if con: result.add body
  else:
    if con: yield body

macro `|`*(aa, bb: untyped): untyped =
  ## 'filter' alias, often used in other template engines.
  ## `a | b` is an alias to `a.b`.
  ## This enables syntax like this:
  ##
  ## .. code-block:: Nim
  ##  {{ "foo baa baz" | slugify()}}
  ##
  result = newStmtList()
  let ss = "(" & (repr aa) & "." & (repr bb) & ")"
  result.add parseStmt(ss)

when isMainModule and false:
  for loop, elem in @["foo", "baa", "baz"].loop():
    if loop.first:
      echo "<ul>"
    echo "<li class=\"" & loop.cycle(@["odd", "even"]) & "\">",loop.index0, " ", loop.index, " " , elem, " ", loop.revindex, " ", loop.revindex0, "</li>", loop.cycle(["1", "2","foo"])
    if loop.last:
      echo "</ul>"

  import nimja
  proc foo(rows: seq[string]): string =
    compileTemplateStr("""
{% for (loop, row) in rows.loop() %}
  <div class="row">
    {{row}}
    {{ loop.index0 }}
    {{ loop.index }}
    {{ loop.revindex0 }}
    {{ loop.revindex }}
    {{ loop.length }}
    {% if loop.first %}The first item{% endif %}
    {% if loop.last %}The last item{% endif %}
    {% if loop.previtem.isSome() %}{{ loop.previtem.get() }}{% endif %}
    {% if loop.nextitem.isSome() %}{{ loop.nextitem.get() }}{% endif %}
    <li class="{{ loop.cycle(@["odd", "even"]) }}">{{row}}</li>
  </div>
{% endfor %}
    """)
  echo foo(@["foo","baa", "baz"])

when isMainModule:
  import nimja
  proc testTilde(name: string): string =
    compileTemplateStr("""{{ "Hello " ~ name ~ "!" }}""")
  assert testTilde("Nim") == "Hello Nim!"

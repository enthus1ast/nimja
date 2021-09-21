import options
export options
import sharedhelper
import strutils
import parseutils

type
  Loop*[T] = object
    index*: int ## which element (start from 1)
    index0*: int ## which elemen (start from 0)
    first*: bool ## if this is the first loop iteration
    last*: bool ## if this is the last loop iteration
    previtem*: Option[T] ## get the item from the last loop iteration
    nextitem*: Option[T] ## get the item from the next loop iteration
    length*: int ## the length of the seq, (same as mySeq.len())
    revindex0*: int ## which element, counted from the end (last one is 0)
    revindex*: int ## which element, counted from the end (last one is 1)
  Loopable*[T] = concept x {.explain.}
    x.len() is int
    x[int] is T
    x.items is T


proc cycle*[T](loop: Loop, elems: openArray[T]): T =
  ## within a loop you can cycle through elements:
  ##
  ## .. code-block:: Nim
  ##   {% for (loop, row) in rows.loop() %}
  ##       <li class="{{ loop.cycle(@["odd", "even"]) }}">{{ row }}</li>
  ##   {% endfor %}
  ##
  return elems[loop.index0 mod elems.len]

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
  var idx = 0
  for each in a:
    var loop = Loop[T]()
    loop.index = idx + 1
    loop.index0 = idx
    loop.first = idx == 0
    loop.last = idx == a.len() - 1
    if not loop.first:
      loop.previtem = some(a[idx - 1])
    if not loop.last:
      loop.nextitem = some(a[idx + 1])
    loop.length = a.len()
    loop.revindex0 = a.len() - (idx + 1)
    loop.revindex = a.len() - idx
    idx.inc
    yield (loop, each)


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
  result = read(path)

proc truncate*(str: string, num: Natural, preserveWords = true, suf = "..."): string =
  ## truncates a string to "num" characters.
  ## when the string was truncated it appends the `suf` to the text.
  ## if `preserveWords` is true it will not cut words in half but
  ## the output string could be shorter than `num` characters.
  if str.len <= num: return str
  if preserveWords == false:
    return str[0 .. num - 1] & suf
  else:
    for idx, word in str.splitWhitespace.pairs():
      if result.len + (word.len) <= num:
        if idx != 0:
          result.add " "
        result.add word
      else:
        result.add suf
        break

func nl2br*(str: string, keepNl = true): string =
  ## Converts all \n to <br>
  ## if keepNL == true: newlines will still be in the output.
  for ch in str:
    if ch == '\n':
      result.add("<br>")
      if keepNl:
        result.add(ch)
    else:
      result.add ch

func spaceless*(str: string): string =
  var pos = 0
  var intag = false
  while pos < str.len:
    let ch = str[pos]
    if ch == '<': intag = true
    if ch == '>': intag = false
    if intag: result.add ch
    else:
      let skipped = str.skipWhile(Whitespace, pos)
      if skipped > 1:
        result.add ' ' # only one whitespace for multiple ones
        pos.inc skipped - 1
      else: result.add ch
    pos.inc


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
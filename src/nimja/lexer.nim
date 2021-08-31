import strformat, strutils

type
  NwtTokenKind* = enum # TODO rename to TokenKind or TokenType
    NwtNone,
    NwtString, # a string block
    NwtComment,
    NwtEval,
    NwtVariable,
  Token* = object
    kind*: NwtTokenKind
    value*: string # the value
    line*: int
    charinbuf*: int

proc debugPrint(buffer: string, pos: int) =
  let pointPos = if pos - 1 < 0: 0 else: pos - 1
  echo buffer
  echo '-'.repeat(pointPos) & "^"

template thisIs(chr: char): bool =
  (not (pos > buf.len)) and (buf[pos] == chr)

template nextIs(chr: char): bool =
  (not (pos + 1 >= buf.len)) and (buf[pos + 1] == chr)

template lastIs(chr: char): bool =
  (not (pos - 1 >= buf.len)) and (not(pos - 1 < 0)) and (buf[pos - 1] == chr)

template isEof(): bool =
  pos >= buf.len

template handleNl() =
  if thisIs('\n'): line.inc

type
  LexReturn = tuple[good: bool, token: Token]

template nomatch() =
  return (false, Token())

proc lexerMsg(str: string, line: int) =
  echo fmt"[{line}] {str}"

func lexInnerStr(buf: string, pos: var int): string =
  result &= buf[pos] # the '"'
  pos.inc # skip '"'
  var escape = false
  while pos < buf.len:
    let ch = buf[pos]
    if escape:
      result &= ch
      escape = false
    elif ch == '\\':
      escape = true
    elif ch == '"':
      result &= '"'
      break
    else:
      result &= ch
    pos.inc

template store() =
  result.token.value &= ch

proc lexBetween(buf: string, pos: var int, line: var int, bstart = "{{", bend = "}}", kind: NwtTokenKind): LexReturn =
  if not (thisIs(bstart[0]) and nextIs(bstart[1])): nomatch
  pos.inc # skip this '{'
  pos.inc # skip next '{'
  result.good = true
  result.token = Token(kind: kind)
  result.token.line = line
  # pos += skipWhitespace(buf, pos) # is stripped later...
  var escaped = false
  var endchar = false
  while pos < buf.len:
    let ch = buf[pos]
    handleNl
    if escaped:
      store
      escaped = false
      pos.inc
      continue
    elif thisIs('\\'):
      escaped = true
    elif thisIs(bend[0]) and nextIs(bend[1]):
      endchar = true
      pos.inc # skip next '}'
      break
    elif thisIs('"'):
      result.token.value &= lexInnerStr(buf, pos)
    else:
      store
    pos.inc
  result.token.value = result.token.value.strip()
  if isEof and endchar == false:
    lexerMsg(fmt"Endchar expected but not found... '{bend}'", line)

proc lexVar(buf: string, pos: var int, line: var int): LexReturn =
  return lexBetween(buf, pos, line, bstart = "{{", bend = "}}", NwtVariable)

proc lexComment(buf: string, pos: var int, line: var int): LexReturn =
  return lexBetween(buf, pos, line, bstart = "{#", bend = "#}", NwtComment)

proc lexEval(buf: string, pos: var int, line: var int): LexReturn =
  return lexBetween(buf, pos, line, bstart = "{%", bend = "%}", NwtEval)

proc lexStr(buf: string, pos: var int, line: var int): LexReturn =
  result.good = true
  result.token = Token(kind: NwtString)
  result.token.line = line
  while pos < buf.len:
    let ch = buf[pos]
    handleNl
    if thisIs('{') and (nextIs('#') or nextIs('%') or nextIs('{')):
      pos.dec # go back to last; for next lexer
      break
    else:
      store
    pos.inc


iterator lex*(buf: string): Token =
  var line = 0
  var pos = 0
  var lexReturn: LexReturn
  while pos < buf.len:
    var ch = buf[pos]
    handleNl
    lexReturn = lexVar(buf, pos, line)
    if lexReturn.good:
      yield lexReturn.token
      pos.inc
      continue

    lexReturn = lexComment(buf, pos, line)
    if lexReturn.good:
      yield lexReturn.token
      pos.inc
      continue

    lexReturn = lexEval(buf, pos, line)
    if lexReturn.good:
      yield lexReturn.token
      pos.inc
      continue

    lexReturn = lexStr(buf, pos, line)
    if lexReturn.good:
      yield lexReturn.token
      pos.inc
      continue




when isMainModule:
  import sequtils
  import unittest
  suite "newLexer":
    setup:
      var pos = 0
    test "only var":
      check toSeq(lex("{{foo}}")) == @[Token(kind: NwtVariable, value: "foo", line: 0)]
      # echo toSeq(lex("{{foo}}"))[0].value
    test "only var escaped":
      # echo toSeq(lex("""{{foo\}\}}}"""))[0].value
      check toSeq(lex("""{{foo\}\}}}""")) == @[Token(kind: NwtVariable, value: """foo}}""", line: 0)]
    test "only var escaped 1":
      check toSeq(lex("""{{foo\}}}""")) == @[Token(kind: NwtVariable, value: """foo}""", line: 0)]
    test "string var":
      check toSeq(lex("{{\"foo\"}}")) == @[Token(kind: NwtVariable, value: "\"foo\"", line: 0)]
    # test "string var escaped":
      # check toSeq(lex("""{{\"fo\\\"o\"}}""")) == @[Token(kind: NwtVariable, value: "\"fo\\\"o\"", line: 0)]

    test "only comment1":
      check toSeq(lex("{#foo#}")) == @[Token(kind: NwtComment, value: "foo", line: 0)]
    test "only comment2":
      check toSeq(lex("{#fo#o#}")) == @[Token(kind: NwtComment, value: "fo#o", line: 0)]
    test "only comment3":
      check toSeq(lex("""{#fo\#}o#}""")) == @[Token(kind: NwtComment, value: """fo#}o""", line: 0)]
    #   echo toSeq(lex("""{#fo\#}o#}"""))[0].value
    # test "str as var":
      # echo toSeq(lex("""{{"foo"}}"""))

    # test "str":
    #   echo toSeq(lex("foo"))
  var pos = 0
  echo toSeq(lex("""foo {# fjo {% aasd %} #} {%%} ba baz"""))

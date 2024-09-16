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
    value*: string
    line*: int
    charinbuf*: int

proc debugPrint(buffer: string, pos: int) =
  let pointPos = if pos - 1 < 0: 0 else: pos - 1
  echo buffer
  echo '-'.repeat(pointPos) & "^"

template thisIs(chr: char): bool =
  (not (pos > buf.len)) and (buf[pos] == chr)

template nextIs(chr: char, cnt = 1): bool =
  (not (pos + cnt >= buf.len)) and (buf[pos + cnt] == chr)

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
  while pos < buf.len:
    let ch = buf[pos]
    if ch == '"':
      result &= '"'
      break
    else:
      result &= ch
    pos.inc

func lexInnerStrTripple(buf: string, pos: var int): string =
  result &= buf[pos .. pos + 2] # the '"""'
  pos.inc # skip '"'
  pos.inc # skip '"'
  pos.inc # skip '"'
  while pos < buf.len:
    let ch = buf[pos]
    if ch == '"' and nextIs('"') and nextIs('"', 2):
      result &= '"'
      result &= '"'
      result &= '"'
      pos.inc 2
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
    elif thisIs('"') and nextIs('"') and nextIs('"', 2):
      # echo "Triple quotes"
      result.token.value &= lexInnerStrTripple(buf, pos)
    elif thisIs('"'):
      result.token.value &= lexInnerStr(buf, pos)
    else:
      store
    pos.inc
  result.token.value = result.token.value.strip() ## TODO strip later? is this even correct for strings?
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
  ## Lexes the string in `buf` yields `Token`
  var line = 0
  var pos = 0
  var lexReturn: LexReturn
  while pos < buf.len:
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
    test "only var escaped":
      check toSeq(lex("""{{foo\}\}}}""")) == @[Token(kind: NwtVariable, value: """foo}}""", line: 0)]
    test "only var escaped 1":
      check toSeq(lex("""{{foo\}}}""")) == @[Token(kind: NwtVariable, value: """foo}""", line: 0)]
    test "string var":
      check toSeq(lex("{{\"foo\"}}")) == @[Token(kind: NwtVariable, value: "\"foo\"", line: 0)]
    test "only comment1":
      check toSeq(lex("{#foo#}")) == @[Token(kind: NwtComment, value: "foo", line: 0)]
    test "only comment2":
      check toSeq(lex("{#fo#o#}")) == @[Token(kind: NwtComment, value: "fo#o", line: 0)]
    test "only comment3":
      check toSeq(lex("""{#fo\#}o#}""")) == @[Token(kind: NwtComment, value: """fo#}o""", line: 0)]
    test "triple quotes":
      echo toSeq(lex("""{{\"\"\"foo\"\"\"}}"""))

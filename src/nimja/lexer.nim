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
    line*: int  ## 0 based line of the token start
    col*: int   ## 0 based column (byte offset from the line start) of the token start

proc debugPrint(buffer: string, pos: int) =
  let pointPos = if pos - 1 < 0: 0 else: pos - 1
  echo buffer
  echo '-'.repeat(pointPos) & "^"

template thisIs(chr: char): bool =
  (not (pos >= buf.len)) and (buf[pos] == chr)

template nextIs(chr: char, cnt = 1): bool =
  (not (pos + cnt >= buf.len)) and (buf[pos + cnt] == chr)

template lastIs(chr: char): bool =
  (not (pos - 1 >= buf.len)) and (not(pos - 1 < 0)) and (buf[pos - 1] == chr)

template isEof(): bool =
  pos >= buf.len

template handleNl() =
  ## remember line starts so the column can be derived from `pos`
  if thisIs('\n'):
    line.inc
    lineStart = pos + 1

type
  LexReturn = tuple[good: bool, token: Token]

template nomatch() =
  return (false, Token())

proc lexerMsg(str: string, line: int) =
  echo fmt"[{line}] {str}"

func lexInnerStr(buf: string, pos, line, lineStart: var int): string =
  result &= buf[pos] # the '"'
  pos.inc # skip '"'
  while pos < buf.len:
    let ch = buf[pos]
    handleNl
    if ch == '\\' and pos + 1 < buf.len:
      # keep the escape sequence (eg.: '\"') intact, do not
      # mistake the escaped quote for the closing quote
      result &= ch
      result &= buf[pos + 1]
      pos.inc 2
      continue
    if ch == '"':
      result &= '"'
      break
    else:
      result &= ch
    pos.inc

func lexInnerStrTripple(buf: string, pos, line, lineStart: var int,
                        closed: var bool): string =
  closed = false
  result &= buf[pos .. pos + 2] # the '"""'
  pos.inc # skip '"'
  pos.inc # skip '"'
  pos.inc # skip '"'
  while pos < buf.len:
    let ch = buf[pos]
    handleNl
    if ch == '"' and nextIs('"') and nextIs('"', 2):
      result &= '"'
      result &= '"'
      result &= '"'
      pos.inc 2
      closed = true
      break
    else:
      result &= ch
    pos.inc

template store() =
  result.token.value &= ch

proc lexBetween(buf: string, pos, line, lineStart: var int, bstart = "{{",
                bend = "}}", kind: NwtTokenKind): LexReturn =
  if not (thisIs(bstart[0]) and nextIs(bstart[1])): nomatch
  let startLine = line
  let startCol = pos - lineStart
  pos.inc # skip this '{'
  pos.inc # skip next '{'
  result.good = true
  result.token = Token(kind: kind)
  result.token.line = startLine
  result.token.col = startCol
  var escaped = false
  var endchar = false
  while pos < buf.len:
    let ch = buf[pos]
    if ch == '\n':
      line.inc
      lineStart = pos + 1
    if escaped:
      result.token.value &= ch
      escaped = false
    elif ch == '\\':
      escaped = true
    elif ch == bend[0] and pos + 1 < buf.len and buf[pos + 1] == bend[1]:
      endchar = true
      pos.inc
      break
    elif ch == '"' and pos + 1 < buf.len and buf[pos + 1] == '"' and pos + 2 < buf.len and buf[pos + 2] == '"':
      var closed = false
      result.token.value &= lexInnerStrTripple(buf, pos, line, lineStart, closed)
      if not closed:
        raise newException(ValueError,
          fmt"Unterminated triple quoted string in block at line {line + 1}")
    elif ch == '"':
      result.token.value &= lexInnerStr(buf, pos, line, lineStart)
    else:
      result.token.value &= ch
    pos.inc
  # Cheaper strip: manually find first/last non-ws chars, only copy when needed.
  var lo = 0
  while lo < result.token.value.len and result.token.value[lo] in {' ', '\t', '\n', '\r', '\f', '\v'}:
    inc lo
  var hi = result.token.value.len - 1
  while hi >= lo and result.token.value[hi] in {' ', '\t', '\n', '\r', '\f', '\v'}:
    dec hi
  if lo > hi:
    result.token.value = ""
  elif lo > 0 or hi < result.token.value.len - 1:
    result.token.value = result.token.value[lo .. hi]
  if isEof and endchar == false:
    lexerMsg(fmt"Endchar expected but not found... '{bend}'", line + 1)

proc lexVar(buf: string, pos, line, lineStart: var int): LexReturn =
  return lexBetween(buf, pos, line, lineStart, bstart = "{{", bend = "}}", NwtVariable)

proc lexComment(buf: string, pos, line, lineStart: var int): LexReturn =
  return lexBetween(buf, pos, line, lineStart, bstart = "{#", bend = "#}", NwtComment)

proc lexEval(buf: string, pos, line, lineStart: var int): LexReturn =
  return lexBetween(buf, pos, line, lineStart, bstart = "{%", bend = "%}", NwtEval)

proc lexStr(buf: string, pos, line, lineStart: var int): LexReturn =
  result.good = true
  result.token = Token(kind: NwtString)
  result.token.line = line
  result.token.col = pos - lineStart
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
  var lineStart = 0
  var pos = 0
  var lexReturn: LexReturn
  while pos < buf.len:
    # Dispatch on the two-character opener once instead of probing every
    # delimiter kind with a call.
    if pos + 1 < buf.len and buf[pos] == '{':
      case buf[pos + 1]
      of '{': lexReturn = lexVar(buf, pos, line, lineStart)
      of '#': lexReturn = lexComment(buf, pos, line, lineStart)
      of '%': lexReturn = lexEval(buf, pos, line, lineStart)
      else: lexReturn = (false, Token())
      if lexReturn.good:
        yield lexReturn.token
        pos.inc
        continue

    lexReturn = lexStr(buf, pos, line, lineStart)
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
    test "lines and columns":
      #           0123456789
      let src = "ab\ncd {{x}}\nfg{% y %}"
      let toks = toSeq(lex(src))
      check toks.len == 4
      check (toks[0].line, toks[0].col) == (0, 0)
      check (toks[1].line, toks[1].col) == (1, 3) # {{x}}
      check (toks[3].line, toks[3].col) == (2, 2) # {% y %}

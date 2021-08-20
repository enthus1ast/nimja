import parseutils
type
  LexerTemplateSyntaxError* = ref object of ValueError
  NimjaLexerTokenKind* = enum
    NlString,
    NlComment,
    NlEval,
    NlVariable,
  Token* = object
    kind*: NimjaLexerTokenKind
    value*: string
    line*: int
    # character*: int

template thisIs(chr: char): bool =
  (not (pos > buf.len)) and (buf[pos] == chr)

template nextIs(chr: char): bool =
  (not (pos + 1 > buf.len)) and (buf[pos + 1] == chr)

template lastIs(chr: char): bool =
  (not (pos - 1 > buf.len)) and (not(pos - 1 < 0)) and (buf[pos - 1] == chr)

type  LexReturn = tuple[good: bool, token: Token]

converter toBool(lexReturn: LexReturn): bool =
  return lexReturn.good

converter toToken(lexReturn: LexReturn): Token =
  return lexReturn.token

template yieldIfGood(lexReturn: LexReturn) =
  if lexReturn: yield lexReturn

template nomatch() =
  return (false, Token())


func lexStr(buf: string, pos: var int): LexReturn =
  discard

func lexInnerStr(buf: string, pos: var int): string =
  result &= buf[pos] # the '"'
  pos.inc # skip '"'
  while pos < buf.len:
    let ch = buf[pos]
    if ch == '\\':
      pos.inc
      result &= buf[pos]
    elif ch == '"':
      result &= '"'
      break
    else:
      result &= ch
    pos.inc



func lexVar(buf: string, pos: var int): LexReturn =
  if thisIs('{') and nextIs('{'):
    result.good = true
    result.token = Token(kind: NlVariable)

    if thisIs('{') and nextIs('{'):
      pos.inc # skip this '{'
      pos.inc # skip next '{'
    else:
      nomatch

    pos += skipWhitespace(buf, pos)

    while pos < buf.len:
      let ch = buf[pos]
      debugEcho ch
      if (not lastIs('\\')) and thisIs('}') and nextIs('}'):
        pos.inc # skip next '}'
        break
      elif thisIs('"'):
        result.token.value &= lexInnerStr(buf, pos)
      else:
        result.token.value &= ch
      pos.inc
  else:
    return (false, Token())
  debugEcho result

iterator lex*(buf: string, pos: var int): Token =
  var line = 0
  while pos < buf.len:
    var ch = buf[pos]
    if ch == '\n':
      line.inc
    # yieldIfGood lexStr(buf, pos)
    yieldIfGood lexVar(buf, pos)
    pos.inc


when isMainModule:
  import sequtils
  import unittest
  suite "nexLexer":
    setup:
      var pos = 0

    test "only var":
      check toSeq(lex("{{foo}}", pos))

    test "str as var":
      echo toSeq(lex("""{{"foo"}}""", pos))

    test "str":
      echo toSeq(lex("foo", pos))

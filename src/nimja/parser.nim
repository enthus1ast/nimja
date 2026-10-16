import strutils, macros, sequtils, parseutils, os, tables, sets, deques, std/enumerate
import lexer, sharedhelper, escaping
export escaping
export getScriptDir
export os

type
  NimjaError* = ref object of ValueError
    ## a template error with the position inside the template
    file*: string
    line*: int
    col*: int

# special case `self` variable, used to reference blocks
const specialSelf {.strdefine.} = "self."

type Path = string
type
  NwtNodeKind = enum
    NStr, NIf, NElif, NElse, NWhile, NFor,
    NVariable, NEval, NBlock,
    NExtends, NProc, NFunc, NWhen,
    NCase, NCaseOf, NCaseElse, NScope, NScopeEnd
  NwtNode = object
    line: int  ## source position (compile time only, never emitted)
    col: int
    file: string
    case kind: NwtNodeKind
    of NStr:
      strBody: string
    of NIf, NWhen:
      ifStmt: string
      nnThen: seq[NwtNode]
      nnElif: seq[NwtNode]
      nnElse: seq[NwtNode]
    of NElif:
      elifStmt: string
      elifBody: seq[NwtNode]
    of NWhile:
      whileStmt: string
      whileBody: seq[NwtNode]
    of NFor:
      forStmt: string
      forBody: seq[NwtNode]
    of NVariable:
      variableBody: string
    of NEval:
      evalBody: string
    of NBlock:
      blockName: string
      blockBody: seq[NwtNode]
    of NExtends:
      extendsPath: string
    of NProc:
      procHeader: string
      procBody: seq[NwtNode]
    of NCase:
      caseStmt: string
      nnCaseOf: seq[NwtNode]
      nnCaseElse: seq[NwtNode]
    of NCaseOf:
      caseOfStmt: string
      caseOfBody: seq[NwtNode]
    of NCaseElse:
      caseElseBody: seq[NwtNode]
    of NScope:
      scopeName: string
      scopeBody: seq[NwtNode]
    else: discard

# First step nodes
type
  FsNodeKind = enum
    FsIf, FsStr, FsEval, FsElse, FsElif, FsEndif, FsFor,
    FsEndfor, FsVariable, FsWhile, FsEndWhile, FsImport,
    FsBlock, FsEndBlock, FsExtends, FsProc, FsEndProc,
    FsFunc, FsEndFunc, FsEnd, FsWhen, FsEndWhen,
    FsCase, FsOf, FsEndCase, FsScope, FsEndScope
  FSNode = object
    kind: FsNodeKind
    value: string
    stripPre: bool
    stripPost: bool
    line: int
    col: int
    file: string

var cacheNwtNode {.compileTime.}: Table[string, seq[NwtNode]] ## a cache for rendered NwtNodes
var cacheNwtNodeFile {.compileTime.}: Table[Path, string] ## a cache for content of a path
var nwtIter {.compileTime.} = false
var nwtVarname {.compileTime.}: string
var nwtBaseDir {.compileTime.}: string 
var nwtStrProc {.compileTime.}: NimNode ## stringifies values: `$`, `htmlEscape` or a custom proc
var nwtEscaping {.compileTime.} = false ## true when a real escaping proc is active
var nwtFallbackFile {.compileTime.}: string ## entry source file, for string templates
var nwtFallbackLine {.compileTime.}: int
var nwtFallbackCol {.compileTime.}: int
var blocks {.compileTime.} : Table[string, seq[NwtNode]]
var guessedStringLen {.compileTime.} = 0

proc templateError(msg, file: string, line, col: int) {.noreturn.} =
  ## Raises a located template error. `line`/`col` are 0 based.
  ## This is caught at the macro boundary and re-reported with
  ## `macros.error(msg, node)` so the compiler points at the template
  ## (`file(line, col)`), while `compile(...)` called directly still raises
  ## a catchable `ValueError`. Zero runtime cost: compile time only.
  raise NimjaError(msg: msg, file: file, line: line, col: col)

proc reportNimjaError(e: NimjaError) {.noreturn.} =
  ## Converts a raised `NimjaError` into a compiler error located at the
  ## template position (or the macro call site for string templates).
  let n = newIdentNode("templateError")
  var msg = e.msg
  if e.file.len > 0:
    n.setLineInfo(e.file, e.line + 1, e.col)
  else:
    msg = msg & " (template line " & $(e.line + 1) & ", col " & $(e.col + 1) & ")"
    if nwtFallbackFile.len > 0:
      try:
        n.setLineInfo(nwtFallbackFile, nwtFallbackLine, nwtFallbackCol)
      except CatchableError:
        discard
  error(msg, n)

proc setEscapeProc(escapeWith: NimNode) =
  ## chooses the proc used to stringify `{{ ... }}` values: a user supplied
  ## `escapeWith` (e.g. `htmlEscape` for HTML) or `$` when none is given.
  if escapeWith.kind != nnkNilLit:
    nwtStrProc = escapeWith
    nwtEscaping = true
  else:
    nwtStrProc = newIdentNode("$")
    nwtEscaping = false

when defined(dumpNwtAstPretty):
  import json
  proc pretty*(nwtNodes: seq[NwtNode]): string {.compileTime.} =
    (%* nwtNodes).pretty()

# Forward declaration
proc parseSecondStep(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc parseSecondStepOne(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc astAst(tokens: seq[NwtNode]): seq[NimNode]
proc compile(str: string, blockToRender: string = "", file: string = ""): seq[NwtNode]
proc astAstOne(token: NwtNode): NimNode

func staticLen(nodes: seq[NwtNode]): int =
  ## Sums the length of all static strings in `nodes`; used to preallocate the
  ## output. Operates on the final tree, so it is independent of the
  ## parse/cache path (avoids `newStringOfCap(0)` on cache hits).
  for node in nodes:
    case node.kind
    of NStr: result += node.strBody.len
    of NIf, NWhen:
      result += staticLen(node.nnThen)
      result += staticLen(node.nnElif)
      result += staticLen(node.nnElse)
    of NElif: result += staticLen(node.elifBody)
    of NWhile: result += staticLen(node.whileBody)
    of NFor: result += staticLen(node.forBody)
    of NBlock: result += staticLen(node.blockBody)
    of NCase:
      result += staticLen(node.nnCaseOf)
      result += staticLen(node.nnCaseElse)
    of NCaseOf: result += staticLen(node.caseOfBody)
    of NCaseElse: result += staticLen(node.caseElseBody)
    of NScope: result += staticLen(node.scopeBody)
    of NProc: result += staticLen(node.procBody)
    else: discard

func atPos(n: NwtNode, fs: FSNode): NwtNode =
  ## copies the compile-time source position of an `FSNode` onto an `NwtNode`
  result = n
  result.line = fs.line
  result.col = fs.col
  result.file = fs.file

func tagName(k: FsNodeKind): string {.inline.} =
  ## user facing tag name, derived from the enum member name:
  ## `FsIf` -> "if", `FsEndBlock` -> "endblock"
  result = ($k)[2 .. ^1].toLowerAscii()

func mustStrip(token: Token): tuple[token: Token, stripPre, stripPost: bool] =
  ## identifies if whitespaceControl chars are in the string,
  ## clear the string of these, but fill `stripPre` and `stripPost` accordingly
  if token.kind == NwtString: return (token, false, false) # if a string we do not touch it
  result.token = token
  result.stripPre = false
  result.stripPost = false
  if result.token.value.len != 0:
    if result.token.value[0] == '-':
      result.stripPre = true
      result.token.value = result.token.value[1 .. ^1] # remove the first
    if result.token.value.len != 0 and result.token.value[^1] == '-':
      result.stripPost = true
      result.token.value = result.token.value[0 .. ^2] # remove the last
  # if "-" was removed, lex() has not stripped it. Strip it here
  result.token.value = result.token.value.strip(true, true)

func splitStmt(str: string): tuple[pref: string, suf: string] {.inline.} =
  ## the prefix is normalized (transformed to lowercase)
  var pref = ""
  var pos = parseIdent(str, pref, 0)
  pos += str.skipWhitespace(pos)
  result.pref = toLowerAscii(pref)
  result.suf = str[pos..^1]

iterator findAll(fsns: seq[FsNode], kind: FsNodeKind | set[FsNodeKind]): FsNode =
  # Finds all FsNodes with given kind
  for fsn in fsns:
    when kind is FsNodeKind:
      if fsn.kind == kind: yield fsn
    else:
      if kind.contains(fsn.kind): yield fsn

proc parseFirstStep(tokens: seq[Token], file: string): seq[FSNode] =
  result = @[]
  for token in tokens:
    let (cleanedToken, stripPre, stripPost) = mustStrip(token)
    template addFs(k: FsNodeKind, v: string) =
      result.add FSNode(kind: k, value: v, stripPre: stripPre, stripPost: stripPost,
                        line: token.line, col: token.col, file: file)
    case token.kind
    of NwtEval:
      let (pref, suf) = splitStmt(cleanedToken.value)
      case pref
      of "if": addFs(FsIf, suf)
      of "elif": addFs(FsElif, suf)
      of "else": addFs(FsElse, suf)
      of "endif": addFs(FsEndif, suf)
      of "for": addFs(FsFor, suf)
      of "endfor": addFs(FsEndfor, suf)
      of "while": addFs(FsWhile, suf)
      of "endwhile": addFs(FsEndWhile, suf)
      of "importnwt", "importnimja": addFs(FsImport, suf)
      of "block": addFs(FsBlock, suf)
      of "endblock": addFs(FsEndBlock, suf)
      of "extends": addFs(FsExtends, suf)
      of "proc": addFs(FsProc, suf)
      of "endproc": addFs(FsEndProc, suf)
      of "macro": addFs(FsProc, suf)
      of "endmacro": addFs(FsEndProc, suf)
      of "func": addFs(FsFunc, suf)
      of "endfunc": addFs(FsEndFunc, suf)
      of "end": addFs(FsEnd, suf)
      of "when": addFs(FsWhen, suf)
      of "endwhen": addFs(FsEndWhen, suf)
      of "case": addFs(FsCase, suf)
      of "of": addFs(FsOf, suf)
      of "endcase": addFs(FsEndCase, suf)
      of "scope": addFs(FsScope, suf)
      of "endscope": addFs(FsEndScope, suf)
      else:
        addFs(FsEval, cleanedToken.value)
    of NwtString: addFs(FsStr, token.value)
    of NwtVariable: addFs(FsVariable, cleanedToken.value)
    of NwtComment:
      # keep whitespace control chars of comments (eg.: `{#- foo -#}`),
      # but drop the comment text itself
      addFs(FsStr, "")
    else: echo "[FS] Not catched:", token

proc consumeBlock(fsTokens: seq[FSNode], pos: var int, endTags: set[FsNodeKind]): seq[NwtNode] =
  while pos < fsTokens.len:
    let fsToken = fsTokens[pos]
    if endTags.contains(fsToken.kind):
      break
    else:
      result.add parseSecondStepOne(fsTokens, pos)

proc parseSsCase(fsTokens: seq[FsNode], pos: var int): NwtNode =
  while pos < fsTokens.len:
    let elem = fsTokens[pos]
    case elem.kind
    of FsCase:
      pos.inc
      result = NwtNode(kind: NwtNodeKind.NCase).atPos(elem)
      result.caseStmt = elem.value
    of FsOf:
      pos.inc
      result.nnCaseOf.add NwtNode(kind: NCaseOf, caseOfStmt: elem.value).atPos(elem)
      result.nnCaseOf[^1].caseOfBody.add consumeBlock(fsTokens, pos, {FsOf, FsElse, FsEndCase})
    of FsElse:
      pos.inc
      result.nnCaseElse.add consumeBlock(fsTokens, pos, {FsEndCase})
    of FsEndCase:
      pos.inc
      break
    else:
      templateError("should not happen: " & tagName(elem.kind), elem.file, elem.line, elem.col)

proc parseSsIf(fsTokens: seq[FsNode], pos: var int): NwtNode =
  while pos < fsTokens.len:
    let elem = fsTokens[pos]
    case elem.kind
    of FsIf:
      pos.inc
      result = NwtNode(kind: NwtNodeKind.NIf).atPos(elem)
      result.ifStmt = elem.value
      result.nnThen.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndif})
    of FsElif:
      pos.inc
      result.nnElif.add NwtNode(kind: NElif, elifStmt: elem.value).atPos(elem)
      result.nnElif[^1].elifBody.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndif} )
    of FsElse:
      pos.inc
      result.nnElse.add consumeBlock(fsTokens, pos, {FsEndif})
    of FsEndif:
      pos.inc
      break
    else:
      templateError("should not happen: " & tagName(elem.kind), elem.file, elem.line, elem.col)

proc parseSsWhen(fsTokens: seq[FsNode], pos: var int): NwtNode =
  while pos < fsTokens.len:
    let elem = fsTokens[pos]
    case elem.kind
    of FsWhen:
      pos.inc
      result = NwtNode(kind: NwtNodeKind.NWhen).atPos(elem)
      result.ifStmt = elem.value
      result.nnThen.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndWhen})
    of FsElif:
      pos.inc
      result.nnElif.add NwtNode(kind: NElif, elifStmt: elem.value).atPos(elem)
      result.nnElif[^1].elifBody.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndWhen} )
    of FsElse:
      pos.inc
      result.nnElse.add consumeBlock(fsTokens, pos, {FsEndWhen})
    of FsEndWhen:
      pos.inc
      break
    else:
      templateError("should not happen: " & tagName(elem.kind), elem.file, elem.line, elem.col)

proc parseSsWhile(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the while that we got called about
  result = NwtNode(kind: NwtNodeKind.NWhile).atPos(elem)
  result.whileStmt = elem.value
  pos.inc # skip FsWhile
  result.whileBody = consumeBlock(fsTokens, pos, {FsEndWhile})
  pos.inc # skip FsEndWhile

proc parseSsFor(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the for that we got called about
  result = NwtNode(kind: NwtNodeKind.NFor).atPos(elem)
  result.forStmt = elem.value
  pos.inc #skip FsFor
  result.forBody = consumeBlock(fsTokens, pos, {FsEndFor})
  pos.inc # skip FsEndBlock

proc parseSsBlock(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  let blockName = elem.value
  result = NwtNode(kind: NwtNodeKind.NBlock, blockName: blockName).atPos(elem)
  pos.inc # skip FsBlock
  result.blockBody = consumeBlock(fsTokens, pos, {FsEndBlock})
  pos.inc # skip FsEndBlock

proc parseSsProc(fsTokens: seq[FsNode], pos: var int, kind: NwtNodeKind = NProc): NwtNode =
  var elem: FsNode = fsTokens[pos]
  result = NwtNode(kind: NwtNodeKind.NProc).atPos(elem)
  result.procHeader = elem.value
  pos.inc # skip FsProc
  if kind == NProc:
    result.procBody = consumeBlock(fsTokens, pos, {FsEnd, FsEndProc})
  elif kind == NFunc:
    result.procBody = consumeBlock(fsTokens, pos, {FsEnd, FsEndFunc})
  pos.inc # skip FsEnd

proc parseSsExtends(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  let extendsPath = elem.value.strip(true, true, {'"'})
  pos.inc # skip FsExtends
  return NwtNode(kind: NExtends, extendsPath: extendsPath).atPos(elem)

proc parseSsScope(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  pos.inc # skip FsScope
  let parts = elem.value.split(" ")
  result = NwtNode(kind: NScope).atPos(elem)
  if parts.len >= 1:
    result.scopeName = parts[0].strip()
  result.scopeBody = consumeBlock(fsTokens, pos, {FsEnd, FsEndScope})
  pos.inc # skip FsEndScope

converter singleNwtNodeToSeq(nwtNode: NwtNode): seq[NwtNode] =
  return @[nwtNode]

proc importNimja(nodes: var seq[NwtNode], path: string, blockToRender = "") =
  var str = read(nwtBaseDir / path)
  nodes = compile(str, blockToRender, nwtBaseDir / path)

proc parseSecondStepOne(fsTokens: seq[FSNode], pos: var int): seq[NwtNode] =
    let fsToken = fsTokens[pos]

    case fsToken.kind
    # Complex Types
    of FsIf: return parseSsIf(fsTokens, pos)
    of FsWhen: return parseSsWhen(fsTokens, pos)

    of FsWhile: return parseSsWhile(fsTokens, pos)
    of FsFor: return parseSsFor(fsTokens, pos)
    of FsBlock: return parseSsBlock(fsTokens, pos)

    of FsCase: return parseSsCase(fsTokens, pos)
    of FsScope: return parseSsScope(fsTokens, pos)

    # Proc / Func / Macro are very similar
    of FsProc: return parseSsProc(fsTokens, pos, NProc)
    of FsFunc: return parseSsProc(fsTokens, pos, NFunc)

    # Simple Types
    of FsStr:
      pos.inc
      return NwtNode(kind: NStr, strBody: fsToken.value).atPos(fsToken)
    of FsVariable:
      pos.inc
      return NwtNode(kind: NVariable, variableBody: fsToken.value).atPos(fsToken)
    of FsEval:
      pos.inc
      return NwtNode(kind: NEval, evalBody: fsToken.value).atPos(fsToken)
    of FsExtends:
      return parseSsExtends(fsTokens, pos)
    of FsImport:
      pos.inc
      let parts = fsToken.value.split(" ")
      let (file, blockToRender) =
        if parts.len == 2:
          (
            parts[0].strip(true, true, {'"'}),
            parts[1].strip(true, true, {'"'})
          )
        else:
          (
            fsToken.value.strip(true, true, {'"'}),
            ""
          )
      importNimja(result, file, blockToRender = blockToRender)
    else:
      templateError("Unexpected template tag (unbalanced or misplaced): " &
        tagName(fsToken.kind) & " '" & fsToken.value & "'",
        fsToken.file, fsToken.line, fsToken.col)


proc parseSecondStep(fsTokens: seq[FSNode], pos: var int): seq[NwtNode] =
  while pos < fsTokens.len:
    result &= parseSecondStepOne(fsTokens, pos)

proc astVariable(token: NwtNode): NimNode =
  var varb: NimNode
  if token.variableBody.strip().len == 0:
    templateError("Empty variable body, a stray whitespace control char? `{{-}}`",
      token.file, token.line, token.col)
  # The "self." block insertion
  if token.variableBody.startsWith(specialSelf):
    let blockname = token.variableBody[specialSelf.len .. ^1]
    if blocks.hasKey(blockname):
      result = newStmtList()
      for token in blocks[blockname]:
        result.add astAstOne(token)
      return
    else:
      templateError("Undefined block referenced by `self.`: " & blockname,
        token.file, token.line, token.col)
  try:
    varb = parseStmt(token.variableBody)
  except:
    templateError("Cannot parse variable body: " & token.variableBody,
      token.file, token.line, token.col)
  return nnkStmtList.newTree(
    nnkInfix.newTree(
      newIdentNode("&="),
      newIdentNode(nwtVarname),
      newCall(
        nwtStrProc,
        varb
      )
    )
  )

proc astStr(token: NwtNode): NimNode =
  return nnkStmtList.newTree(
    nnkInfix.newTree(
      newIdentNode("&="),
      newIdentNode(nwtVarname),
      newStrLitNode(token.strBody)
    )
  )

proc astVariableIter(token: NwtNode): NimNode =
  var v = newCall(nwtStrProc, parseStmt(token.variableBody))
  if nwtEscaping:
    # `htmlEscape` returns HTMLSafeStr; iterators yield a plain string
    v = newCall(newIdentNode("$"), v)
  return nnkStmtList.newTree(
    nnkYieldStmt.newTree(
      v
    )
  )

func astStrIter(token: NwtNode): NimNode =
  return nnkStmtList.newTree(
    nnkYieldStmt.newTree(
      newStrLitNode(token.strBody)
    )
  )

func astEval(token: NwtNode): NimNode =
  try:
    return parseStmt(token.evalBody)
  except:
    templateError("Cannot parse eval body: " & token.evalBody,
      token.file, token.line, token.col)

proc astFor(token: NwtNode): NimNode =
  let easyFor = "for " & token.forStmt & ": discard" # `discard` to make a parsable construct
  result = parseStmt(easyFor)
  # the body is the last child of nnkForStmt; index 2 is only the body for a
  # single loop variable (`for k, v in pairs(x)` has an extra Ident, see #86)
  result[0][^1] = newStmtList(astAst(token.forBody)) # overwrite discard with real `for` body

proc astWhile(token: NwtNode): NimNode =
  nnkStmtList.newTree(
    nnkWhileStmt.newTree(
      parseStmt(token.whileStmt),
      nnkStmtList.newTree(
        astAst(token.whileBody)
      )
    )
  )


proc astIf(token: NwtNode): NimNode =
  ## generates code for `if` or `when`
  if token.kind == NIf:
    result = nnkIfStmt.newTree()
  elif token.kind == NWhen:
    result = nnkWhenStmt.newTree()

  # Add the then node
  result.add:
    nnkElifBranch.newTree(
      parseStmt(token.ifStmt),
      nnkStmtList.newTree(
        astAst(token.nnThen)
      )
    )

  ## Add the elif nodes
  for elifToken in token.nnElif:
    result.add:
      nnkElifBranch.newTree(
        parseStmt(elifToken.elifStmt),
        nnkStmtList.newTree(
          astAst(elifToken.elifBody)
        )
      )

  # Add the else node
  if token.nnElse.len > 0:
    result.add:
      nnkElse.newTree(
        nnkStmtList.newTree(
          astAst(token.nnElse)
        )
      )


proc astCase(token: NwtNode): NimNode =
  result = nnkCaseStmt.newTree()

  result.add parseStmt(token.caseStmt)

  for caseOfToken in token.nnCaseOf:
    result.add nnkOfBranch.newTree(
      parseStmt(caseOfToken.caseOfStmt),
      nnkStmtList.newTree(
        astAst(caseOfToken.caseOfBody)
      )
    )

  if token.nnCaseElse.len > 0:
    result.add nnkElse.newTree(
      nnkStmtList.newTree(
        astAst(token.nnCaseElse)
      )
    )


proc astProc(token: NwtNode, procStr = "proc"): NimNode =
  let easyProc =  procStr & " " & token.procHeader & " discard"
  result = parseStmt(easyProc) # dummy to build valid procBody
  result[0].body = nnkStmtList.newTree(
    astAst(token.procBody) # fill the proc body with content
  )

proc astScope(token: NwtNode): NimNode =
  result = newStmtList()
  var blockStmt = newNimNode(kind = nnkBlockStmt)
  if token.scopeName.len == 0:
    blockStmt.add newEmptyNode()
  else:
    blockStmt.add newIdentNode(token.scopeName)
  blockStmt.add newStmtList()
  blockStmt[1].add astAst(token.scopeBody)
  result.add blockStmt

proc astAstOne(token: NwtNode): NimNode =
  case token.kind
  of NVariable:
    if nwtIter: return astVariableIter(token)
    else: return astVariable(token)
  of NStr:
    if nwtIter: return astStrIter(token)
    else: return astStr(token)
  of NEval: return astEval(token)
  of NIf, NWhen: return astIf(token)
  of NFor: return astFor(token)
  of NWhile: return astWhile(token)
  of NExtends: return parseStmt("discard")
  of NBlock: return parseStmt("discard")
  of NProc: return astProc(token, procStr = "proc")
  of NFunc: return astProc(token, procStr = "func")
  of NCase: return astCase(token)
  of NScope: return astScope(token)
  else: templateError("cannot convert to ast: " & $token.kind,
                      token.file, token.line, token.col)

proc varExpr(body: string): NimNode =
  ## `parseStmt` wraps the expression in a `StmtList`; unwrap the single stmt
  result = parseStmt(body)
  if result.kind == nnkStmtList and result.len == 1:
    result = result[0]

proc isFoldableIdent(n: NwtNode): bool =
  ## Only simple identifiers are folded. `x is static` is broader than
  ## "is a const": a pure proc call is `static` too, and folding it would move
  ## its evaluation (and any side effect) to compile time.
  if n.kind != NVariable: return false
  if n.variableBody.startsWith(specialSelf): return false
  try:
    result = varExpr(n.variableBody).kind == nnkIdent
  except:
    result = false

proc stringifyVar(n: NwtNode): NimNode =
  ## `$var` or `escapeWith(var)`, as a plain string for `&` concatenation
  var varb: NimNode
  try:
    varb = varExpr(n.variableBody)
  except:
    templateError("Cannot parse variable body: " & n.variableBody,
                  n.file, n.line, n.col)
  result = newCall(nwtStrProc, varb)
  if nwtEscaping:
    result = newCall(newIdentNode("$"), result)

proc appendValue(value: NimNode): NimNode =
  if nwtIter:
    result = nnkYieldStmt.newTree(value)
  else:
    result = nnkStmtList.newTree(
      nnkInfix.newTree(newIdentNode("&="), newIdentNode(nwtVarname), value))

proc staticCond(n: NwtNode): NimNode =
  nnkInfix.newTree(newIdentNode("is"), varExpr(n.variableBody),
                   newIdentNode("static"))

proc astRun(run: seq[NwtNode]): NimNode =
  ## A maximal run of `NStr`/`NVariable`.
  ##
  ## * if every variable is a simple identifier, the first branch is
  ##   `when v1 is static and v2 is static ...:` so the compiler can constant
  ##   fold the whole run into a single string (issue #53);
  ## * the `else` branch folds each variable with the literal before it, so a
  ##   mixed run (some runtime variables) still saves one `add` per static
  ##   variable;
  ## * runs containing non identifiers use the normal per node code.
  var hasVar = false
  var foldable = true
  for n in run:
    if n.kind == NVariable:
      hasVar = true
      if not isFoldableIdent(n): foldable = false
  if not hasVar:
    return astAstOne(run[0])        # a single (already condensed) string
  if not foldable:
    var plain = newStmtList()
    for n in run: plain.add astAstOne(n)
    return plain
  # mixed-run fallback: fold each variable with the preceding literal
  var sep = newStmtList()
  var pending: NimNode = nil
  for n in run:
    case n.kind
    of NStr:
      let lit = newStrLitNode(n.strBody)
      pending = if pending.isNil: lit else:
        nnkInfix.newTree(newIdentNode("&"), pending, lit)
    of NVariable:
      let v = stringifyVar(n)
      if pending.isNil:
        sep.add appendValue(v)
      else:
        let merged = nnkInfix.newTree(newIdentNode("&"), pending, v)
        sep.add nnkWhenStmt.newTree(
          nnkElifBranch.newTree(staticCond(n), newStmtList(appendValue(merged))),
          nnkElse.newTree(newStmtList(appendValue(pending), appendValue(v))))
      pending = nil
    else: discard
  if not pending.isNil:
    sep.add appendValue(pending)
  # all-static: fold the complete run into one string
  var cond, folded: NimNode
  for n in run:
    case n.kind
    of NStr:
      let lit = newStrLitNode(n.strBody)
      folded = if folded.isNil: lit else:
        nnkInfix.newTree(newIdentNode("&"), folded, lit)
    of NVariable:
      let v = stringifyVar(n)
      folded = if folded.isNil: v else:
        nnkInfix.newTree(newIdentNode("&"), folded, v)
      cond = if cond.isNil: staticCond(n) else:
        nnkInfix.newTree(newIdentNode("and"), cond, staticCond(n))
    else: discard
  result = nnkWhenStmt.newTree(
    nnkElifBranch.newTree(cond, newStmtList(appendValue(folded))),
    nnkElse.newTree(sep))

proc astAst(tokens: seq[NwtNode]): seq[NimNode] =
  var i = 0
  while i < tokens.len:
    let k = tokens[i].kind
    let foldStart = k == NStr or (k == NVariable and isFoldableIdent(tokens[i]))
    if foldStart:
      var run: seq[NwtNode]
      while i < tokens.len and (tokens[i].kind == NStr or
            (tokens[i].kind == NVariable and isFoldableIdent(tokens[i]))):
        run.add tokens[i]
        i.inc
      result.add astRun(run)
    else:
      result.add astAstOne(tokens[i])
      i.inc

proc validExtend(secondsStepTokens: seq[NwtNode]): int =
  ## Scans if invalid tokens come before extend.
  ## If no extend was found `-1` is returned, else the position.
  ## Only Strings and comments are allowed to come before extend
  result = -1
  var validBeforeExtend = true
  for idx, secondStepToken in enumerate(secondsStepTokens):
    case secondStepToken.kind
    of NStr: discard
    of NExtends:
      result = idx
      break
    else:
      validBeforeExtend = false

  if (result > -1) and (not validBeforeExtend):
    let ext = secondsStepTokens[result]
    templateError("Invalid token(s) before {%extend%}",
      ext.file, ext.line, ext.col)

func condenseStrings(nodes: seq[FsNode]): seq[FsNode] =
  ## tries to combine multiple string assignments into one. Operates on `FsNodes` seq
  when defined(noCondenseStrings): return nodes
  var curStr = ""
  for node in nodes:
    case node.kind
    of FsStr:
      curStr &= node.value
    else:
      if curStr.len > 0:
        result.add FsNode(kind: FsStr, value: curStr)
      curStr = ""
      result.add node
  if curStr.len != 0:
    result.add FsNode(kind: FsStr, value: curStr)

func condenseStrings(nodes: seq[NwtNode]): seq[NwtNode] =
  ## tries to combine multiple string assignments into one. Operates on `NwtNode` ast
  when defined(noCondenseStrings): return nodes
  # return nodes
  var curStr = ""
  for node in nodes:
    case node.kind
    of NStr:
      curStr &= node.strBody
    else:
      if curStr.len > 0:
        result.add NwtNode(kind: NStr, strBody: curStr)
      curStr = ""
      result.add node
  if curStr.len != 0:
    result.add NwtNode(kind: NStr, strBody: curStr)

func whitespaceControl(nodes: seq[FsNode]): seq[FsNode] =
  ## Implements the handling of "WhitespaceControl" chars.
  ## eg.: {%- if true -%}
  var nextStrip = false
  for node in nodes:
    var mnode = node
    if nextStrip:
      if node.kind == FsStr:
        mnode.value = mnode.value.strip(true, false, {' ', '\n', '\c'})
      nextStrip = false
    if node.stripPre:
      if result.len > 0: # if there is something
        if result[^1].kind == FsStr:
          result[^1].value = result[^1].value.strip(false, true, {' ', '\n', '\c'}) # remove trailing whitespace from last node
    if node.stripPost:
      nextStrip = true
    if mnode.value.len == 0 and mnode.kind == FsStr:
      # skip empty string nodes entirely, if they're empty after stripping.
      continue
    result.add mnode

proc errorOnDuplicatedBlocks(fsns: seq[FSNode]) =
  ## Find duplicated blocks
  # TODO give context and line
  var blocknames: HashSet[string]
  for fsnode in fsns.findAll(FsBlock):
    if blocknames.contains(fsnode.value):
      templateError("found duplicated block: " & fsnode.value,
        fsnode.file, fsnode.line, fsnode.col)
    else:
      blocknames.incl fsnode.value

proc errorOnDuplicatedExtends(fsns: seq[FSNode]) =
  ## Find duplicated extends
  # TODO give context and line
  var foundExtends = false
  for fsnode in fsns.findAll(FsExtends):
    if foundExtends == true:
      templateError("found multiple extends", fsnode.file, fsnode.line, fsnode.col)
    else:
      foundExtends = true

proc errorOnUnevenBlocks(fsns: seq[FSNode]) =
  ## Find and report uneven/lonely blocks at the offending tag
  var stack: seq[FSNode]
  template matchingEnd(k: FsNodeKind): string =
    case k
    of FsIf: "endif"
    of FsFor: "endfor"
    of FsWhile: "endwhile"
    of FsWhen: "endwhen"
    of FsBlock: "endblock"
    else: "end"
  for fsnode in fsns.findAll({FsIf, FsEndif, FsFor, FsEndfor, FsWhile, FsEndWhile,
                               FsWhen, FsEndWhen, FsBlock, FsEndBlock}):
    case fsnode.kind
    of FsIf, FsFor, FsWhile, FsWhen, FsBlock:
      stack.add fsnode
    of FsEndif, FsEndfor, FsEndWhile, FsEndWhen, FsEndBlock:
      let opener =
        case fsnode.kind
        of FsEndif: FsIf
        of FsEndfor: FsFor
        of FsEndWhile: FsWhile
        of FsEndWhen: FsWhen
        of FsEndBlock: FsBlock
        else: FsIf
      if stack.len == 0 or stack[^1].kind != opener:
        templateError("unexpected `" & tagName(fsnode.kind) & "` without matching opener",
          fsnode.file, fsnode.line, fsnode.col)
      else:
        stack.setLen(stack.len - 1)
    else: discard # Cannot happen
  if stack.len > 0:
    let opener = stack[^1]
    templateError("`" & tagName(opener.kind) & "` is missing `" &
      matchingEnd(opener.kind) & "`", opener.file, opener.line, opener.col)

template firstStepErrorChecks(fsns: seq[FSNode]) =
  ## TODO combine all these?
  errorOnDuplicatedExtends(fsns)
  errorOnDuplicatedBlocks(fsns)
  errorOnUnevenBlocks(fsns)

proc loadCache(str: string, file: string = ""): seq[NwtNode] =
  ## For faster compilation
  ## ```-d:nwtCacheOff``` to disable caching
  ## Creates NwtNodes only the first time for a given string,
  ## the second time is returned from the cache
  if not defined(nwtCacheOff) and cacheNwtNode.contains(str):
    return cacheNwtNode[str]
  else:
    # No cache hit (or cache disabled)
    var lexerTokens = toSeq(lex(str))
    var fsns = parseFirstStep(lexerTokens, file)
    fsns.firstStepErrorChecks()
    fsns = fsns.whitespaceControl()
    fsns = fsns.condenseStrings() # we condense on the FSNodes that are cached
    var pos = 0
    when defined(nwtCacheOff):
      return parseSecondStep(fsns, pos)
    else:
      cacheNwtNode[str] = parseSecondStep(fsns, pos)
      return cacheNwtNode[str]

proc loadCacheFile(path: Path): string =
  ## For faster compilation
  ## ```-d:nwtCacheOff``` to disable caching
  ## Statically reads a file, and caches it.
  ## The second time the same file should be read
  ## it is returned from the cache
  when defined(nwtCacheOff):
    return read(nwtBaseDir / path)
  else:
    if cacheNwtNodeFile.contains(nwtBaseDir / path):
      return cacheNwtNodeFile[nwtBaseDir / path]
    else:
      cacheNwtNodeFile[nwtBaseDir / path] = read(nwtBaseDir / path)
      return cacheNwtNodeFile[nwtBaseDir / path]

proc extend(str: string, templateCache: var Deque[seq[NwtNode]],
            seen: var HashSet[string], file: string = "") =
  var secondsStepTokens = loadCache(str, file)
  let foundExtendAt = validExtend(secondsStepTokens)
  if foundExtendAt > -1:
    templateCache.addFirst secondsStepTokens
    let extPath = secondsStepTokens[foundExtendAt].extendsPath
    if seen.contains(extPath):
      let extNode = secondsStepTokens[foundExtendAt]
      templateError("circular extends detected: " & extPath,
        extNode.file, extNode.line, extNode.col)
    seen.incl extPath
    let ext = loadCacheFile(extPath)
    extend(ext, templateCache, seen, nwtBaseDir / extPath)
  else:
    templateCache.addFirst secondsStepTokens

iterator findAll(nwtns: seq[NwtNode], kind: NwtNodeKind): NwtNode =
  for nwtn in nwtns:
    if nwtn.kind == kind: yield nwtn

proc recursiveFindAllBlocks(nwtns: seq[NwtNode]): seq[NwtNode] =
  for nwtn in nwtns.findAll(NBlock):
    result.add nwtn
    result.add recursiveFindAllBlocks(nwtn.blockBody)

proc fillBlocks(nodes: seq[NwtNode]): seq[NwtNode] =
  for node in nodes:
    if node.kind == NBlock:
      for bnode in blocks[node.blockName]:
        if bnode.kind == NBlock:
          result.add fillBlocks(bnode)
        else:
          result.add bnode
    else:
      result.add node

proc resolveSelf(nodes: seq[NwtNode], resolving: var HashSet[string]): seq[NwtNode] =
  ## Replaces `{{self.<block>}}` variables with the body of the corresponding
  ## block. This has to happen at the end of each `compile` invocation because
  ## `blocks` is global: if we waited until AST generation a later template
  ## could already have overwritten a block of the same name (issue #107).
  ## `resolving` guards against a block referencing itself via `self.`.
  for node in nodes:
    var n = node
    case n.kind
    of NVariable:
      if n.variableBody.startsWith(specialSelf):
        let blockname = n.variableBody[specialSelf.len .. ^1]
        if blocks.hasKey(blockname) and not resolving.contains(blockname):
          resolving.incl blockname
          result.add resolveSelf(blocks[blockname], resolving)
          resolving.excl blockname
          continue
    of NIf, NWhen:
      n.nnThen = resolveSelf(n.nnThen, resolving)
      n.nnElif = resolveSelf(n.nnElif, resolving)
      n.nnElse = resolveSelf(n.nnElse, resolving)
    of NElif:
      n.elifBody = resolveSelf(n.elifBody, resolving)
    of NWhile:
      n.whileBody = resolveSelf(n.whileBody, resolving)
    of NFor:
      n.forBody = resolveSelf(n.forBody, resolving)
    of NBlock:
      n.blockBody = resolveSelf(n.blockBody, resolving)
    of NProc:
      n.procBody = resolveSelf(n.procBody, resolving)
    of NCase:
      n.nnCaseOf = resolveSelf(n.nnCaseOf, resolving)
      n.nnCaseElse = resolveSelf(n.nnCaseElse, resolving)
    of NCaseOf:
      n.caseOfBody = resolveSelf(n.caseOfBody, resolving)
    of NCaseElse:
      n.caseElseBody = resolveSelf(n.caseElseBody, resolving)
    of NScope:
      n.scopeBody = resolveSelf(n.scopeBody, resolving)
    else:
      discard
    result.add n

proc compile(str: string, blockToRender: string = "", file: string = ""): seq[NwtNode] =
  var templateCache = initDeque[seq[NwtNode]]()
  var seen = initHashSet[string]()
  extend(str, templateCache, seen, file)
  for idx, tmp in enumerate(templateCache):
    for nwtn in tmp.recursiveFindAllBlocks():
      # echo nwtn.blockName ## HERE ## TODO remove
      blocks[nwtn.blockName] = nwtn.blockBody
  if blockToRender == "":
    var base = templateCache[0]
    result = fillBlocks(base)
  else:
    if blocks.contains(blockToRender):
      result = fillBlocks(blocks[blockToRender])
    else:
      templateError("Block '" & blockToRender & "' is not known.",
        "", 0, 0)
  # resolve `self.` here, while `blocks` still holds this template's blocks,
  # then run the Nwt-stage string condense so `self.` inlining gets merged too
  var resolving = initHashSet[string]()
  result = resolveSelf(result, resolving).condenseStrings()
  # compute the pre-allocation size from the final tree (cache independent)
  guessedStringLen = staticLen(result)
  # echo result

proc generatePreallocatedStringDef(len: int): NimNode =
  # dumpAstGen:
  #   when result is string:
  #     result = newStringOfCap(10)
  return nnkStmtList.newTree(
    nnkWhenStmt.newTree(
      nnkElifBranch.newTree(
        nnkInfix.newTree(
          newIdentNode("is"),
          newIdentNode(nwtVarname),
          newIdentNode("string")
        ),
        nnkStmtList.newTree(
          nnkAsgn.newTree(
            newIdentNode(nwtVarname),
            nnkCall.newTree(
              newIdentNode("newStringOfCap"),
              newLit(len)
            )
          )
        )
      )
    )
  )


template doCompile(str: untyped, blockToRender: string = "", res = newStmtList(),
                  file: string = ""): untyped =
  guessedStringLen = 0
  try:
    let nwtNodes = compile(str, blockToRender, file)
    when defined(dumpNwtAst): echo nwtNodes
    when defined(dumpNwtAstPretty): echo nwtNodes.pretty
    result = res

    if not nwtIter:
      if (not defined(noPreallocatedString)) and guessedStringLen > 0:
        result.add generatePreallocatedStringDef(guessedStringLen)

    for nwtNode in astAst(nwtNodes):
      result.add nwtNode
    when defined(dumpNwtMacro): echo toStrLit(result)
  except NimjaError as e:
    reportNimjaError(e)

template tmplsMacroImpl() =
  # we use templates as a "variable alias"
  # eg: template foo(): untyped = baa
  # StmtList
  #   TemplateDef
  #     Ident "xx"
  #     Empty
  #     Empty
  #     FormalParams
  #       Ident "untyped"
  #     Empty
  #     Empty
  #     StmtList
  #       Ident "rax"
  result = newStmtList()
  for node in context:
    var alias = newTree(nnkTemplateDef)
    alias.add node[0]
    alias.add newNimNode(nnkEmpty)
    alias.add newNimNode(nnkEmpty)
    var formalParams = newNimNode(nnkFormalParams)
    formalParams.add newIdentNode("untyped")
    alias.add formalParams
    alias.add newNimNode(nnkEmpty)
    alias.add newNimNode(nnkEmpty)
    var body = newStmtList()
    body.add node[1]
    alias.add body
    result.add alias

macro compileTemplateStr*(str: typed, baseDir: static string = "", 
    blockToRender: static string = "", iter: static bool = false,
    varname: static string = "result",  escapeWith: untyped = nil,
    context: untyped = nil): untyped =
  ## Compiles a Nimja template from a string.
  ##
  ## .. code-block:: Nim
  ##  proc yourFunc(yourParams: bool): string =
  ##    compileTemplateStr("{%if yourParams%}TRUE{%endif%}")
  ##
  ##  echo yourFunc(true)
  ##
  ## If `iter = true` then the macro can be used in an iterator body
  ## this could be used for streaming templates, or to save memory when a big template
  ## is rendered and the http server can send data in chunks.
  ##
  ## .. code-block:: nim
  ##  iterator yourIter(yourParams: bool): string =
  ##    compileTemplateStr("{%for idx in 0 .. 100%}{{idx}}{%endfor%}", iter = true)
  ##
  ##  for elem in yourIter(true):
  ##    echo elem
  ##
  ## `varname` specifies the variable that is appended to.
  ##
  ## `escapeWith = htmlEscape` HTML-escapes every `{{ ... }}` variable; any
  ## other proc (e.g. URL/JS escaping) can be passed as `escapeWith`.
  ## `{{ x|safe }}` bypasses escaping, `{{ x|e }}` always escapes.
  ##
  ## A context can be supplied to the `compileTemplateStr` (also `compileTemplateFile`), to override variable names:
  ##
  ## .. code-block:: nim
  ##   block:
  ##     type
  ##       Rax = object
  ##         aa: string
  ##         bb: float
  ##     var rax = Rax(aa: "aaaa", bb: 13.37)
  ##     var foo = 123
  ##     proc render(): string =
  ##       compileTemplateStr("{{node.bb}}{{baa}}", {node: rax, baa: foo})
  ##

  # Please note, currently the context **cannot be** procs/funcs etc.
  nwtVarname = varname
  nwtIter = iter
  nwtBaseDir = baseDir
  setEscapeProc(escapeWith)
  let entry = str.lineInfoObj
  nwtFallbackFile = entry.filename
  nwtFallbackLine = entry.line
  nwtFallbackCol = entry.column
  tmplsMacroImpl()
  doCompile(str.strVal, blockToRender, result, file = "")

macro compileTemplateFile*(path: static string, baseDir: static string = "", 
    blockToRender: static string = "", iter: static bool = false,
    varname: static string = "result", escapeWith: untyped = nil,
    context: untyped = nil): untyped =
  ## Compiles a Nimja template from a file.
  ##
  ## .. code-block:: nim
  ##  proc yourFunc(yourParams: bool): string =
  ##    compileTemplateFile(getScriptDir() / "relative/path.nimja)
  ##
  ##  echo yourFunc(true)
  ##
  ## If `iter = true` then the macro can be used in an iterator body
  ## this could be used for streaming templates, or to save memory when a big template
  ## is rendered and the http server can send data in chunks.
  ##
  ## .. code-block:: nim
  ##  iterator yourIter(yourParams: bool): string =
  ##    compileTemplateFile(getScriptDir() / "relative/path.nimja, iter = true)
  ##
  ##  for elem in yourIter(true):
  ##    echo elem
  ##
  ## `varname` specifies the variable that is appended to.
  ##
  ## `escapeWith = htmlEscape` HTML-escapes every `{{ ... }}` variable; any
  ## other proc (e.g. URL/JS escaping) can be passed as `escapeWith`.
  ## `{{ x|safe }}` bypasses escaping, `{{ x|e }}` always escapes.
  ## A context can be supplied to the `compileTemplateFile` (also `compileTemplateStr`), to override variable names:
  ##
  ## .. code-block:: nim
  ##   block:
  ##     type
  ##       Rax = object
  ##         aa: string
  ##         bb: float
  ##     var rax = Rax(aa: "aaaa", bb: 13.37)
  ##     var foo = 123
  ##     proc render(): string =
  ##       compileTemplateFile(getScriptDir() / "myTemplate.nimja", {node: rax, baa: foo})
  ##
  nwtVarname = varname
  nwtIter = iter
  nwtBaseDir = baseDir
  setEscapeProc(escapeWith)
  const ii = instantiationInfo(-1, true)
  nwtFallbackFile = ii.filename
  nwtFallbackLine = ii.line
  nwtFallbackCol = ii.column
  let str = loadCacheFile(path)
  tmplsMacroImpl()
  doCompile(str, blockToRender, result, file = nwtBaseDir / path)

template tmplsImpl(str: static string, baseDir: static string, blockToRender: static string,
                   escapeProc: untyped = nil): string =
  var nimjaTmplsVar: string
  compileTemplateStr(str, baseDir, blockToRender, varname = astToStr nimjaTmplsVar,
                     escapeWith = escapeProc)
  nimjaTmplsVar

macro tmpls*(str: static string, baseDir: static string = "", 
    blockToRender: static string = "", escapeWith: untyped = nil,
    context: untyped = nil): string =
  ## Compiles a Nimja template string and returns directly.
  ## Can be used inline, without a wrapper proc.
  ##
  ## .. code-block:: nim
  ##  echo tmpls("""{% if true %}Is true!{% endif %}""")
  ##
  ## A context can be supplied to the template, to override the variable names:
  ##
  ## .. code-block:: nim
  ##  type
  ##    Rax = object
  ##      aa: string
  ##      bb: float
  ##  var rax = Rax(aa: "aaaa", bb: 13.37)
  ##  var foo = 123
  ##  echo tmpls("""{% if node.aa == "aaaa" %}{{node.bb}}{% endif %}{{baa}}""", {node: rax, baa: foo})
  ##
  tmplsMacroImpl()
  result.add quote do:
    tmplsImpl(`str`, `baseDir`, `blockToRender`, `escapeWith`)

template tmplfImpl(path: static string, baseDir: static string = "", blockToRender: static string = "",
                   escapeProc: untyped = nil): string =
  var nimjaTmplfVar: string
  compileTemplateFile(path, baseDir, blockToRender, varname = astToStr nimjaTmplfVar,
                      escapeWith = escapeProc)
  nimjaTmplfVar

macro tmplf*(str: static string, baseDir: static string = "", blockToRender: static string = "",
    escapeWith: untyped = nil, context: untyped = nil): string =
  ## Compiles a Nimja template file and returns directly.
  ## Can be used inline, without a wrapper proc.
  ##
  ## .. code-block:: nim
  ##  echo tmplf("""/some/template.nimja""")
  ##
  ## A context can be supplied to the template, to override the variable names:
  ##
  ## .. code-block:: nim
  ##  type
  ##    Rax = object
  ##      aa: string
  ##      bb: float
  ##  var rax = Rax(aa: "aaaa", bb: 13.37)
  ##  echo tmplf("""/some/template.nimja""", {node: rax})
  ##
  tmplsMacroImpl()
  result.add quote do:
    tmplfImpl(`str`, `baseDir`, `blockToRender`, `escapeWith`)

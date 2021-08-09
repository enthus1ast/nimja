import strutils, macros, sequtils, parseutils, os
import nwtTokenizer

type
  NwtNodeKind = enum
    NStr, NComment, NIf, NElif, NElse, NWhile, NFor,
    NVariable, NEval, NImport, NBlock, NExtends
  NwtNode = object
    case kind: NwtNodeKind
    of NStr:
      strBody: string
    of NComment:
      commentBody: string
    of NIf:
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
    of NImport:
      importBody: string
    of NBlock:
      blockName: string
      blockBody: seq[NwtNode]
    of NExtends:
      extendsPath: string
    else: discard

type IfState {.pure.} = enum
  InThen, InElif, InElse

# First step nodes
type
  FsNodeKind = enum
    FsIf, FsStr, FsEval, FsElse, FsElif, FsEndif, FsFor,
    FsEndfor, FsVariable, FsWhile, FsEndWhile, FsImport, FsBlock, FsEndBlock, FsExtends
  FSNode = object
    kind: FsNodeKind
    value: string

template getScriptDir*(): string =
  ## Helper for staticRead
  getProjectPath()

# Forward decleration
proc parseSecondStep*(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc parseSecondStepOne(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc astAst(tokens: seq[NwtNode]): seq[NimNode]


func splitStmt(str: string): tuple[pref: string, suf: string] {.inline.} =
  ## the prefix is normalized (transformed to lowercase)
  var pref = ""
  var pos = parseIdent(str, pref, 0)
  pos += str.skipWhitespace(pos)
  result.pref = toLowerAscii(pref)
  result.suf = str[pos..^1]

proc parseFirstStep*(tokens: seq[Token]): seq[FSNode] =
  result = @[]
  for token in tokens:
    if token.tokenType == NwtEval:
      let (pref, suf) = splitStmt(token.value)
      case pref
      of "if":
        result.add FSNode(kind: FsIf, value: suf)
      of "elif":
        result.add FSNode(kind: FsElif, value: suf)
      of "else":
        result.add FSNode(kind: FsElse, value: suf)
      of "endif":
        result.add FSNode(kind: FsEndif, value: suf)
      of "for":
        result.add FSNode(kind: FsFor, value: suf)
      of "endfor":
        result.add FSNode(kind: FsEndfor, value: suf)
      of "while":
        result.add FSNode(kind: FsWhile, value: suf)
      of "endwhile":
        result.add FSNode(kind: FsEndWhile, value: suf)
      of "importnwt":
        result.add FSNode(kind: FsImport, value: suf)
      of "block":
        result.add FSNode(kind: FsBlock, value: suf)
      of "endblock":
        result.add FSNode(kind: FsEndBlock, value: suf)
      of "extends":
        result.add FSNode(kind: FsExtends, value: suf)
      else:
        result.add FSNode(kind: FsEval, value: token.value)
    elif token.tokenType == NwtString:
      result.add FSNode(kind: FsStr, value: token.value)
    elif token.tokenType == NwtVariable:
      result.add FSNode(kind: FsVariable, value: token.value)
    elif token.tokenType == NwtComment:
      discard # ignore comments
    else:
      echo "[FS] Not catched:", token


proc parseSsIf(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the if that we got called about
  result = NwtNode(kind: NwtNodeKind.NIf)
  result.ifStmt = elem.value
  pos.inc # skip the if
  var ifstate = IfState.InThen
  while pos < fsTokens.len:
    elem = fsTokens[pos]
    if elem.kind == FsIf:
      if ifState == IfState.InThen:
        result.nnThen.add parseSecondStep(fsTokens, pos)
      if ifState == IfState.InElse:
        result.nnElse.add parseSecondStep(fsTokens, pos)
      if ifState == IfState.InElif:
        result.nnElif[^1].elifBody.add parseSecondStep(fsTokens, pos)
    elif elem.kind == FsElif:
      ifstate = IfState.InElif
      result.nnElif.add NwtNode(kind: NElif, elifStmt: elem.value)
    elif elem.kind == FsElse:
      ifstate = IfState.InElse
    elif elem.kind == FsEndif:
      break
    else:
      if ifState == IfState.InThen:
        result.nnThen &= parseSecondStepOne(fsTokens, pos)
      if ifState == IfState.InElse:
        result.nnElse &= parseSecondStepOne(fsTokens, pos)
      if ifState == IfState.InElif:
        result.nnElif[^1].elifBody &= parseSecondStepOne(fsTokens, pos)
    pos.inc


proc parseSsWhile(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the while that we got called about
  result = NwtNode(kind: NwtNodeKind.NWhile)
  result.whileStmt = elem.value
  while pos < fsTokens.len:
    pos.inc # skip the while
    elem = fsTokens[pos]
    if elem.kind == FsEndWhile:
      break
    else:
      result.whileBody &= parseSecondStepOne(fsTokens, pos)

proc parseSsFor(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the for that we got called about
  result = NwtNode(kind: NwtNodeKind.NFor)
  result.forStmt = elem.value
  while pos < fsTokens.len:
    pos.inc # skip the for
    elem = fsTokens[pos]
    if elem.kind == FsEndFor:
      break
    else:
      result.forBody &= parseSecondStepOne(fsTokens, pos)

proc parseSsBlock(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  let blockName = elem.value
  result = NwtNode(kind: NwtNodeKind.NBlock, blockName: blockName)
  while pos < fsTokens.len:
    pos.inc # skip the block
    elem = fsTokens[pos]
    if elem.kind == FsEndBlock:
      break
    else:
      result.blockBody &= parseSecondStepOne(fsTokens, pos)

proc parseSsExtends(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  let extendsPath = elem.value.strip(true, true, {'"'})
  return NwtNode(kind: NExtends, extendsPath: extendsPath)

converter singleNwtNodeToSeq(nwtNode: NwtNode): seq[NwtNode] =
  return @[nwtNode]

proc includeNwt(nodes: var seq[NwtNode], path: string) {.compileTime.} =
  const basePath = getProjectPath()
  var str = staticRead( basePath  / path.strip(true, true, {'"'}) )
  var lexerTokens = toSeq(nwtTokenize(str))
  var firstStepTokens = parseFirstStep(lexerTokens)
  var pos = 0
  var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  for secondStepToken in secondsStepTokens:
    nodes.add secondStepToken

proc parseSecondStepOne(fsTokens: seq[FSNode], pos: var int): seq[NwtNode] =
    let fsToken = fsTokens[pos]
    # Complex Types
    if fsToken.kind == FSif:
      return parseSsIf(fsTokens, pos)
    elif fsToken.kind == FsWhile:
      return parseSsWhile(fsTokens, pos)
    elif fsToken.kind == FsFor:
      return parseSsFor(fsTokens, pos)
    # Simple Types
    elif fsToken.kind == FsStr:
      return NwtNode(kind: NStr, strBody: fsToken.value)
    elif fsToken.kind == FsVariable:
      return NwtNode(kind: NVariable, variableBody: fsToken.value)
    elif fsToken.kind == FsEval:
      return NwtNode(kind: NEval, evalBody: fsToken.value)
    elif fsToken.kind == FsBlock:
      return parseSsBlock(fsTokens, pos)
    elif fsToken.kind == FsExtends:
      return parseSsExtends(fsTokens, pos)
    elif fsToken.kind == FsImport:
        includeNwt(result, fsToken.value)
    else:
      echo "[SS] NOT IMPL: ", fsToken

proc parseSecondStep*(fsTokens: seq[FSNode], pos: var int): seq[NwtNode] =
  while pos < fsTokens.len:
    result &= parseSecondStepOne(fsTokens, pos)
    pos.inc # skip the current elem

func astVariable(token: NwtNode): NimNode =
  return nnkStmtList.newTree(
    nnkInfix.newTree(
      newIdentNode("&="),
      newIdentNode("result"),
      newCall(
        "$",
        parseStmt(token.variableBody)
      )
    )
  )

func astStr(token: NwtNode): NimNode =
  return nnkStmtList.newTree(
    nnkInfix.newTree(
      newIdentNode("&="),
      newIdentNode("result"),
      newStrLitNode(token.strBody)
    )
  )

func astEval(token: NwtNode): NimNode =
  return parseStmt(token.evalBody)

func astComment(token: NwtNode): NimNode =
  return newCommentStmtNode(token.commentBody)

proc astFor(token: NwtNode): NimNode =
  let easyFor = "for " & token.forStmt & ": discard" # `discard` to make a parsable construct
  result = parseStmt(easyFor)
  result[0][2] = newStmtList(astAst(token.forBody)) # overwrite discard with real `for` body

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
  result = nnkIfStmt.newTree()

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


proc astAstOne(token: NwtNode): NimNode =
  if token.kind == NVariable:
    return astVariable(token)
  elif token.kind == NStr:
    return astStr(token)
  elif token.kind == NEval:
    return astEval(token)
  elif token.kind == NComment:
    return astComment(token)
  elif token.kind == NIf:
    return astIf(token)
  elif token.kind == NFor:
    return astFor(token)
  elif token.kind == NWhile:
    return astWhile(token)
  elif token.kind == NExtends:
    return parseStmt("discard")
  elif token.kind == NBlock:
    return parseStmt("discard")
  else:
    raise newException(ValueError, "cannot convert to ast:" & $token.kind)

proc astAst(tokens: seq[NwtNode]): seq[NimNode] =
  for token in tokens:
    result.add astAstOne(token)

template compile(): untyped =
  ## TODO extend must be the first token, but
  ## comments can come before extend (for documentation purpose)
  if secondsStepTokens[0].kind == NExtends:
    # echo "===== THIS TEMPLATE EXTENDS ====="
    # Load master template
    let masterStr = staticRead( getScriptDir() / secondsStepTokens[0].extendsPath)
    var masterLexerTokens = toSeq(nwtTokenize(masterStr))
    var masterFirstStepTokens = parseFirstStep(masterLexerTokens)
    var masterPos = 0
    var masterSecondsStepTokens = parseSecondStep(masterFirstStepTokens, masterPos)

    # Load THIS template (above)
    var toRender: seq[NwtNode] = @[]
    for masterSecondsStepToken in masterSecondsStepTokens:
      if masterSecondsStepToken.kind == NBlock:
        ## search the other template and put the stuff in toRender
        for secondsStepToken in secondsStepTokens[1..^1]:
          if secondsStepToken.kind == NExtends: raise newException(ValueError, "only one extend is allowed!")
          if secondsStepToken.kind == NBlock and secondsStepToken.blockName == masterSecondsStepToken.blockName:
            for blockToken in secondsStepToken.blockBody:
              toRender.add blockToken
      else:
        toRender.add masterSecondsStepToken
    result = newStmtList()
    for token in toRender:
      result.add astAstOne(token)
  else:
    result = newStmtList()
    for token in secondsStepTokens:
      result.add astAstOne(token)

macro compileTemplateStr*(str: typed): untyped =
  ## Compiles a nimja template from a string.
  ## .. code-block:: nim
  ##  compileTemplateString("{%if true%}TRUE{%endif%}")
  var lexerTokens = toSeq(nwtTokenize(str.strVal))
  var firstStepTokens = parseFirstStep(lexerTokens)
  var pos = 0
  var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  when defined(dumpNwtAst): echo secondsStepTokens
  compile



macro compileTemplateFile*(path: static string): untyped =
  ## Compiles a nimja template from a file.
  ## .. code-block:: nim
  ##  compileTemplateFile(getScriptDir() / "relative/path.nwt")
  let str = staticRead(path)
  var lexerTokens = toSeq(nwtTokenize(str))
  var firstStepTokens = parseFirstStep(lexerTokens)
  var pos = 0
  var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  when defined(dumpNwtAst): echo secondsStepTokens
  compile
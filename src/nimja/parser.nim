import strutils, macros, sequtils, parseutils, os, tables, sets, deques, std/enumerate
import lexer, sharedhelper
export getScriptDir

# special case `self` variable, used to reference blocks
const specialSelf {.strdefine.} = "self."

type Path = string
type
  NwtNodeKind = enum
    NStr, NIf, NElif, NElse, NWhile, NFor,
    NVariable, NEval, NImport, NBlock,
    NExtends, NProc, NFunc, NWhen
  NwtNode = object
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
    of NImport:
      importBody: string
    of NBlock:
      blockName: string
      blockBody: seq[NwtNode]
    of NExtends:
      extendsPath: string
    of NProc:
      procHeader: string
      procBody: seq[NwtNode]
    else: discard

# First step nodes
type
  FsNodeKind = enum
    FsIf, FsStr, FsEval, FsElse, FsElif, FsEndif, FsFor,
    FsEndfor, FsVariable, FsWhile, FsEndWhile, FsImport,
    FsBlock, FsEndBlock, FsExtends, FsProc, FsEndProc, FsFunc, FsEndFunc, FsEnd, FsWhen, FsEndWhen
  FSNode = object
    kind: FsNodeKind
    value: string
    stripPre: bool
    stripPost: bool

var cacheNwtNode {.compileTime.}: Table[string, seq[NwtNode]] ## a cache for rendered NwtNodes
var cacheNwtNodeFile {.compileTime.}: Table[Path, string] ## a cache for content of a path
var nwtIter {.compileTime.} = false
var nwtVarname {.compileTime.}: string
var blocks {.compileTime.} : Table[string, seq[NwtNode]]
var guessedStringLen {.compileTime.} = 0

when defined(dumpNwtAstPretty):
  import json
  proc pretty*(nwtNodes: seq[NwtNode]): string {.compileTime.} =
    (%* nwtNodes).pretty()

# Forward declaration
proc parseSecondStep(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc parseSecondStepOne(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc astAst(tokens: seq[NwtNode]): seq[NimNode]
proc compile(str: string): seq[NwtNode]
proc astAstOne(token: NwtNode): NimNode

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
    if result.token.value[^1] == '-':
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

proc parseFirstStep(tokens: seq[Token]): seq[FSNode] =
  result = @[]
  for token in tokens:
    let (cleanedToken, stripPre, stripPost) = mustStrip(token)
    case token.kind
    of NwtEval:
      let (pref, suf) = splitStmt(cleanedToken.value)
      case pref
      of "if": result.add FSNode(kind: FsIf, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "elif": result.add FSNode(kind: FsElif, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "else": result.add FSNode(kind: FsElse, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endif": result.add FSNode(kind: FsEndif, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "for": result.add FSNode(kind: FsFor, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endfor": result.add FSNode(kind: FsEndfor, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "while": result.add FSNode(kind: FsWhile, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endwhile": result.add FSNode(kind: FsEndWhile, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "importnwt", "importnimja": result.add FSNode(kind: FsImport, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "block": result.add FSNode(kind: FsBlock, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endblock": result.add FSNode(kind: FsEndBlock, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "extends": result.add FSNode(kind: FsExtends, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "proc": result.add FSNode(kind: FsProc, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endproc": result.add FSNode(kind: FsEndProc, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "macro": result.add FSNode(kind: FsProc, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endmacro": result.add FSNode(kind: FsEndProc, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "func": result.add FSNode(kind: FsFunc, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endfunc": result.add FSNode(kind: FsEndFunc, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "end": result.add FSNode(kind: FsEnd, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "when": result.add FSNode(kind: FsWhen, value: suf, stripPre: stripPre, stripPost: stripPost)
      of "endwhen": result.add FSNode(kind: FsEndWhen, value: suf, stripPre: stripPre, stripPost: stripPost)
      else:
        result.add FSNode(kind: FsEval, value: cleanedToken.value, stripPre: stripPre, stripPost: stripPost)
    of NwtString: result.add FSNode(kind: FsStr, value: token.value)
    of NwtVariable: result.add FSNode(kind: FsVariable, value: cleanedToken.value, stripPre: stripPre, stripPost: stripPost)
    of NwtComment: discard # ignore comments
    else: echo "[FS] Not catched:", token

proc consumeBlock(fsTokens: seq[FSNode], pos: var int, endTags: set[FsNodeKind]): seq[NwtNode] =
  while pos < fsTokens.len:
    let fsToken = fsTokens[pos]
    if endTags.contains(fsToken.kind):
      break
    else:
      result.add parseSecondStepOne(fsTokens, pos)

proc parseSsIf(fsTokens: seq[FsNode], pos: var int): NwtNode =
  while pos < fsTokens.len:
    let elem = fsTokens[pos]
    case elem.kind
    of FsIf:
      pos.inc
      result = NwtNode(kind: NwtNodeKind.NIf)
      result.ifStmt = elem.value
      result.nnThen.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndif})
    of FsElif:
      pos.inc
      result.nnElif.add NwtNode(kind: NElif, elifStmt: elem.value)
      result.nnElif[^1].elifBody.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndif} )
    of FsElse:
      pos.inc
      result.nnElse.add consumeBlock(fsTokens, pos, {FsEndif})
    of FsEndif:
      pos.inc
      break
    else:
      raise newException(ValueError, "should not happen: " & $elem)

proc parseSsWhen(fsTokens: seq[FsNode], pos: var int): NwtNode =
  while pos < fsTokens.len:
    let elem = fsTokens[pos]
    case elem.kind
    of FsWhen:
      pos.inc
      result = NwtNode(kind: NwtNodeKind.NWhen)
      result.ifStmt = elem.value
      result.nnThen.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndWhen})
    of FsElif:
      pos.inc
      result.nnElif.add NwtNode(kind: NElif, elifStmt: elem.value)
      result.nnElif[^1].elifBody.add consumeBlock(fsTokens, pos, {FsElif, FsElse, FsEndWhen} )
    of FsElse:
      pos.inc
      result.nnElse.add consumeBlock(fsTokens, pos, {FsEndWhen})
    of FsEndWhen:
      pos.inc
      break
    else:
      raise newException(ValueError, "should not happen: " & $elem)

proc parseSsWhile(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the while that we got called about
  result = NwtNode(kind: NwtNodeKind.NWhile)
  result.whileStmt = elem.value
  pos.inc # skip FsWhile
  result.whileBody = consumeBlock(fsTokens, pos, {FsEndWhile})
  pos.inc # skip FsEndWhile

proc parseSsFor(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the for that we got called about
  result = NwtNode(kind: NwtNodeKind.NFor)
  result.forStmt = elem.value
  pos.inc #skip FsFor
  result.forBody = consumeBlock(fsTokens, pos, {FsEndFor})
  pos.inc # skip FsEndBlock

proc parseSsBlock(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  let blockName = elem.value
  result = NwtNode(kind: NwtNodeKind.NBlock, blockName: blockName)
  pos.inc # skip FsBlock
  result.blockBody = consumeBlock(fsTokens, pos, {FsEndBlock})
  pos.inc # skip FsEndBlock

proc parseSsProc(fsTokens: seq[FsNode], pos: var int, kind: NwtNodeKind = NProc): NwtNode =
  var elem: FsNode = fsTokens[pos]
  result = NwtNode(kind: NwtNodeKind.NProc)
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
  return NwtNode(kind: NExtends, extendsPath: extendsPath)

converter singleNwtNodeToSeq(nwtNode: NwtNode): seq[NwtNode] =
  return @[nwtNode]

proc includeNwt(nodes: var seq[NwtNode], path: string) =
  const basePath = getProjectPath()
  var str = read( basePath  / path.strip(true, true, {'"'}) )
  nodes = compile(str)

proc parseSecondStepOne(fsTokens: seq[FSNode], pos: var int): seq[NwtNode] =
    let fsToken = fsTokens[pos]

    case fsToken.kind
    # Complex Types
    of FsIf: return parseSsIf(fsTokens, pos)
    of FsWhen: return parseSsWhen(fsTokens, pos)

    of FsWhile: return parseSsWhile(fsTokens, pos)
    of FsFor: return parseSsFor(fsTokens, pos)
    of FsBlock: return parseSsBlock(fsTokens, pos)

    # Proc / Func / Macro are very similar
    of FsProc: return parseSsProc(fsTokens, pos, NProc)
    of FsFunc: return parseSsProc(fsTokens, pos, NFunc)

    # Simple Types
    of FsStr:
      pos.inc
      guessedStringLen.inc fsToken.value.len
      return NwtNode(kind: NStr, strBody: fsToken.value)
    of FsVariable:
      pos.inc
      return NwtNode(kind: NVariable, variableBody: fsToken.value)
    of FsEval:
      pos.inc
      return NwtNode(kind: NEval, evalBody: fsToken.value)
    of FsExtends:
      return parseSsExtends(fsTokens, pos)
    of FsImport:
      pos.inc
      includeNwt(result, fsToken.value)
    else: raise newException(ValueError, "[SS] NOT IMPL: " & $fsToken)


proc parseSecondStep(fsTokens: seq[FSNode], pos: var int): seq[NwtNode] =
  while pos < fsTokens.len:
    result &= parseSecondStepOne(fsTokens, pos)

proc astVariable(token: NwtNode): NimNode =
  var varb: NimNode
  # The "self." block insertion
  if token.variableBody.startsWith(specialSelf):
    let blockname = token.variableBody[specialSelf.len .. ^1]
    if blocks.hasKey(blockname):
      result = newStmtList()
      for token in blocks[blockname]:
        result.add astAstOne(token)
      return
  try:
    varb = parseStmt(token.variableBody)
  except:
    error "Cannot parse variable body: " & token.variableBody
  return nnkStmtList.newTree(
    nnkInfix.newTree(
      newIdentNode("&="),
      newIdentNode(nwtVarname),
      newCall(
        "$",
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

func astVariableIter(token: NwtNode): NimNode =
  return nnkStmtList.newTree(
    nnkYieldStmt.newTree(
      newCall(
        "$",
        parseStmt(token.variableBody)
      )
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
    error "Cannot parse eval body: " & token.evalBody

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


proc astProc(token: NwtNode, procStr = "proc"): NimNode =
  discard
  let easyProc =  procStr & " " & token.procHeader & " discard"
  result = parseStmt(easyProc) # dummy to build valid procBody
  result[0].body = nnkStmtList.newTree(
    astAst(token.procBody) # fill the proc body with content
  )

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
  else: raise newException(ValueError, "cannot convert to ast:" & $token.kind)

proc astAst(tokens: seq[NwtNode]): seq[NimNode] =
  for token in tokens:
    result.add astAstOne(token)

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
    raise newException(ValueError,
      "Invalid token(s) before {%extend%}: " & $ secondsStepTokens[0 .. result]
    )

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
      raise newException(ValueError, "found duplicated block:" & fsnode.value & " :" & $ fsns)
    else:
      blocknames.incl fsnode.value

proc errorOnDuplicatedExtends(fsns: seq[FSNode]) =
  ## Find duplicated extends
  # TODO give context and line
  var foundExtends = false
  for _ in fsns.findAll(FsExtends):
    if foundExtends == true:
      raise newException(ValueError, "found multiple extends: " & $fsns)
    else:
      foundExtends = true

proc errorOnUnevenBlocks(fsns: seq[FSNode]) =
  ## Find and errors uneven/lonely blocks
  # TODO give context and line
  var ifs = 0
  var fors = 0
  var whiles = 0
  for fsnode in fsns.findAll({FsIf, FsEndif, FsFor, FsEndfor, FsWhile, FsEndWhile}):
    case fsnode.kind
    of FsIf: ifs.inc
    of FsEndif: ifs.dec
    of FsFor: fors.inc
    of FsEndfor: fors.dec
    of FsWhile: whiles.inc
    of FsEndWhile: whiles.dec
    else: discard # Cannot happen
  if ifs != 0:
    raise newException(ValueError, "uneven if's: " & $fsns)
  if fors != 0:
    raise newException(ValueError, "uneven for's: " & $fsns)
  if whiles != 0:
    raise newException(ValueError, "uneven while's: " & $fsns)

template firstStepErrorChecks(fsns: seq[FSNode]) =
  ## TODO combine all these?
  errorOnDuplicatedExtends(fsns)
  errorOnDuplicatedBlocks(fsns)
  errorOnUnevenBlocks(fsns)

proc loadCache(str: string): seq[NwtNode] =
  ## For faster compilation
  ## ```-d:nwtCacheOff``` to disable caching
  ## Creates NwtNodes only the first time for a given string,
  ## the second time is returned from the cache
  if not defined(nwtCacheOff) and cacheNwtNode.contains(str):
    return cacheNwtNode[str]
  else:
    # No cache hit (or cache disabled)
    var lexerTokens = toSeq(lex(str))
    var fsns = parseFirstStep(lexerTokens)
    fsns.firstStepErrorChecks()
    fsns = fsns.condenseStrings() # we condense on the FSNodes that are cached
    fsns = fsns.whitespaceControl()
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
    return read(path)
  else:
    if cacheNwtNodeFile.contains(path):
      return cacheNwtNodeFile[path]
    else:
      cacheNwtNodeFile[path] = read(path)
      return cacheNwtNodeFile[path]

proc extend(str: string, templateCache: var Deque[seq[NwtNode]]) =
  var secondsStepTokens = loadCache(str)
  let foundExtendAt = validExtend(secondsStepTokens)
  if foundExtendAt > -1:
    templateCache.addFirst secondsStepTokens
    let ext = loadCacheFile(getScriptDir() / secondsStepTokens[foundExtendAt].extendsPath)
    extend(ext, templateCache)
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

proc compile(str: string): seq[NwtNode] =
  var templateCache = initDeque[seq[NwtNode]]()
  extend(str, templateCache)
  for idx, tmp in enumerate(templateCache):
    for nwtn in tmp.recursiveFindAllBlocks():
      blocks[nwtn.blockName] = nwtn.blockBody
  var base = templateCache[0]
  return fillBlocks(base).condenseStrings() # ast condense after blocks are filled


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


template doCompile(str: untyped): untyped =
  guessedStringLen = 0
  let nwtNodes = compile(str)
  when defined(dumpNwtAst): echo nwtNodes
  when defined(dumpNwtAstPretty): echo nwtNodes.pretty
  result = newStmtList()

  if not nwtIter:
    if (not defined(noPreallocatedString)):
      result.add generatePreallocatedStringDef(guessedStringLen)

  for nwtNode in nwtNodes:
    result.add astAstOne(nwtNode)
  when defined(dumpNwtMacro): echo toStrLit(result)


macro compileTemplateStr*(str: typed, iter: static bool = false,
    varname: static string = "result"): untyped =
  ## Compiles a Nimja template from a string.
  ##
  ## .. code-block:: Nim
  ##  proc yourFunc(yourParams: bool): string =
  ##    compileTemplateString("{%if yourParams%}TRUE{%endif%}")
  ##
  ##  echo yourFunc(true)
  ##
  ## If `iter = true` then the macro can be used in an iterator body
  ## this could be used for streaming templates, or to save memory when a big template
  ## is rendered and the http server can send data in chunks.
  ##
  ## .. code-block:: nim
  ##  iterator yourIter(yourParams: bool): string =
  ##    compileTemplateString("{%for idx in 0 .. 100%}{{idx}}{%endfor%}", iter = true)
  ##
  ##  for elem in yourIter(true):
  ##    echo elem
  ##
  ## `varname` specifies the variable that is appended to.
  ##
  nwtVarname = varname
  nwtIter = iter
  doCompile(str.strVal)

macro compileTemplateFile*(path: static string, iter: static bool = false,
    varname: static string = "result"): untyped =
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
  nwtVarname = varname
  nwtIter = iter
  let str = loadCacheFile(path)
  doCompile(str)

template tmplsImpl(str: static string): string =
  var nimjaTmplsVar: string
  compileTemplateStr(str, varname = astToStr nimjaTmplsVar)
  nimjaTmplsVar

# template tmplsMacroImpl() =
#   result = newStmtList()
#   # var vsec = newTree(nnkVarSection)
#   var vsec = newTree(nnkLetSection)
#   for node in context:
#     var idn = newTree(nnkIdentDefs)
#     idn.add node[0]
#     idn.add newNimNode(nnkEmpty)
#     idn.add node[1]
#     vsec.add idn
#   result.add vsec

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

macro tmpls*(str: static string, context: varargs[untyped]): string =
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
  ##  echo tmpls("""{% if node.aa == "aaaa" %}{{node.bb}}{% endif %}{{baa}}""", node = rax, baa = foo)
  ##
  tmplsMacroImpl()
  result.add quote do:
    tmplsImpl(`str`)

template tmplfImpl(path: static string): string =
  var nimjaTmplfVar: string
  compileTemplateFile(path, varname = astToStr nimjaTmplfVar)
  nimjaTmplfVar

macro tmplf*(str: static string, context: varargs[untyped]): string =
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
  ##  echo tmplf("""/some/template.nimja""", node = rax)
  ##
  tmplsMacroImpl()
  result.add quote do:
    tmplfImpl(`str`)
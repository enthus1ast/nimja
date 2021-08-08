# {.push:experimental:vmopsDanger.}
# {.experimental: "vmopsDanger".}


# when not defined(vmopsDanger):
#   echo "compile with: --experimental:vmopsDanger!"
#   quit()


import strformat, strutils
import macros
import nwtTokenizer, sequtils, parseutils

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
      nnThen: seq[NwtNode] # <---- Alle Nodes
      nnElif: seq[NwtNode] # <---  Elif nodes
      nnElse: seq[NwtNode] # <---- Alle Nodes
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

# TODO global vars must gone!
# import tables
# var gBlocks {.compileTime.}: Table[string, seq[NwtNode]]
# var gExtends {.compileTime.}: Table[string, seq[NwtNode]]

import os
template getScriptDir(): string =
  ## Helper for staticRead
  # parentDir(instantiationInfo(-1, true).filename)
  instantiationInfo(-1, true).filename

# Forward decleration
proc parseSecondStep*(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc parseSecondStepOne(fsTokens: seq[FSNode], pos: var int): seq[NwtNode]
proc astAstOne(token: NwtNode): NimNode
proc astAst(tokens: seq[NwtNode]): seq[NimNode]
proc includeNwt(nodes: var seq[NwtNode], path: string) {.compileTime.}


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
    else:
      echo "[FS] Not catched:", token
    # elif token.tokenType == NwtComment:
    #   result.add FSNode(kind: FsComment, value: token.value)


proc parseSsIf(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the if that we got called about
  result = NwtNode(kind: NwtNodeKind.NIf)
  result.ifStmt = elem.value
  pos.inc # skip the if
  var ifstate = IfState.InThen
  while pos < fsTokens.len:
    elem = fsTokens[pos]
    if elem.kind == FsIf:
      # echo "open new if"
      # TODO open a new if; where to put the parsed node from the recursive if parser??
      #### TODO pack this into func/template
      if ifState == IfState.InThen:
        result.nnThen.add parseSecondStep(fsTokens, pos) ## TODO should be parseSecondStep
      if ifState == IfState.InElse:
        result.nnElse.add parseSecondStep(fsTokens, pos) ## TODO should be parseSecondStep
      if ifState == IfState.InElif:
        result.nnElif[^1].elifBody.add parseSecondStep(fsTokens, pos) ## TODO should be parseSecondStep
    elif elem.kind == FsElif:
      ifstate = IfState.InElif
      result.nnElif.add NwtNode(kind: NElif, elifStmt: elem.value)
    elif elem.kind == FsElse:
      ifstate = IfState.InElse
    elif elem.kind == FsEndif:
      break
    else:
      if ifState == IfState.InThen:
        result.nnThen &= parseSecondStepOne(fsTokens, pos) #addCorrectNode(elem)
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
    echo fsTokens[pos .. ^1]
    elem = fsTokens[pos]
    if elem.kind == FsEndWhile:
      break
    else:
      result.whileBody &= parseSecondStepOne(fsTokens, pos)

proc parseSsFor(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos] # first is the while that we got called about
  result = NwtNode(kind: NwtNodeKind.NFor)
  result.forStmt = elem.value
  while pos < fsTokens.len:
    pos.inc # skip the while
    # echo fsTokens[pos .. ^1]
    elem = fsTokens[pos]
    if elem.kind == FsEndFor:
      break
    else:
      result.forBody &= parseSecondStepOne(fsTokens, pos)

proc parseSsBlock(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  let blockName = elem.value
  result = NwtNode(kind: NwtNodeKind.NBlock, blockName: blockName)
  echo fmt"BLOCK START: '{elem.value}' @ {pos}"
  while pos < fsTokens.len:
    pos.inc # skip the block
    elem = fsTokens[pos]
    if elem.kind == FsEndBlock:
      echo fmt"BLOCK END: '{elem.value}' @ {pos}"
      # pos.inc # skip the endblock
      break
    else:
      result.blockBody &= parseSecondStepOne(fsTokens, pos)
  echo result

proc parseSsExtends(fsTokens: seq[FsNode], pos: var int): NwtNode =
  var elem: FsNode = fsTokens[pos]
  let extendsPath = elem.value.strip(true, true, {'"'})
  result = NwtNode(kind: NwtNodeKind.NExtends, extendsPath: extendsPath)
  echo fmt"EXTENDS: '{extendsPath}' @ {pos}"

  # TODO this must be in a proc (called often in this parser)
  # var str = staticRead(extendsPath)
  # var extendedTemplate: seq[NwtNode] = @[]
  # var lexerTokens = toSeq(nwtTokenize(str))
  # var firstStepTokens = parseFirstStep(lexerTokens)
  # var pos = 0
  # var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  # for token in secondsStepTokens:
  #   extendedTemplate.add token
  # gExtends[extendsPath] = extendedTemplate
  ############

  return NwtNode(kind: NExtends, extendsPath: extendsPath)

converter singleNwtNodeToSeq(nwtNode: NwtNode): seq[NwtNode] =
  return @[nwtNode]

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
      return NwtNode(kind: NVariable, variableBody: fsToken.value) # TODO choose right NwtNodeKind
    elif fsToken.kind == FsEval:
      return NwtNode(kind: NEval, evalBody: fsToken.value) # TODO choose right NwtNodeKind
    elif fsToken.kind == FsBlock:
      return parseSsBlock(fsTokens, pos)
    elif fsToken.kind == FsExtends:
      return parseSsExtends(fsTokens, pos)
    elif fsToken.kind == FsImport:
        includeNwt(result, fsToken.value)

    else:
      echo "[SS] NOT IMPL: ", fsToken


proc includeNwt(nodes: var seq[NwtNode], path: string) {.compileTime.} =
  {.push experimental: "vmopsDanger".} # should work in devel!
  debugEcho "FOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO"
  # let basePath = staticExec("""pathHelper.exe""")

  # must be build with --experimental:vmopsDanger
  const basePath = getCurrentDir() # staticExec("pwd").strip().strip(leading = true, chars = {'/'})
  echo "BASE PATH ========:", basePath
  # var str = staticRead(path.strip(true, true, {'"'}) ) # TODO the static path is a problem...

  #### TODO AAAARGH this is so annoying....
  var str = staticRead( basePath  / path.strip(true, true, {'"'}) )
  # var str = staticRead("asdjfaklsdjf")

  var lexerTokens = toSeq(nwtTokenize(str))
  var firstStepTokens = parseFirstStep(lexerTokens)
  var pos = 0
  var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  for secondStepToken in secondsStepTokens:
    nodes.add secondStepToken

proc parseSecondStep*(fsTokens: seq[FSNode], pos: var int): seq[NwtNode] =
  echo "parseSecondStep #########################"
  while pos < fsTokens.len:
    ## TODO TEST IF THIS IS GOOD HERE
    ## this is include
    let token = fsTokens[pos]
    echo token.kind
    # if token.kind == FsImport:
    #   # pos.inc
    #   # TODO this whole block could be removed??????
    #   echo "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH"
    #   result.includeNwt(token.value)
    # else:
    result &= parseSecondStepOne(fsTokens, pos)
    pos.inc # skip the current elem (test if the inner procs should forward)



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
  result[0][2] = newStmtList(astAst(token.forBody)) # overwrite discard with real for body

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
    # for blockNode in gBlocks[token.value]:
    return parseStmt("discard")

  else:
    raise newException(ValueError, "cannot convert to ast:" & $token.kind)
    discard
  # elif token.kind == NImport:
  #   return


proc astAst(tokens: seq[NwtNode]): seq[NimNode] =
  for token in tokens:
    result.add astAstOne(token)

macro compileTemplateStr*(str: typed): untyped =
  var lexerTokens = toSeq(nwtTokenize(str.strVal))
  var firstStepTokens = parseFirstStep(lexerTokens)
  var pos = 0
  var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  when defined(dumpNwtAst): echo secondsStepTokens
  result = newStmtList()
  for token in secondsStepTokens:
    result.add astAstOne(token)


macro compileTemplateFile*(path: static string): untyped =
  let str = staticRead(path)
  # let pathn = newNimNode(nnkStrLit)
  # pathn.strVal = str
  # compileTemplateStr(str)
  ## TODO Why can't i call the other template?
  var lexerTokens = toSeq(nwtTokenize(str))
  var firstStepTokens = parseFirstStep(lexerTokens)
  var pos = 0
  var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  when defined(dumpNwtAst): echo secondsStepTokens

  ## TODO extend must be the first token, but
  ## strings can come before extend (for documentation purpose)
  if secondsStepTokens[0].kind == NExtends:
    echo "===== THIS TEMPLATE EXTENDS ====="
    # Load master template
    let masterStr = staticRead( parentDir(path) / secondsStepTokens[0].extendsPath)
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
    # insert THIS template to the masters blocks
    # render the whole template
  else:
    result = newStmtList()
    for token in secondsStepTokens:
      result.add astAstOne(token)
  # echo "gExtends: ", gExtends
  # echo "gBlocks: ", gBlocks

# when isMainModule:
#   expandMacros:
#     var result = ""
#     compileTemplateStr("{{foo}}baa{% idx.inc() %}{# a comment #}{%if foo() == baa()%}baa{{BAA}}{%elif true == true%}elif branch{%elif false == false%}elif branch2{%else%}ELSEBRANCH{%endif%}    {%for idx in 0..10%}{%if true%}{{TRAA}}{%endif%}{%endfor%}   {% var loop = 0%}{%while loop < 10%} {% loop.inc %} {%endwhile%} ")




when isMainModule:
  discard

  # block:
  #   proc testMe(a = 1, ONE = "ONE", TWO = "TWO", THREE = "THREE", ELSE = "ELSE", sex = "male"): string =
  #     compileTemplateStr3 """{% if a == 1 %}a{% if sex == "male"%}HE{%else%}SHE{%endif%}is one{{ONE}}{% elif a == 2 %}a is two{{TWO}}{% elif a == 3 %}a is three{{THREE}}{% else %}a is something else{{ELSE}}{%endif%}"""
  #   assert "aHEis one-->ONE<--" == testMe(a = 1, sex = "male", ONE = "-->ONE<--")
  #   assert "aSHEis one-->ONE<--" == testMe(a = 1, sex = "female", ONE = "-->ONE<--")
  #   assert "a is twoTWO" == testMe(a = 2)
  #   assert "a is threeTHREE" == testMe(a = 3)

  block:
    discard
    # echo onlyFirstAndSecond("""{{foo}}{% while idx < 10 %}idx is: {{idx}}{%idx.inc%}{% endwhile %}baa{{zaa}}""")
    # echo onlyFirstAndSecond("""{{foo}}{% while idx < 10 %}idx is: {{idx}}{%idx.inc%}{% endwhile %}baa{{zaa}}""")
    # echo onlyFirstAndSecond("""{% while isAA() %}AA{%while isBB()%}BB{%while isCC()%}CC{%endwhile%}{%endwhile%}{% endwhile %}baa{{zaa}}""")
    # echo onlyFirstAndSecond("""{%if elems.len > 0%}{% while isFoo() %}FOO{% endwhile %}{%endif%}""")

    # echo onlyFirstAndSecond("""{% for idx in 0..10 %}{{idx}}<br>{%endfor%}""")

    # ## Wrong render but ast looks good...
    # echo onlyFirstAndSecond("""{%if elems.len > 0%}{% while isFoo() %}FOO{%if true%}true{%endif%}{% endwhile %}{%endif%}baa""")
    # echo onlyFirstAndSecond("""
    #   {%if elems.len > 0%}
    #     {% while isFoo() %}
    #       FOO
    #       {%if true%}
    #         true
    #       {%endif%}
    #     {% endwhile %}
    #   {%endif%}
    #   baa""")



    # proc testMe(): string =
    #   compileTemplateStr3 """{% while idx < 10 %}idx is: {{idx}}{%idx.inc%}{%endwhile%}"""
    # echo testMe()

    # # Rendered wrong, ast seems ok
    # proc testMe(): string =
    #   compileTemplateStr3 """{%while true%}{% for idx in 0..10 %}{{idx}}<br>{%endfor%}{%endwhile%}"""
    # echo testMe()

    # echo prettyNwt("""{% var foo: string = ":D" %}{% for idx in 0..10 %}{% foo &= $idx %}foo={{foo}}<br>{%endfor%}""")


    # type TestObj = object
    #   foo: string
    #   baa: int
    # proc testObj(tobj: TestObj): string =
    #   compileTemplateStr3 """{% for idx in 0 .. tobj.baa  %}{{idx}}{{tobj.foo}}{%endfor%}"""
    # echo testObj(TestObj(foo:"_FOO", baa: 20))

    # proc testMe2(): string =
    #   compileTemplateStr3 """{% var foo: string = ":D" %}{% for idx in 0..10 %}{% foo &= $idx %}foo={{foo}}<br>{%endfor%}"""
    # echo testMe2()

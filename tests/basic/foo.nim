include ../../src/nimja/parser
# import ../../src/nimja/lexer

proc compile2(str: string, templateCache: var Deque[seq[NwtNode]]): seq[NwtNode] =
  var secondsStepTokens = loadCache(str)
  let foundExtendAt = validExtend(secondsStepTokens)
  if foundExtendAt > -1:
    echo "EXTENDS"
    templateCache.addFirst secondsStepTokens
    # compile2(loadCacheFile(getScriptDir() / secondsStepTokens[foundExtendAt].extendsPath))
    let ext = read(getScriptDir() / secondsStepTokens[foundExtendAt].extendsPath)
    discard compile2(ext, templateCache)
  else:
    templateCache.addFirst secondsStepTokens

proc findAll(nwtns: seq[NwtNode], kind: NwtNodeKind): seq[NwtNode] =
  for nwtn in nwtns:
    if nwtn.kind == kind: result.add nwtn

proc recursiveFindAllBlocks(nwtns: seq[NwtNode]): seq[NwtNode] =
  for nwtn in nwtns.findAll(NBlock):
    result.add nwtn
    result.add recursiveFindAllBlocks(nwtn.blockBody)


proc fillBlocks(nodes: seq[NwtNode], blocks: Table[string, seq[NwtNode]]): seq[NwtNode] =
  for node in nodes:
    if node.kind == NBlock:
      for bnode in blocks[node.blockName]:
        if bnode.kind == NBlock:
          result.add fillBlocks(bnode, blocks)
        else:
          result.add bnode
    else:
      result.add node


# macro compileTemplateStr*(str: typed, iter: static bool = false): untyped =
macro compileTemplateStr*(str: typed, iter: static bool = false): untyped =
  var templateCache = initDeque[seq[NwtNode]]()
  # echo compile2("""{% extends "doubleExtends/outer.nwt" %}{%block outer%}inner{%endblock%}""", templateCache)
  echo compile2(str.strVal, templateCache)
  var blocks: Table[string, seq[NwtNode]]
  for idx, tmp in templateCache.pairs():
    echo idx, " :", tmp
    for nwtn in tmp.recursiveFindAllBlocks():
      blocks[nwtn.blockName] = nwtn.blockBody
    echo blocks
  var base = templateCache[0]
  let filledBlocks = fillBlocks(base, blocks)
  # echo filledBlocks

  result = newStmtList()
  for nwtNode in filledBlocks:
    result.add astAstOne(nwtNode)

# macro compileTemplateFile*(path: typed, iter: static bool = false): untyped =
macro compileTemplateFile*(path: static string, iter: static bool = false): untyped =
  var str = read(path)
  # compileTemplateStr(str)
  var templateCache = initDeque[seq[NwtNode]]()
  # echo compile2("""{% extends "doubleExtends/outer.nwt" %}{%block outer%}inner{%endblock%}""", templateCache)
  echo compile2(str, templateCache)
  var blocks: Table[string, seq[NwtNode]]
  for idx, tmp in templateCache.pairs():
    echo idx, " :", tmp
    for nwtn in tmp.recursiveFindAllBlocks():
      blocks[nwtn.blockName] = nwtn.blockBody
    echo blocks
  var base = templateCache[0]
  let filledBlocks = fillBlocks(base, blocks)
  # echo filledBlocks

  result = newStmtList()
  for nwtNode in filledBlocks:
    result.add astAstOne(nwtNode)




proc foo(): string =
  compileTemplateStr("""{% extends "doubleExtends/outer.nwt" %}{%block outer%}inner{%endblock%}""")

# echo foo()


# proc fillBlocks()

# compileTemplateFile(getScriptDir() / "doubleExtends" / "outer.nwt")
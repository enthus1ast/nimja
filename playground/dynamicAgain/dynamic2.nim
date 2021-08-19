# from nimja/parser import compile, NwtNode
include nimja/parser
# import
import
  compiler/[
    ast, pathutils, vm, scriptconfig,
    modulegraphs, options, idents, condsyms, sem, modules,
    lineinfos, astalgo, vmdef, vmconv
  ]

import compiler/parser except openParser
import
  std/[strutils, strformat, os, macros]

import hnimast, hnimast/obj_field_macros
# import hpprint





# while true:
#   let line = stdin.readLine()
#   # echo compile("foo{#baa#}baz")
#   echo compile(line)



############################################################
include compiler/passes
let stdlib* = getHomeDir() / ".choosenim/toolchains/nim-1.4.8/lib"

var
  conf = newConfigRef()
  cache = newIdentCache()
  graph = newModuleGraph(cache, conf)

conf.libpath = AbsoluteDir stdlib

for p in @[
    stdlib,
    stdlib / "pure",
    stdlib / "pure" / "collections",
    stdlib / "pure" / "concurrency",
    stdlib / "impure",
    stdlib / "js",
    stdlib / "packages" / "docutils",
    stdlib / "std",
    stdlib / "core",
    stdlib / "posix",
    stdlib / "windows",
    stdlib / "wrappers",
    stdlib / "wrappers" / "linenoise",
    # "C:/Users/david/projects/nimja/src/"
  ]:
  conf.searchPaths.add(AbsoluteDir p)

conf.cmd = cmdInteractive
conf.errorMax = high(int)
conf.structuredErrorHook =
  proc (config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) =
    echo &"{info.line}:{info.col} {msg}"
    assert false
    # if not (
    #   "instantiation from here" in msg
    #   # "type mismatch" in msg
    # ):
    #   assert false


initDefines(conf.symbols)

defineSymbol(conf.symbols, "nimscript")
defineSymbol(conf.symbols, "nimconfig")

registerPass(graph, semPass)
registerPass(graph, evalPass)

var m = graph.makeModule(AbsoluteFile"scriptname.nim")
incl(m.flags, sfMainModule)
graph.vm = setupVM(m, cache, "scriptname.nim", graph)

graph.compileSystemModule()

proc processModule3(
    graph: ModuleGraph; module: PSym, n: PNode, a: var TPassContextArray) =
  discard processTopLevelStmt(graph, n, a)

proc getIdent(graph: ModuleGraph, name: string): PNode =
  newIdentNode(graph.cache.getIdent(name), TLineInfo())

proc astAstOneDyn(token: NwtNode): PNode

proc astAstDyn(tokens: seq[NwtNode]): seq[PNode] =
  for token in tokens:
    result.add astAstOneDyn(token)

proc astVarDyn(token: NwtNode): PNode =
  return nkStmtList.newTree(
    nkCall.newTree(
      graph.getIdent("add"),
      graph.getIdent("result"),
      nkPrefix.newTree(
        graph.getIdent("$"),
        graph.getIdent(token.variableBody)
      )
    )
  )

proc astStrDyn(token: NwtNode): PNode =
  return nkStmtList.newTree(
    nkCall.newTree(
      graph.getIdent("add"),
      graph.getIdent("result"),
      newPLit(token.strBody)
    )
  )

proc astEvalDyn(token: NwtNode): PNode =
  return parseString(token.evalBody, cache, conf)


proc astIfDyn(token: NwtNode): PNode =
    var ifstmt = nkIfStmt.newTree()
    ifstmt.add:
      nkElifBranch.newTree(
        parseString(token.ifStmt, cache, conf),
        nkStmtList.newTree(
          astAstDyn(token.nnThen)
        )
      )

    ## Add the elif nodes
    for elifToken in token.nnElif:
      ifstmt.add:
        nkElifBranch.newTree(
          parseString(elifToken.elifStmt, cache, conf),
          nkStmtList.newTree(
            astAstDyn(elifToken.elifBody)
          )
        )

    # Add the else node
    if token.nnElse.len > 0:
      ifstmt.add:
        nkElse.newTree(
          nkStmtList.newTree(
            astAstDyn(token.nnElse)
          )
        )
    return ifstmt

proc astForDyn(token: NwtNode): PNode =
  let easyFor = "for " & token.forStmt & ": discard" # `discard` to make a parsable construct
  let forstmt = parseString(easyFor, cache, conf)
  forstmt[0][2] = newPStmtList(astAstDyn(token.forBody)) # overwrite discard with real `for` body
  return forstmt

proc astWhileDyn(token: NwtNode): PNode =
  return nkStmtList.newTree(
    nkWhileStmt.newTree(
      parseString(token.whileStmt, cache, conf),
      nkStmtList.newTree(
        astAstDyn(token.whileBody)
      )
    )
  )

proc astAstOneDyn(token: NwtNode): PNode =
  case token.kind
  of NVariable: return astVarDyn(token)
  of NStr: return astStrDyn(token)
  of NEval: return astEvalDyn(token)
  of NIf: return astIfDyn(token)
  of NFor: return astForDyn(token)
  of NWhile: return astWhileDyn(token)
  # of NExtends: discard # return parseStmt("discard")
  # of NBlock: discard # return parseStmt("discard")
  else: raise newException(ValueError, "cannot convert to ast:" & $token.kind)



echo astAstDyn(compile("foo{#baa#}baz"))
###



graph.vm.PEvalContext().registerCallback(
  "setOutResult",
  proc(args: VmArgs) =
    echo "Called custom proc with arg [", args.getString(0), "]"
)

proc empty(): PNode = nkEmpty.newTree()


macro pnodeGenRepr*(node: untyped) =
  proc aux(n: NimNode, res: var string, level: int) =
    res.add "  ".repeat(level)
    case n.kind:
      of nnkIdent:
        res.add "graph.getIdent(\""
        res.add n.strVal()
        res.add "\")"

      of nnkCharLit .. nnkUInt64Lit:
        res.add "newIntNode("
        res.add ($n.kind)[1 .. ^1]
        res.add ", "
        res.add $n.intVal()
        res.add ")"

      of nnkFloatLit .. nnkFloat128Lit:
        res.add "newFloatNode"
        res.add $n.floatVal()
        res.add ", "
        res.add ($n.kind)[1 .. ^1]
        res.add ")"

      of nnkStrLit .. nnkTripleStrLit:
        res.add "newStrNode(\""
        res.add n.strVal()
        res.add "\", "
        res.add ($n.kind)[1 .. ^1]
        res.add ")"

      of nnkEmpty:
        res.add "nkEmpty.newTree()"

      else:
        res.add ($n.kind)[1..^1]
        res.add ".newTree(\n"
        for idx, sub in n:
          aux(sub, res, level + 1)
          if idx < n.len - 1:
            res.add ",\n"

        res.add ")"

  var res: string
  aux(node, res, 1)
  echo res

pnodeGenRepr:
  add(result, $myVar)
# if true: quit()
proc parseNode(graph: ModuleGraph, module: PSym, s: PllStream): PNode =
  var p: Parser
  openParser(p, module.fileIdx, s, graph.cache, graph.config)

  result = parseTopLevelStmt(p)

  closeParser(p)

proc processModule2(
    graph: ModuleGraph; module: PSym,
    s: PLLStream, a: var TPassContextArray) =
  var
    p: Parser
    fileIdx = module.fileIdx

  openParser(p, fileIdx, s, graph.cache, graph.config)

  while true:
    if graph.stopCompile(): break
    var n = parseTopLevelStmt(p)
    if n.kind == nkEmpty: break
    if n.kind in imperativeCode:
      # read everything until the next proc declaration etc.
      var sl = newNodeI(nkStmtList, n.info)
      sl.add n
      var rest: PNode = nil
      while true:
        var n = parseTopLevelStmt(p)
        if n.kind == nkEmpty or n.kind notin imperativeCode:
          rest = n
          break
        sl.add n
      if not processTopLevelStmt(graph, sl, a): break
      if rest != nil:
        if not processTopLevelStmt(graph, rest, a): break

    else:
      if not processTopLevelStmt(graph, n, a): break

var a: TPassContextArray
openPasses(graph, a, m)


processModule2(graph, m, llStreamOpen("""
proc setOutResult[T](arg: T) = discard
var result = ""
var ii = 123
"""), a)

while true:
  let line = stdin.readLine().strip()
  if line == "": continue

  let nwtNodes = compile(line)
  if nwtNodes.len == 0: continue
  # var fun = astAstOneDyn(compile("foo{#baa#}baz")[0])
  # var fun = astAstOneDyn(nwtNodes[0])
  var fun = newPStmtList()
  for node in nwtNodes:
    fun.add astAstOneDyn(node)
  # var fun = astAstDyn(nwtNodes)
  var cc = "compiled"
  processModule3(graph, m, fun, a)

  processModule2(graph, m, llStreamOpen("""
echo "##########"
echo result
echo "##########"
setOutResult(result)
result = ""
  """), a)


closePasses(graph, a)


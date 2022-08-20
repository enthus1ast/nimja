# TODO:
# - NProc
# - importnimja works only the first time.
#   - -d:nwtCacheOff   !!
# - block does not work



#### For dynamic the caches must work differently
#### and reparse if changed (file)

include nimja/parser
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

import pnodeHelper


############################################################
include compiler/passes
let stdlib* = getHomeDir() / ".choosenim/toolchains/nim-1.6.4/lib"

var
  conf = newConfigRef()
  cache = newIdentCache()
  graph = newModuleGraph(cache, conf)

conf.libpath = AbsoluteDir stdlib

for path in @[
    stdlib,
    stdlib / "pure",
    stdlib / "pure" / "collections",
    stdlib / "pure" / "concurrency",
    # stdlib / "impure",
    # stdlib / "js",
    # stdlib / "packages" / "docutils",
    stdlib / "std",
    stdlib / "core",
    # stdlib / "posix",
    # stdlib / "windows",
    # stdlib / "wrappers",
    # stdlib / "wrappers" / "linenoise",
    # "C:/Users/david/projects/nimja/src/"
  ]:
  conf.searchPaths.add(AbsoluteDir path)

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

var idgen = idGeneratorFromModule(m)

graph.vm = setupVM(m, cache, "scriptname.nim", graph, idgen)

graph.compileSystemModule()

proc processModule3(
    graph: ModuleGraph; module: PSym, n: PNode, a: var TPassContextArray) =
  discard processTopLevelStmt(graph, n, a)

proc getIdent(graph: ModuleGraph, name: string): PNode =
  newIdentNode(graph.cache.getIdent(name), TLineInfo())


################################################
## PNode generation
################################################

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

proc astProcDyn(token: NwtNode, procStr = "proc"): PNode =
  ## How to set the body of a pnode??
  discard
  # result = newProcNode(nkProcDef, TLineInfo(), astAstDyn(token.procBody), )
  let easyProc =  procStr & " " & token.procHeader & " discard"
  result = parseString(easyProc, cache, conf) # dummy to build valid procBody
  echo "astProcDyn ####################"
  echo result
  echo "####################"
  # echo repr result.body
  echo "^^^^^^^^^^^^^^^^^^"
  # pnodeGenRepr result
  # result.sons[0][6] = newPStmtList(
  #   astAstDyn(token.procBody) # fill the proc body with content
  # )

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
  of NProc: return astProcDyn(token, procStr = "proc")
  else: raise newException(ValueError, "cannot convert to ast:" & $token.kind)

###



# graph.vm.PEvalContext().registerCallback(
#   "setOutResult",
#   proc(args: VmArgs) =
#     echo "Called custom proc with arg [", args.getString(0), "]"
# )

proc empty(): PNode = nkEmpty.newTree()

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
    if n.kind == nkEmpty: break # end of stream
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
# openPasses(graph, a, m)

proc repl() =

  graph.vm.PEvalContext().registerCallback(
    "setOutResult",
    proc(args: VmArgs) =
      echo "BB Called custom proc with arg [", args.getString(0), "]"
  )


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
# repl()

proc evaluateTemplateStr*(str: string, foo: int): string =
  ## dynamically evaluates and runs a template string (on runtime)
  ## this is the dynamic equivalent to `compileTemplateStr()`
  openPasses(graph, a, m, idgen)
  # echo foo
  if graph.isNil: echo "graph is nil"; quit()
  if m.isNil: echo "m is nil"; quit()
  if conf.isNil: echo "conf is nil"; quit()

  # var res = ""
  # var resP = addr res
  var res = ""
  graph.vm.PEvalContext().callbacks = @[] ## remove old callbacks TODO find better way?!
  graph.vm.PEvalContext().registerCallback(
    "setOutResult",
    proc(args: VmArgs) {.closure.} =
      echo "AA Called custom proc with arg [", args.getString(0), "]"
      # resP[] = args.getString(0)
      res = args.getString(0)
  )

  # Prepare environment
  processModule2(graph, m, llStreamOpen("""
proc setOutResult[T](arg: T) = discard
var result = ""
var ii = 123
#var foo: int = 111
  """), a)

  #echo graph.getIdent("foo")
  # Make parameters available to VM
  # TODO how to get ALL visible vars?
  # processModule3(graph, m,
  #   nkBlockStmt.newTree(nkEmpty.newTree(),
  #     nkStmtList.newTree(
  #       # Pass arguments to the environment
  #       nkLetSection.newTree(
  #         nkIdentDefs.newTree(newPIdent("aaa"), nkEmpty.newTree(), vmconv.toLit(foo)),
  #         # nkIdentDefs.newTree( newIdentNode("foo"), nkEmpty.newTree(), vmconv.toLit(foo)),
  #         # nkIdentDefs.newTree(graph.getIdent("ii"), nkEmpty.newTree(), vmconv.toLit(ii))
  #       )
  #     )
  #   )
  # , a)
  # processModule3(graph, m,
  #   nkStmtList.newTree(
  #     # Pass arguments to the environment
  #     nkVarSection.newTree(
  #       nkIdentDefs.newTree(newPIdent("aaa"), nkEmpty.newTree(), vmconv.toLit(foo)),
  #       # nkIdentDefs.newTree( newIdentNode("foo"), nkEmpty.newTree(), vmconv.toLit(foo)),
  #       # nkIdentDefs.newTree(graph.getIdent("ii"), nkEmpty.newTree(), vmconv.toLit(ii))
  #     )
  #   )
  # , a)

  # var varname = newSym(skLet, "aaa")
  # graph.vm.setGlobalValue(newSym(skVar, "aaa", newIntNode(foo))


  let nwtNodes = compile(str)
  when defined(dumpNwtAst): echo nwtNodes
  when defined(dumpNwtAstPretty): echo nwtNodes.pretty
  var fun = newPStmtList()
  for node in nwtNodes:
    fun.add astAstOneDyn(node)
  processModule3(graph, m, fun, a)

  processModule2(graph, m, llStreamOpen("""
#echo "##########"
#echo result
#echo "##########"
setOutResult(result)
result = ""
    """), a)


  closePasses(graph, a)
  # resP[]
  # result = resP[]
  return res

proc evaluateTemplateStr*(str: string): string =
  return evaluateTemplateStr(str, 1337)


template dynamicFile*(path: string, foo: int) =
  return evaluateTemplateStr(readFile(path), foo)





# repl()

# closePasses(graph, a)

when isMainModule:
  import print

  when false:
    # Test pnode generation
    echo astAstDyn(compile("foo{#baa#}baz"))
    echo astAstDyn(compile("""{%if true%}true{%else%}false{%endif%}"""))

    proc renderFoo(): string =
      return evaluateTemplateStr("{%if true%}true{%else%}false{%endif%}", 1337)
    print renderFoo()

    proc renderBaa(): string =
      return evaluateTemplateStr("{%for idx in 0..10%}<li>{{idx}}</li>\n{%endfor%}", 1337)
    print renderBaa()

  when true:

    proc renderFoo(): string =
      return evaluateTemplateStr("<h1>{{aaa}}</h1>", 1337)
    echo renderFoo()

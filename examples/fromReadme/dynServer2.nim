include compiler/passes

import
  compiler/[
    nimeval, ast, astalgo, pathutils, vm, scriptconfig,
    modulegraphs, options, idents, condsyms, sem, modules, llstream,
    lineinfos, astalgo, msgs, parser, idgen, vmdef
  ]

import
  std/[strutils, strformat, parseutils, os]


let stdlib* = getHomeDir() / ".choosenim/toolchains/nim-1.4.8/lib"

var
  conf = newConfigRef()
  cache = newIdentCache()
  graph = newModuleGraph(cache, conf)

conf.libpath = AbsoluteDir stdlib

for p in @[
    stdlib,
    stdlib / "pure",
    stdlib / "core",
    stdlib / "pure" / "collections"
  ]:
  conf.searchPaths.add(AbsoluteDir p)

conf.cmd = cmdInteractive
conf.errorMax = high(int)
conf.structuredErrorHook =
  proc (config: ConfigRef; info: TLineInfo; msg: string; severity: Severity) =
    assert false, &"{info.line}:{info.col} {msg}"


initDefines(conf.symbols)

defineSymbol(conf.symbols, "nimscript")
defineSymbol(conf.symbols, "nimconfig")

registerPass(graph, semPass)
registerPass(graph, evalPass)

var m = graph.makeModule(AbsoluteFile"scriptname.nim")
incl(m.flags, sfMainModule)
graph.vm = setupVM(m, cache, "scriptname.nim", graph)
graph.compileSystemModule()

proc processModule3(graph: ModuleGraph; module: PSym, n: PNode) =
  var a: TPassContextArray
  openPasses(graph, a, module)

  discard processTopLevelStmt(graph, n, a)

  closePasses(graph, a)

proc getIdent(graph: ModuleGraph, name: string): PNode =
  newIdentNode(graph.cache.getIdent(name), TLineInfo())


graph.vm.PEvalContext().registerCallback(
  "customProc",
  proc(args: VmArgs) =
    echo "Called custom proc with arg [", args.getString(0), "]"
)

# import nimja, macros


proc empty(): PNode = nkEmpty.newTree()

# processModule3(graph, m, newCall(graph.getIdent("compileTemplateStr"), newLit("foo")))

processModule3(graph, m,
  nkStmtList.newTree(
    nkProcDef.newTree(
      graph.getIdent("customProc"),
      empty(),
      empty(),
      nkFormalParams.newTree(
        empty(),
        nkIdentDefs.newTree(graph.getIdent("arg"), graph.getIdent("string"), empty())),
      empty(),
      empty(),
      nkStmtList.newTree(nkDiscardStmt.newTree(empty()))),
  nkCall.newTree(graph.getIdent("customProc"), newStrNode(nkStrLit, "SSSSSSSSSSSSS"))))
import std/dynlib, asyncdispatch, osproc, os, times,
  strformat, strutils, macros, tables

export dynlib

type
  Exec* = proc(cw: ChangeWatcher)
  Paths* = Table[string, Time]
  ChangeWatcher* = ref object
    checkTimeout*: int
    libfile*: string
    lib*: pointer
    patterns*: seq[string]
    paths*: Paths
    exec*: Exec

template updateFile(path: string) =
  if not cw.paths.hasKey(path):
    echo "NEW: ", path
    cw.paths[path] = getLastModificationTime(path)
    result.add path
  else:
    let cur = getLastModificationTime(path)
    if cur > cw.paths[path]:
      echo "CHANGED: ", path
      cw.paths[path] = cur
      result.add path

proc walk(cw: ChangeWatcher): seq[string] =
  for pattern in cw.patterns:
    if pattern.fileExists():
      updateFile(pattern)
    else:
      for path in walkDirRec(pattern):
        updateFile(path)

proc doRecompile*(cw: ChangeWatcher) =
  echo execShellCmd(fmt"nim c --app:lib {getAppDir() / cw.libfile}.nim")

proc newChangeWatcher*(patterns: seq[string], exec: Exec = doRecompile, checkTimeout = 1_000,
    libfile = "tmpls.nim"): ChangeWatcher =
  result = ChangeWatcher()
  result.exec = exec
  result.checkTimeout = checkTimeout
  result.libfile = splitFile(libfile).name
  result.patterns = patterns
  result.patterns.add libfile # always add the libfile
  result.doRecompile() # compile the lib once on start
  result.lib = loadLib(DynlibFormat % result.libfile)

proc recompile*(cw: ChangeWatcher) {.async.} =
  echo "Dynamic recompilation is on; watching:"
  for pattern in cw.patterns:
    echo "\t", pattern
  while true:
    var changed = cw.walk()
    if changed.len > 0:
      echo "CHANGED .. RECOMPILE"
      cw.lib.unloadLib()
      cw.doRecompile()
      cw.lib = loadLib(DynlibFormat % cw.libfile)
    await sleepAsync(cw.checkTimeout)

macro dyn*(kind, name: untyped, params: varargs[untyped]): untyped =
  var ps: string = ""
  for idx, param in params:
    var pp: string = repr param
    ps.add pp
    if idx < params.len - 1:
      ps.add ", "
  let cc = fmt"""cast[{$kind}](cw.lib.symAddr("{$name}"))({ps})"""
  return parseStmt(cc)

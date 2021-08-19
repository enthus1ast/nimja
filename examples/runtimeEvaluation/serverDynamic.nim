import os, strutils
import prologue
# import nimja/parser
# import nimja/playground/dynamicAgain/dynamic2

import
  compiler/[
    ast, pathutils, vm, scriptconfig,
    modulegraphs, options, idents, condsyms, sem, modules,
    lineinfos, astalgo, vmdef, vmconv
  ]

import """C:\Users\david\projects\nimja\playground\dynamicAgain\dynamic2.nim"""

# type
#   User = object
#     name: string
#     lastname: string
#     age: int

# We use the new UserContext feature of prologue.
# type
#   UserContext = ref object of Context
#     users: seq[User]

# method extend(ctx: UserContext) =
#   ctx.users = @[
#     User(name: "Katja", lastname: "Kopylevych", age: 32),
#     User(name: "David", lastname: "Krause", age: 32),
#   ]

proc renderIndex(): string =
  # dynamicFile(getScriptDir() / "index.nwt")
  dynamicFile(getScriptDir / "index.nwt")
  # return "foo"

# proc renderUser(title: string, idx: int, users: seq[User]): string =
#   let user = users[idx]
#   compileTemplateFile(getScriptDir() / "user.nwt")

# proc renderError(title: auto, code: HttpCode, users: seq[User]): string =
#   ## title is `auto` here; nim generics work as well!
#   compileTemplateFile(getScriptDir() / "error.nwt")

proc hello*(ctx: Context) {.async, gcsafe.} =
  # resp renderIndex("someTitle", ctx.users)
  resp renderIndex()

# proc user*(ctx: UserContext) {.async.} =
#   var idx = 0
#   try:
#     idx = parseInt(ctx.getPathParams("idx", "0"))
#     resp renderUser("someTitle", idx, ctx.users)
#   except:
#     resp "", Http404

# proc go404*(ctx: UserContext) {.async.} =
#   resp renderError(title = Http404, code = Http404, ctx.users), Http404

let app = newApp()
app.get("/", hello)
# app.get("/users/{idx}", user)
# app.registerErrorHandler(Http404, go404)
# app.run(UserContext)
app.run()
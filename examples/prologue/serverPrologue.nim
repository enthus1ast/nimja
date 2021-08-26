discard """
action: "compile"
"""
import os, strutils
import prologue
import nimja/parser

type
  User = object
    name: string
    lastname: string
    age: int

# We use the new UserContext feature of prologue.
type
  UserContext = ref object of Context
    users: seq[User]

method extend(ctx: UserContext) =
  ctx.users = @[
    User(name: "Katja", lastname: "Kopylevych", age: 32),
    User(name: "David", lastname: "Krause", age: 32),
  ]

proc renderIndex(title: string, users: seq[User]): string =
  compileTemplateFile(getScriptDir() / "index.nwt")

proc renderUser(title: string, idx: int, users: seq[User]): string =
  let user = users[idx]
  compileTemplateFile(getScriptDir() / "user.nwt")

proc renderError(title: auto, code: HttpCode, users: seq[User]): string =
  ## title is `auto` here; nim generics work as well!
  compileTemplateFile(getScriptDir() / "error.nwt")

proc hello*(ctx: UserContext) {.async.} =
  resp renderIndex("someTitle", ctx.users)

proc user*(ctx: UserContext) {.async.} =
  var idx = 0
  try:
    idx = parseInt(ctx.getPathParams("idx", "0"))
    resp renderUser("someTitle", idx, ctx.users)
  except:
    resp "", Http404

proc go404*(ctx: UserContext) {.async.} =
  resp renderError(title = Http404, code = Http404, ctx.users), Http404

let app = newApp()
app.get("/", hello)
app.get("/users/{idx}", user)
app.registerErrorHandler(Http404, go404)
app.run(UserContext)
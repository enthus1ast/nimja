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

method extend(ctx: Context) =
  UserContext(ctx).users = @[
    User(name: "Katja", lastname: "Kopylevych", age: 33),
    User(name: "David", lastname: "Krause", age: 33),
  ]

proc renderIndex(title: string, users: seq[User]): string =
  compileTemplateFile(getScriptDir() / "index.nwt")

proc renderUser(title: string, idx: int, users: seq[User]): string =
  let user = users[idx]
  compileTemplateFile(getScriptDir() / "user.nwt")

proc renderError(title: auto, code: HttpCode, users: seq[User]): string =
  ## title is `auto` here; nim generics work as well!
  compileTemplateFile(getScriptDir() / "error.nwt")

proc hello*(ctx: Context) {.async.} =
  resp renderIndex("someTitle", UserContext(ctx).users)

proc user*(ctx: Context) {.async.} =
  var idx = 0
  try:
    idx = parseInt(UserContext(ctx).getPathParams("idx", "0"))
    resp renderUser("someTitle", idx, UserContext(ctx).users)
  except:
    resp "", Http404

proc go404*(ctx: Context) {.async.} =
  resp renderError(title = Http404, code = Http404, UserContext(ctx).users), Http404

var app = newApp()
app.get("/", hello)
app.get("/users/{idx}", user)
app.registerErrorHandler(Http404, go404)
app.run(UserContext)

import os, strutils
import prologue
import nimja/parser

type
  User = object
    name: string
    lastname: string
    age: int

let users: seq[User] = @[
  User(name: "Katja", lastname: "Kopylevych", age: 32),
  User(name: "David", lastname: "Krause", age: 32),
]

proc renderIndex(title: string, users: seq[User]): string {.gcsafe.} =
  compileTemplateFile(getScriptDir() / "index.nwt")

proc renderUser(title: string, idx: int, users: seq[User]): string {.gcsafe.} =
  let user = users[idx]
  compileTemplateFile(getScriptDir() / "user.nwt")

proc hello*(ctx: Context) {.async, gcsafe.} =
  resp $renderIndex("someTitle", users)

proc user*(ctx: Context) {.async, gcsafe.} =
  var idx = 0
  try:
    idx = parseInt(ctx.getPathParams("idx", "0"))
    resp $renderUser("someTitle", idx, users)
  except:
    resp "not found", Http404

let app = newApp()
app.get("/", hello)
app.get("/users/{idx}", user)
app.run()
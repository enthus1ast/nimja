discard """
action: "compile"
"""
import os, strutils
import jester
import nimja/parser

type
  User = object
    name: string
    lastname: string
    age: int

const users = @[
  User(name: "Katja", lastname: "Kopylevych", age: 32),
  User(name: "David", lastname: "Krause", age: 32),
]

proc renderIndex(title: string, users: seq[User]): string =
  compileTemplateFile(getScriptDir() / "index.nimja")

proc renderUser(title: string, idx: int, users: seq[User]): string =
  let user = users[idx]
  compileTemplateFile(getScriptDir() / "user.nimja")

proc renderError(title: auto, code: HttpCode, users: seq[User]): string =
  ## title is `auto` here; nim generics work as well!
  compileTemplateFile(getScriptDir() / "error.nimja")

routes:
  get "/":
    resp renderIndex("someTitle", users)

  get "/users/@idx":
      var idx = 0
      idx = parseInt(@"idx")
      resp renderUser("someTitle", idx, users)

  get "/@notFound":
    resp renderError(title = Http404, code = Http404, users)

  error Exception:
    resp renderError(title = Http404, code = Http404, users)

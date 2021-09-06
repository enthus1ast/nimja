discard """
action: "compile"
"""
## compile this example with: --experimental:vmopsDanger or you will get
## Error: cannot 'importc' variable at compile time; getCurrentDirectoryW

import asynchttpserver, asyncdispatch
import nimja/parser
import os, random # os and random are later used in the templates, so imported here

type
  User = object
    name: string
    lastname: string
    age: int

proc renderIndex(title: string, users: seq[User]): string =
  ## the `index.nwt` template is transformed to nim code.
  ## so it can access all variables like `title` and `users`
  ## the return variable could be `string` or `Rope` or
  ## anything which has a `&=`(obj: YourObj, str: string) proc.
  compileTemplateFile(getScriptDir() / "index.nwt")

proc main {.async.} =
  var server = newAsyncHttpServer()

  proc cb(req: Request) {.async.} =

    # in the templates we can later loop trough this sequence
    let users: seq[User] = @[
      User(name: "Katja", lastname: "Kopylevych", age: 32),
      User(name: "David", lastname: "Krause", age: 32),
      User(name: "dank", lastname: "r4d", age: 27),
    ]
    await req.respond(Http200, renderIndex("index", users))

  server.listen Port(8080)
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(cb)
    else:
      poll()

asyncCheck main()
runForever()
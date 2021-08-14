import system/nimscript
import nimja
import os
import random

type
  User = object
    name: string
    lastname: string
    age: int

let users: seq[User] = @[
  User(name: "Katja", lastname: "Kopylevych", age: 32),
  User(name: "Katja", lastname: "Kopylevych", age: 32),
  User(name: "David", lastname: "Krause", age: 32),
  User(name: "Daasdfvid", lastname: "Krause", age: 32),
  # User(name: "Davidasdf", lastname: "Krause", age: 32),
  # User(name: "Davida", lastname: "Krause", age: 32),
  User(name: "Davidasdfafsdf", lastname: "Krause", age: 32),
]

var ret*: string = ""
# var ass*: auto = compileTemplateFile(getScriptDir() / "index.nwt")
proc foo(title: string, users: seq[User]): string =
  compileTemplateFile(getScriptDir() / "index.nwt")
ret = foo("title", users)
echo ret


# echo "fooA"
# echo 1+1
# echo :D
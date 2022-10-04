import macros

proc doStuffModule1*() =
  const foo = getProjectPath()
  echo "module1:", foo
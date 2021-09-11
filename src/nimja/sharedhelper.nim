import macros # for get project path

template read*(path: untyped): untyped =
  ## Internal helper, on compiletime this calls
  ## `staticRead`
  ## on runtime thils calls
  ## `readFile`
  when nimvm:
    staticRead(path)
  else:
    readFile(path)

template getScriptDir*(): string =
  ## Helper for staticRead.
  ##
  ## returns the absolute path to your project, on compile time.
  getProjectPath()
import macros # for get project path

template read*(path: untyped): untyped =
  ## Internal helper, on compiletime this calls
  ## `staticRead`
  ## on runtime this calls
  ## `readFile`
  when nimvm:
    staticRead(path)
  else:
    readFile(path)
  

template getScriptDir*(): string =
  ## Helper for staticRead.
  ##
  ## returns the absolute path to your project, on compile time.
  instantiationInfo(-1, true).filename.parentDir() 
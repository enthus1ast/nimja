import ../../../src/nimja


proc moduleRender*(): string =
  compileTemplateFile("theFile.nimja", getScriptDir())


when isMainModule:
  echo moduleRender()

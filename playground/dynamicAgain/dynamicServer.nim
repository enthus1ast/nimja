import jester
import dynamic2
import os

routes:
  get "/":
    resp evaluateTemplateStr(readFile(getAppDir() / "index.nimja"))
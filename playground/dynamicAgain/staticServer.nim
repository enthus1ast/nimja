import jester
# import dynamic2
import nimja
import os

routes:
  get "/":
    resp tmplf(getScriptDir() / "index.nimja")
discard """
  joinable: false
"""
import ../../src/nimja

proc simple(): string = compileTemplateStr("simple")
doAssert simple() == "simple"

proc simpleVar(ii: int): string = compileTemplateStr("simple{{ii}}simple")
doAssert simpleVar(123) == "simple123simple"

type
  MyObj = object
    ff: float
    ss: string
proc simpleObj(obj: MyObj): string = compileTemplateStr("simple {{obj.ff}} simple {{obj.ss}}")
doAssert simpleObj(MyObj(ff: 13.37, ss: "leet")) == "simple 13.37 simple leet"

proc stmts(obj: MyObj): string = compileTemplateStr("{{obj.ff.int * 2}} {{obj.ss.len}}")
doAssert stmts(MyObj(ff: 21.0, ss: "leet")) == "42 4"

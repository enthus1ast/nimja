discard """
  joinable: false
"""
import ../../src/nimja
import ../../src/nimja/nwtTokenizer
import sequtils

type
  NwtComplex = object
    first: seq[Token] # eg if + block
    second: seq[seq[Token]] # eg elif's + blocks
    third: seq[Token] # eg else + block

# proc skipOverBlock()

proc parseComplex(tokens: seq[Token], nameFirst, nameSecond, nameThird: string): NwtComplex =
  discard


# let tokens = toSeq(nwtTokenize("{%if false%}false{%elif true%}true{%endif%}"))
# let complex = parseComplex(tokens, "if", "elif", "else")
# # doAssert complex.blks == @[
# #   Token(tokenType = )
# ]

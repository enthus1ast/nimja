import parser, nwtTokenizer
import json, sequtils

proc prettyNwt*(str: string): string {.compileTime.} =
  ## pretty print parsed nwt template (as json)
  var lexerTokens = toSeq(nwtTokenize(str))
  var firstStepTokens = parseFirstStep(lexerTokens)
  var pos = 0
  var secondsStepTokens = parseSecondStep(firstStepTokens, pos)
  (%* secondsStepTokens).pretty()


when isMainModule:
  echo prettyNwt("{%if true%}{{TRUE}}{%endif%}")
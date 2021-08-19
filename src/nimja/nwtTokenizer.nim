#
#
#                  nimWebTemplates
#        (c) Copyright 2017 David Krause
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
## :Author: David Krause (enthus1ast)
##
## a jinja like template syntax parser
##
## This is the tokenizer of nwt.
##
## From this html:
##
## .. code-block::
##
##     <html>
##       <head>
##         <title>{%block "title" %}BASE{%endblock%}</title>
##       </head>
##       <body>
##
##         <style>
##           body {
##             background-color: darkslategray;
##             color: white;
##           }
##         </style>
##
##
##         <h1>Welcome from base</h1>
##         <div id="content">
##           {# <h1>{{content}}</h1>  #}
##         </div>
##           {%block "content2" %}{%endblock%}
##         <div>
##
##         </div>
##
##         <div>
##           Hier beschreibe ich nwt's syntax:
##           <!-- {{aksd}} -->
##
##         </div>
##       </body>
##     </html>

##
## This gets generated:
##
## .. code-block::
##
##   (tokenType: NwtString, value: <html>
##     <head>
##       <title>)
##   (tokenType: NwtEval, value: block "title")
##   (tokenType: NwtString, value: BASE)
##   (tokenType: NwtEval, value: endblock)
##   (tokenType: NwtString, value: </title>
##     </head>
##     <body>
##
##       <style>
##         body {
##           background-color: darkslategray;
##           color: white;
##         }
##       </style>
##
##
##       <h1>Welcome from base</h1>
##       <div id="content">
##         <h1>)
##   (tokenType: NwtVariable, value: content)
##   (tokenType: NwtString, value: </h1>
##       </div>
##       )
##   (tokenType: NwtEval, value: block "content2")
##   (tokenType: NwtEval, value: endblock)
##   (tokenType: NwtString, value:
##
##       <div>
##
##       </div>
##
##       <div>
##         Hier beschreibe ich nwt's syntax:
##       </div>
##     </body>
##   </html>)

import parseutils
import strutils

proc debugPrint(buffer: string, pos: int) =
  let pointPos = if pos - 1 < 0: 0 else: pos - 1
  echo buffer
  echo '-'.repeat(pointPos) & "^"

type
  TemplateSyntaxError* = ref object # of Exception
  UnknownTemplate* = ref object #of Exception

  NwtToken* = enum # TODO rename to TokenKind or TokenType
    NwtString, # a string block
    NwtComment,
    NwtEval,
    NwtVariable,

  Token* = object
    tokenType*: NwtToken
    value*: string # the value

  Block* = tuple[name: string, posStart: int, posEnd: int]

proc newToken*(tokenType: NwtToken, value: string): Token =
  result = Token()
  result.tokenType = tokenType
  result.value = value

proc extractTemplateName*(raw: string): string =
  ## returns the template name from
  ##  extends "base.html"
  ## returns "base.html"
  var parts = raw.strip().split(" ")
  if parts.len < 2:
    # TemplateSyntaxError
    raise newException(ValueError, "Could not extract template name from '$1'" % [raw])
  result = parts[1].captureBetween('"', '"')
  if result != "": return

  result = parts[1].captureBetween('\'', '\'')
  if result != "": return

  result = parts[1] #   " or ' are missing


iterator nwtTokenize*(s: string): Token =
  ## transforms nwt templates into tokens
  var
    buffer: string = s
    pos = 0
    toyieldlater = "" # we use this to reconstruct a string whitch contains a "{"

  while true:
    var stringToken = ""
    pos += buffer.parseUntil(stringToken, '{', pos)
    # buffer.debugPrint(pos)

    if buffer == "{":
      # echo "buffer ist just '{'"
      yield newToken(NwtString, "{")
      break

    if stringToken.len == buffer.len:
      # echo "we have read the string at once! no '{' found"
      yield newToken(NwtString, stringToken)
      break

    if stringToken != "":
      toyieldlater.add stringToken
    pos.inc # skip "{"
    if buffer.continuesWith("{", pos):
      if toyieldlater != "":
        yield newToken(NwtString, toyieldlater)
        toyieldlater = ""
      pos.inc # skip {
      pos += buffer.parseUntil(stringToken, '}', pos)
      yield newToken(NwtVariable, stringToken.strip())
      pos.inc # skip }
      pos.inc # skip }
    elif buffer.continuesWith("#", pos):
      if toyieldlater != "":
        yield newToken(NwtString, toyieldlater)
        toyieldlater = ""
      pos.inc # skip #
      pos += buffer.parseUntil(stringToken, '#', pos)
      pos.inc # skip end #
      if buffer.continuesWith("}", pos):
        pos.inc # skip }
        yield newToken(NwtComment, stringToken[0..^1].strip())
    elif buffer.continuesWith("%", pos):
      if toyieldlater != "":
        yield newToken(NwtString, toyieldlater);
        toyieldlater = ""
      pos.inc # skip #
      pos += buffer.parseUntil(stringToken, '%', pos)
      pos.inc # skip end #
      if buffer.continuesWith("}", pos):
        pos.inc # skip }
        yield newToken(NwtEval, stringToken[0..^1].strip())
    else:
      if pos >= buffer.len:
        # echo "we have reached the end of buffer"
        yield newToken(NwtString, toyieldlater)
      else:
        # echo "we found a { somewhere so we have to prepend it"
        toyieldlater = toyieldlater & "{"
      discard

    if pos >= buffer.len: # TODO check if this has to be '>'
      ## Nothing to do for us here
      break
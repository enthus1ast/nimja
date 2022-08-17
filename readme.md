Nimja Template Engine
=====================

<p align="center">
  <img style="max-width: 100%" src="https://user-images.githubusercontent.com/13794470/133277541-01de699e-9699-4d8f-b65c-595bc309a1ee.png">
</p>


typed and compiled template engine inspired by [jinja2](https://jinja.palletsprojects.com/), [twig](https://twig.symfony.com/) and [onionhammer/nim-templates](https://github.com/onionhammer/nim-templates) for Nim.


FEATURES
========

[![test](https://github.com/enthus1ast/nimja/actions/workflows/test.yml/badge.svg)](https://github.com/enthus1ast/nimja/actions/workflows/test.yml)

- compiled
- statically typed
- extends (a master template)
- control structures (if elif else / for / while)
- import other templates
- most nim code is valid in the templates
- very fast:
```
# https://github.com/enthus1ast/dekao/blob/master/bench.nim
# nim c --gc:arc -d:release -d:danger -d:lto --opt:speed -r bench.nim
name ................. min time  avg time  std dv   runs
dekao ................ 0.105 ms  0.117 ms  ±0.013  x1000
karax ................ 0.126 ms  0.132 ms  ±0.008  x1000
htmlgen .............. 0.021 ms  0.023 ms  ±0.004  x1000
nimja ................ 0.016 ms  0.017 ms  ±0.001  x1000 <--
nimja iterator ....... 0.008 ms  0.009 ms  ±0.001  x1000 <--
scf .................. 0.023 ms  0.024 ms  ±0.003  x1000
nim-mustache ......... 0.745 ms  0.790 ms  ±0.056  x1000
```

DOCUMENTATION
=============

- this readme
- [generated nim docs](https://enthus1ast.github.io/nimja/nimja.html)


MOTIVATING EXAMPLE
==================

- [this example is in the example folder](https://github.com/enthus1ast/nimja/tree/master/examples/fromReadme)
- [and a more complete prologue and jester example](https://github.com/enthus1ast/nimja/tree/master/examples/prologue)
- [an example howto load templates from a shared library (dll, so)](https://github.com/enthus1ast/nimja/tree/master/examples/dynlib)

server.nim

```nim
import asynchttpserver, asyncdispatch
import ../src/parser
import os, random # os and random are later used in the templates, so imported here

type
  User = object
    name: string
    lastname: string
    age: int

proc renderIndex(title: string, users: seq[User]): string =
  ## the `index.nimja` template is transformed to nim code.
  ## so it can access all variables like `title` and `users`
  ## the return variable could be `string` or `Rope` or
  ## anything which has a `&=`(obj: YourObj, str: string) proc.
  compileTemplateFile(getScriptDir() / "index.nimja")

proc main {.async.} =
  var server = newAsyncHttpServer()

  proc cb(req: Request) {.async.} =

    # in the templates we can later loop trough this sequence
    let users: seq[User] = @[
      User(name: "Katja", lastname: "Kopylevych", age: 32),
      User(name: "David", lastname: "Krause", age: 32),
    ]
    await req.respond(Http200, renderIndex("index", users))

  server.listen Port(8080)
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(cb)
    else:
      poll()

asyncCheck main()
runForever()
```

index.nimja:

```twig
{% extends partials/_master.nimja%}
{#
  extends uses the master.nimja template as the "base".
  All the `block`s that are defined in the master.nimja are filled
  with blocks from this template.

  If the templates extends another, all content HAVE TO be in a block.

  blocks can have arbitrary names

  extend must be the first token in the template,
  only comments `{# Some foo #}` and strings are permitted to come before it.
#}


{% block content %}
  {# A random loop to show off. #}
  {# Data is defined here for demo purpose, but could come frome database etc.. #}
  <h1>Random links</h1>
  {% const links = [
    (title: "google", target: "https://google.de"),
    (title: "fefe", target: "https://blog.fefe.de")]
  %}
  {% for (ii, item) in links.pairs() %}
    {{ii}} <a href="{{item.target}}">This is a link to: {{item.title}}</a><br>
  {% endfor %}

  <h1>Members</h1>
    {# `users` was a param to the `renderIndex` proc #}
    {% for (idx, user) in users.pairs %}
        <a href="/users/{{idx}}">{% importnimja "./partials/_user.nimja" %}</a><br>
    {% endfor %}
{% endblock %}

{% block footer %}
  {#
    we can call arbitraty nim code in the templates.
    Here we pick a random user from users.
  #}
  {% var user = users.sample() %}

  {#
    imported templates have access to all variables declared in the parent.
    So `user` is usable in "./partials/user.nimja"
  #}
  This INDEX was presented by.... {% importnimja "./partials/_user.nimja" %}
{% endblock footer %} {# the 'footer' in endblock is completely optional #}
```

master.nimja
```twig
{#

  This template is later expanded from the index.nimja template.
  All blocks are filled by the blocks from index.nimja

  Variables are also useable.
 #}
<html>
<head>
  <title>{{title}}</title>
</head>
<body>

<style>
body {
  background-color: aqua;
  color: red;
}
</style>

{# The master can declare a variable that is later visible in the child template #}
{% var aVarFromMaster = "aVarFromMaster" %}

{# We import templates to keep the master small #}
{% importnimja "partials/_menu.nimja" %}

<h1>{{title}}</h1>

{# This block is filled from the child templates #}
{%block content%}{%endblock%}


{#
  If the block contains content and is NOT overwritten later.
  The content from the master is rendered
#}
{% block onlyMasterBlock %}Only Master Block{% endblock %}

<footer>
  {% block footer %}{% endblock %}
</footer>

</body>
</html>
```

partials/_menu.nimja:
```twig
<a href="/">index</a>
```

partials/_user.nimja:
```twig
User: {{user.name}} {{user.lastname}} age: {{user.age}}
```

Basic Syntax
============

- `{{ myObj.myVar }}` --transformed-to--->  `$(myObj.myVar)`
- {% myExpression.inc() %} --transformed-to---> `myExpression.inc()`
- {# a comment #}



How?
====

nimja transforms templates to nim code on compilation,
so you can write arbitrary nim code.
```nim
proc foo(ss: string, ii: int): string =
  compileTemplateStr(
    """example{% if ii == 1%}{{ss}}{%endif%}{% var myvar = 1 %}{% myvar.inc %}"""
  )
```
is transformed to:

```nim
proc foo(ss: string; ii: int): string =
  result &= "example"
  if ii == 1:
    result &= ss
  var myvar = 1
  inc(myvar, 1)
```

this means you have the full power of nim in your templates.


USAGE
=====

there are only three relevant procedures:

- `compileTemplateStr(str: string)`
  compiles a template string to nim ast
- `compileTemplateFile(path: string)`
  compiles the content of a file to nim ast
- `getScriptDir()`
  returns the path to your current project, on compiletime.

compileTemplateFile
-------------------

compileTemplateFile transforms the given file into the nim code.
you should use it like so:

```nim
import os # for `/`
proc myRenderProc(someParam: string): string =
  compileTemplateFile(getScriptDir() / "myFile.html")

echo myRenderProc("test123")
```

compileTemplateFile can also generate an iterator body, for details look at the
iteratior section.

compileTemplateFile (also compileTemplateString) generates the body of a proc/iterator so it generates
assign calls to a variable. The default is `result`.
If you want it to use another variable set it in `varname`

compileTemplateStr
-------------------

compileTemplateStr compiles the given string into nim code.


```nim
proc myRenderProc(someParam: string): string =
  compileTemplateStr("some nimja code {{someParam}}")

echo myRenderProc("test123")
```

compileTemplateStr can also generate an iterator body, for details look at the
iteratior section.


compileTemplateString (also compileTemplateFile) generates the body of a proc/iterator so it generates
assign calls to a variable. The default is `result`.
If you want it to use another variable set it in `varname`



if / elif / else
-----------------

```twig
{% if aa == 1 %}
  aa is: one
{% elif aa == 2 %}
  aa is: two
{% else %}
  aa is something else
{% endif %}
```

when / elif / else
-----------------

`when` is the compile time if statement.
It has the same semantic than if

```twig
{% when declared(isDeclared) %}
  isDeclared
{% elif true == true %}
  true
{% else %}
  something else
{% endif %}
```


tmpls / tmplf
=============

`compileTemplateStr` and `compileTemplateFile` both need a surrounding proc.
`tmpls` (template str) and `tmplf` (template file) are a shorthand for these
situations where you want to inline a render call.

```nim
let leet = 1337
echo tmpls("foo {{leet}}")
echo tmplf(getScriptDir() / "templates" / "myfile.nimja")
```

A context can be supplied to the template, to override variable names:

```nim
block:
  type
    Rax = object
      aa: string
      bb: float
  var rax = Rax(aa: "aaaa", bb: 13.37)
  var foo = 123
  tmpls("{{node.bb}}{{baa}}", node = rax, baa = foo)
```

Please note, currently the context **cannot be** procs/funcs etc.



for
---

```twig
{% for (cnt, elem) in @["foo", "baa", "baz"].pairs() %}
  {{cnt}} -> {{elem}}
{% endfor %}
```

```twig
{% for elem in someObj.someIter() %}
  {# `elem` is accessible from the "some/template.nimja" #}
  {# see importnimja section for more info #}
  {% importnimja "some/template.nimja" %}
{% endfor %}
```

while
----

```twig
{% while isTrue() %}
  still true
{% endwhile %}
```

```twig
{% var idx = 0 %}
{% while idx < 10 %}
  still true
  {% idx.inc %}
{% endwhile %}
```

comments
-------

```twig
{# single line comment #}
{#
  multi
  line
  comment
#}
{# {% var idx = 0 %} #}
```

"to string" / output
--------------------

declare your own `$` before you call
`compileTemplateStr()` or `compileTemplateFile()`
for your custom objects.
For complex types it is recommend to use the method described in the `importnimja` section.
```twig
{{myVar}}
{{someProc()}}
```

importnimja
---------

import the content of another template.
The imported template has access to the parents variables.
So it's a valid strategy to have a "partial" template that for example
can render an object or a defined type.
Then include the template wherever you need it:

best practice is to have a `partials` folder,
and every partial template begins with an underscore "_"
all templates are partial that do not extend another
template and therefore can be included.

This way you create reusable template blocks to use all over your webpage.

partials/_user.nimja:
```twig
<div class="col-3">
  <h2>{{user.name}}</h2>
  <ul>
    <li>Age: {{user.age}}</li>
    <li>Lastname: {{user.lastname}}</li>
  </ul>
</div>
```

partials/_users.nimja:
```twig
<div class="row">
  {% for user in users: %}
    {% importnimja "partials/_user.nimja" %}
  {% endfor %}
</div>
```

extends
-------

a child template can extend a master template.
So that placeholder blocks in the master are filled
with content from the child.


partials/_master.nimja
```twig
<html>
<body>
A lot of boilerplate
{% block content %}{% endblock %}
<hr>
{% block footer %}{% endblock %}
</body>
</html>
```

child.nimja
```
{% extends "partials/_master.nimja" %}
{% block content %}I AM CONTENT{% endblock %}
{% block footer %}...The footer..{% endblock %}
```

if the child.nimja is compiled then rendered like so:

```nim
proc renderChild(): string =
  compileTemplateFile(getScriptDir() / "child.nimja")

echo renderChild()
```

output:
```html
<html>
<body>
A lot of boilerplate
I AM CONTENT
<hr>
...The footer..
</body>
</html>
```

`self` variable
===============

Jinja describes them like so, we can do the same:

You can't define multiple {% block %} tags with the same name in the same template.
This limitation exists because a block tag works in "both" directions.
That is, a block tag doesn't just provide a placeholder to fill - it also defines the content that fills the placeholder in the parent.
If there were two similarly-named {% block %} tags in a template, that template's parent wouldn't know which one of the blocks content to use.

If you want to print a block multiple times, you can, however, use the special self variable and call the block with that name:

```twig
<title>{% block title %}{% endblock %}</title>
<h1>{{ self.title }}</h1>
{% block body %}{% endblock %}
```

To change the `specialSelf` variable name compile with eg.:

```
nim c -d:specialSelf="blocks." file.nim
```


procedures (macro)
========

Procedures can be defined like so:

```twig
{% proc foo(): string = %}
  baa
{% endproc %}
{{ foo() }}
```

```twig
{% proc input(name: string, value="", ttype="text"): string = %}
    <input type="{{ ttype }}" value="{{ value }}" name="{{ name }}">
{% endproc %}
{{ input("name", "value", ttype="text") }}
```

Func's have the same semantic as nim funcs, they are not allowed to have a side effect.

```twig
{% func foo(): string = %}
  baa
{% endfunc %}
{{ foo() }}
```

`macro` is an alias for `proc`

```twig
{% macro textarea(name, value="", rows=10, cols=40): string = %}
    <textarea name="{{ name }}" rows="{{ rows }}" cols="{{ cols
        }}">{{ value }}</textarea>
{% endmacro %}
{{ textarea("name", "value") }}
```

for `{{func}}` `{{proc}}` and `{{macro}}` either the `{{end}}` tag or
the `{{endfunc}}` `{{endproc}}` `{{endmacro}}` are valid closing tags.

Importing func/proc/macro from a file
------------------------------------

Importing works like any other ordinary Nimja templates with `ìmportnimja`.
Good practice is to define procs with the "whitespacecontrol":

myMacros.nimja
```
{%- proc foo(): string = %}foo{% end -%}
{%- proc baa(): string = %}baa{% end -%}
```

myTemplate.nimja
```
{% importnimja "myMacros.nimja" %}
```

When a template `extends` another template, `importnimja` statements must be
in a `block` they cannot stand on their own.
It might be a good idea to import these "library templates" in
the extended template (eg.: master.nimja).

Iterator
========

Expanded template bodies can also be created as an iterator,
therefore the generated strings are not concatenated to the result
`result &= "my string"` but are yielded.

This could be used for streaming templates, or to save memory when a big template is rendered and the http server can send data in chunks:

```nim
iterator yourIter(yourParams: bool): string =
  compileTemplateString("{%for idx in 0 .. 100%}{{idx}}{%endfor%}", iter = true)

for elem in yourIter(true):
  echo elem
```

Whitespace Control
==================

```twig
###############
{% if true %}
  <li>   {{foo}}   </li>
{% endif %}
###############
```
is expanded to:

```html
###############

  <li>   FOO   </li>

###############
```

the nimja template control statements leave their newline and whitespace when rendered.
To fix this you can annotate them with "-":

```twig
###############
{% if true -%}
  <li>   {{-foo-}}   </li>
{%- endif %}
###############
```

```html
###############
<li>FOO</li>
###############
```


Nimjautils
==========

The optional `nimjautils` module, implements some convenient procedures.

```nim
import nimja/nimjautils
```

Mainly:

Loop variable/iterator
-------------

yields a `Loop` object with every item.
Inside the loop body you have access to the following fields.
Unlike jinja2 or twig where the loop variable is implicitly bound and available, we must use the `loop()` iterator explicity.

```twig
{% for (loop, row) in rows.loop() %}
    {{ loop.index0 }} {# which elemen (start from 0) #}
    {{ loop.index }} {# which element (start from 1) #}
    {{ loop.revindex0 }} {# which element, counted from the end (last one is 0) #}
    {{ loop.revindex }} {# which element, counted from the end (last one is 1) #}
    {{ loop.length }} {# the length of the seq, (same as mySeq.len()) #}
    {% if loop.first %}The first item{% endif %} {# if this is the first loop iteration #}
    {% if loop.last %}The last item{% endif %} {# if this is the last loop iteration #}
    {% if loop.previtem.isSome() %}{{ loop.previtem.get() }}{% endif %} {# get the item from the last loop iteration #}
    {% if loop.nextitem.isSome() %}{{ loop.nextitem.get() }}{% endif %} {# get the item from the next loop iteration #}
    <li class="{{ loop.cycle(@["odd", "even"]) }}">{{row}}</li>
{% endfor %}
```

~~however, the element you iterate over must match the Concept `Loopable`.~~ https://github.com/enthus1ast/nimja/issues/23
This means you can propably not use `loop()` with an iterator, since they do not have a `len()` and `[]`

Cycle
-----

within a loop you can cycle through elements:

```twig
{% for (loop, row) in rows.loop() %}
    <li class="{{ loop.cycle(@["odd", "even"]) }}">{{ row }}</li>
{% endfor %}
```

'~' (tilde)
----------

Converts all operands into strings and concatenates them.
like: `$aa & $bb`

```twig
{{ "Hello " ~ name ~ "!" }}
```

would return (assuming name is set to 'Nim') Hello Nim!.

includeRaw
----------
Includes the content of a file literally without any parsing
Good for documentation etc..

```nim
proc test(): string =
  let path = (getScriptDir() / "tests/basic" / "includeRawT.txt")
  compileTemplateStr("""pre{{ includeRaw(path) }}suf""")
```

raw strings
-----------
to include raw strings, or nimja code itself to a template (for documentation purpose),
you could use this construct `{{"raw code"}}`

```nim
proc foo(): string =
  compileTemplateStr("""
    foo {{"{%if true%}baa{%endif%}"}}
  """)
```
this would then be rendered like so:

```
foo {%if true%}baa{%endif%}
```

includeRawStatic
----------------
Includes the content of a file literally without any parsing, on compiletime.
This means it is included into the executable.

includeStaticAsDataurl
----------------------
Includes the content of a file on compile time, it is converted to a data url.
Eg:

```html
  <img src="{{includeStaticAsDataurl(getScriptDir() / "logo.jpg")}}">
```

  is transformed to:

```html
  <img src="data:image/jpeg;charset=utf-8;base64,/9j/4AAQSkZJRg..."/>
```


truncate
--------

truncates a string to "num" characters.
when the string was truncated it appends the `suf` to the text.
if `preserveWords` is true it will not cut words in half but
the output string could be shorter than `num` characters.

```nim
proc truncate*(str: string, num: Natural, preserveWords = true, suf = "..."): string
```

```nim
let lorem = "Lorem ipsum, dolor sit amet consectetur adipisicing elit. Rem voluptates odio tempore voluptas beatae eum consequatur laudantium totam. Delectus fuga eveniet ab cum nulla aperiam iste ducimus odio fugit voluptas."

proc test(lorem: string): string =
  compileTemplateStr("{{lorem.truncate(65)}}")
assert test(lorem) == "Lorem ipsum, dolor sit amet consectetur adipisicing elit. Rem..."
```

nl2br
-----

Converts newline to `<br>`.
If keepNL == true, the one `\n` is replaced by `<br>\n` thus keeping the newlines.

```nim
func nl2br*(str: string, keepNl = true): string =
```

```nim
assert "foo\nbaa".nl2br == "foo<br>\nbaa"
```

spaceless
---------

Removes unneeded whitespaces between html tags,
warning, this is NOT smart. So it will destroy `<textarea>` and `<pre>` content!

```nim
  check "<foo>\n\nbaa  </foo>".spaceless == "<foo> baa </foo>"
  check "<foo tag='tag tag'>\n\nbaa  </foo>".spaceless == "<foo tag='tag tag'> baa </foo>"
  check "<foo>baa  baz</foo>".spaceless == "<foo>baa baz</foo>"
```

slugify
-------

converts any string to an url friendly one.
Removes any special chars and replaces non ASCII runes to their ASCII representation.

```nim
slugify("Lession learned german umlauts: öüä")
```

will output:

```lession-learned-german-umlauts-oua```


```nim
let allowedCharsInSlug = Letters + Digits
proc slugify*(str: string, sperator = "-", allowedChars = allowedCharsInSlug): string =
```

shorthand if `?`
----------------

a shorthand for a condition, this could be used for example
to toggle html classes:

```nim
proc foo(isDisabled: bool): string =
  compileTemplateStr("""{% ?isDisabled: "disabled" %}""")
check "disabled" == foo(true)
check "" == foo(false)
```

filter `|`
---------

`a | b` is an alias to `a.b` this is often used in other template engines.

```nim
proc foo(): string =
  compileTemplateStr("""{{"foo baa baz" | slugify}}""")
check foo() == "foo-baa-baz"
```


Want to hack?
-------------
> if you need more utils in nimjautils, please PR!
> they should all be quite easy to implement,
> so they make up a good first issue/pull request!
>
>a good inspiration WHAT to hack is jinja and twig filters.


Compile / Use
=============

This is a COMPILED template engine.
This means you must _recompile_ your application
for every change you do in the templates!

~~_Automatic recompilation / hot code reloading / dynamic execution is a [planned feature](https://github.com/enthus1ast/nimja/issues/6)._~~ see the
`Automatic Recompilation / Hot Code Reloading (hcr)` section

```bash
nim c -r yourfile.nim
```

sometimes, nim does not catch changes to template files.
Then compile with "-f" (force)

```bash
nim c -f -r  yourfile.nim
```

Automatic Recompilation / Hot Code Reloading (hcr)
============================================

(Still an experimental feature, help wanted.)
Automatic Recompilation enables you to change your templates and without
recompiling your application, see the changes lives.

How it works:

Nimja compiles your templates (and template render functions)
to a shared library (.so/.dll/.dynlib), then your host application loads
this library, then on source code change, the shared library is unloaded from
your host, recompiled, and loaded again.

This is normally way faster, than recompiling your whole application.

For this to work, Nimja now contains a small file watcher, you must utilize this
tool in your own application.

You also must restructure you application a little bit,
all you render functions must be in a separate file,
this file is then compiled to a shared lib and loaded by your host.

When you go live later, you can just disable the recompilation,
and compile the shared library for release, it should be very fast as well.

Below is a minimal example, [a more complete example is in the example folder](https://github.com/enthus1ast/nimja/tree/master/examples/hcr)

Minimal example:

`host.nim`

```nim
# this is the file that eg. implements your webserver and loads
# the templates as a shared lib.
import nimja/hcrutils # Nimja's hot code reloading utilities
import jester, os

# We watch the templates folder for change (and also tmpls.nim implicitly)
var cw = newChangeWatcher(@[getAppDir() / "templates/"])
asyncCheck cw.recompile() # if a change is detected we recompile tmpls.nim

type
    # You must declare the proc definition from your tmpls.nim here as well.
    ProcNoParam = proc (): string {.gcsafe, stdcall.}
    ProcId = proc (id: string): string {.gcsafe, stdcall.}

routes:
  get "/":
    resp dyn(ProcNoParam, "index")

  get "/id/@id":
    resp dyn(ProcId, "detail", @"id")
```


`tmpls.nim`

```nim
# this file contains you render functions
# is compiled to a shared lib and loaded by your host application
# to keep compilation fast, use this file only for templates.
# this file is also watched by the filewatcher.
# It can also be changed dynamically!
import nimja
import os # for `/`

proc index*(): string {.exportc, dynlib.} =
  var foos =  1351 # change me i'm dynamic :)
  compileTemplateFile(getScriptDir() / "templates/index.nimja")

proc detail*(id: string): string {.exportc, dynlib.} =
  compileTemplateFile(getScriptDir() / "templates/detail.nimja")

```

`templates/`

`templates/partials/_master.nimja`

```html
<head>
  <title>Hello, world!</title>
</head>
<body>
  <h1><a href="/">Nimja dynamic test</a></h1>
  <div>
    {% block content %}{% endblock %}
  </div>
  </body>
</html>
```


`templates/index.nimja`
```html
{% extends "templates/partials/_master.nimja" %}
{% block content %}

<h1>Hello, world! {{foos}}</h1>

index

{% for idx in 0..100 %}
  <a href="/id/{{idx}}">{{idx}}</a>
{%- endfor %}

{% endblock %}

```


`templates/detail.nimja`
```html
{% extends "templates/partials/_master.nimja" %}
{% block content %}
detail
<a href="/id/{{id}}">{{id}}</a>
{% endblock %}

```

you can now change any of the templates or the `tmpls.nim`
files.
Later if you wanna go live, comment out the

```
asyncCheck cw.recompile() # if a change is detected we recompile tmpls.nim
```

line.


Nimja Template VSCode Syntax Color Formatting
============================================
If you are using VSCode to develop your nim app,
you can still associate nimja template files for color syntax and formating with vscode as an html file.
Add this segment to your settings.json in vscode:

```json
  "files.associations": {
    "*.nwt": "html", // Nimja deprecated templates
    "*.nimja": "html", // Nimja new templates
  },
```

Debugging
=====================


```bash
nim c -d:dumpNwtAst -r yourfile.nim # <-- dump NwtAst
nim c -d:dumpNwtAstPretty -r yourfile.nim # <-- dump NwtAst as pretty json
nim c -d:nwtCacheOff -r yourfile.nim   # <-- disables the NwtNode cache
nim c -d:noPreallocatedString -r yourfile # <-- do not preallocate the output string
nim c -d:noCondenseStrings -r yourfile.nim # <-- disables string condense see #12
nim c -d:dumpNwtMacro -r yourfile.nim # <-- dump generated Nim macros
```


Changelog
=========

- 0.7.0 Added context to `tmpls` and `tmplf`
- 0.6.8 Added `importnimja` deprecated `importnwt` (importnwt is still valid for now)
- 0.6.7 Removed the ".nwt" extention everywhere, we go with ".nimja" now.
- 0.6.6 Preallocate the minimal known output length if `result` is string.
- 0.6.5 Condense strings of extended templates (less assigns -> better runtime performance).
- 0.6.1 No codegen for empty string nodes after whitespaceControl.
- 0.5.6 Added `{{endfunc}}` `{{endproc}}` `{{endmacro}}` for consistency.
- 0.5.5 Added `tmpls` and `tmplf` procs to use inline.
- 0.5.1 Added self variable, to print blocks multiple times
- 0.5.0 Added hot code reloading.
- 0.4.2 Added `includeRawStatic` and `includeStaticAsDataurl`

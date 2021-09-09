Nimja Template Engine
=====================

<p align="center">
  <img width="460" src="https://raw.githubusercontent.com/enthus1ast/nimja/master/logo/logojanina.png">
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
  ## the `index.nwt` template is transformed to nim code.
  ## so it can access all variables like `title` and `users`
  ## the return variable could be `string` or `Rope` or
  ## anything which has a `&=`(obj: YourObj, str: string) proc.
  compileTemplateFile(getCurrentDir() / "index.nwt")

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

index.nwt:

```twig
{% extends partials/_master.nwt%}
{#
  extends uses the master.nwt template as the "base".
  All the `block`s that are defined in the master.nwt are filled
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
        <a href="/users/{{idx}}">{% importnwt "./partials/_user.nwt" %}</a><br>
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
    So `user` is usable in "./partials/user.nwt"
  #}
  This INDEX was presented by.... {% importnwt "./partials/_user.nwt" %}
{% endblock footer %} {# the 'footer' in endblock is completely optional #}
```

master.nwt
```twig
{#

  This template is later expanded from the index.nwt template.
  All blocks are filled by the blocks from index.nwt

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
{% importnwt "partials/_menu.nwt" %}

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

partials/_menu.nwt:
```twig
<a href="/">index</a>
```

partials/_user.nwt:
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

for
---

```twig
{% for (cnt, elem) in @["foo", "baa", "baz"].pairs() %}
  {{cnt}} -> {{elem}}
{% endfor %}
```

```twig
{% for elem in someObj.someIter() %}
  {# `elem` is accessible from the "some/template.nwt" #}
  {# see importnwt section for more info #}
  {% importnwt "some/template.nwt" %}
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
For complex types it is recommend to use the method described in the `importnwt` section.
```twig
{{myVar}}
{{someProc()}}
```

importnwt
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

partials/_user.nwt:
```twig
<div class="col-3">
  <h2>{{user.name}}</h2>
  <ul>
    <li>Age: {{user.age}}</li>
    <li>Lastname: {{user.lastname}}</li>
  </ul>
</div>
```

partials/_users.nwt:
```twig
<div class="row">
  {% for user in users: %}
    {% importnwt "partials/_user.nwt" %}
  {% endfor %}
</div>
```

extends
-------

a child template can extend a master template.
So that placeholder blocks in the master are filled
with content from the child.


partials/_master.nwt
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

child.nwt
```
{% extends "partials/_master.nwt" %}
{% block content %}I AM CONTENT{% endblock %}
{% block footer %}...The footer..{% endblock %}
```

if the child.nwt is compiled then rendered like so:

```nim
proc renderChild(): string =
  compileTemplateFile("child.nwt")

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

procedures (macro)
========

Procedures can be defined like so:

```twig
{% proc foo(): string = %}
  baa
{% end %}
{{ foo() }}
```

```twig
{% proc input(name: string, value="", ttype="text"): string = %}
    <input type="{{ ttype }}" value="{{ value }}" name="{{ name }}">
{% end %}
{{ input("name", "value", ttype="text") }}
```

Func's have the same semantic as nim funcs, they are not allowed to have a side effect.

```twig
{% func foo(): string = %}
  baa
{% end %}
{{ foo() }}
```

`macro` is an alias for `proc`

```twig
{% macro textarea(name, value="", rows=10, cols=40): string = %}
    <textarea name="{{ name }}" rows="{{ rows }}" cols="{{ cols
        }}">{{ value }}</textarea>
{% end %}
{{ textarea("name", "value") }}
```


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

> if you need more utils in nimjautils, please pr!
> they should all be quite easy to implement,
> so they make up a good first issue/pull request!

Compile / Use
=============

This is a COMPILED template engine.
This means you must _recompile_ your application
for every change you do in the templates!

_Automatic recompilation / hot code reloading / dynamic execution is a [planned feature](https://github.com/enthus1ast/nimja/issues/6)._

```bash
nim c -r yourfile.nim
```

sometimes, nim does not catch changes to template files.
Then compile with "-f" (force)

```bash
nim c -f -r  yourfile.nim
```



Debugging
=====================


```bash
nim c -d:dumpNwtAst -r yourfile.nim # <-- dump NwtAst
nim c -d:dumpNwtAstPretty -r yourfile.nim # <-- dump NwtAst as pretty json
nim c -d:nwtCacheOff -r yourfile.nim   # <-- disables the NwtNode cache
nim c -d:noCondenseStrings -r yourfile.nim # <-- disables string condense see #12
nim c -d:dumpNwtMacro -r yourfile.nim # <-- dump generated Nim macros
```

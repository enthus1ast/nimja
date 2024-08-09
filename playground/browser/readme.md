This is just dumb, since it replaces the innerHTML of the document.

But it shows that nimja could run on the javascript target.

A good solution could be to let nimja generate karax, so that we can have a virtual dom/dom diffing.

if you want to play with this, compile jsplayground.nim to js:

```nim
nim js jsplayground.nim
```

then open index.html in your browser.
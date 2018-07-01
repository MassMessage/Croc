Idea
=======

Lex and parse some subset of Croc and output Lua.

It is NOT a "Croc front". It does not take arbitrary Croc and output code that will behave exactly the same way. It is more like a reskin of Lua plus a few extra features that I always find lacking (like augmentation/crements).

Not all Croc language features are supported and many of Croc's semantics are not preserved. For example, array indices start at 1, not 0; numeric for loops go to the high value inclusive; field access is just sugar for indexing etc. It IS Lua, it's not Croc. It's just a nicer-looking Lua.

Comments are preserved. Attempts are made to preserve line numbers for error reporting purposes, but Lua does not have a "line pragma" feature and therefore it's not always possible.

Lexical
=======

Identifiers containing '!'
	=> NO!

String literals with unicode characters/escapes
	=> convert to sequences of single-byte escapes

Binary number literals
	=> convert to hex literals

Expressions
===========

Trivial
	`and, or, not`
	`==, !=, <, <=, >, >=`
	`#, - (neg)`
	`+, -, *, /, %, ~ (cat)`
	`{x=5}`
	`[5]`
	`a[e]`
	`a.x, a.('x')`
	`null`
	`true, false`
	`f()`
	`\x -> x, \->{}`
	`x`
	`vararg`

Pretty easy
	`is, is not`
		=> just sugar for == and !=
	`this`
		=> `self`
	`:x, :('x')`
		=> `self.x, self['x']`
	`#vararg`
		=> `select('#', vararg)`
	`vararg[i]` (rhs)
		=> `select(i, vararg)`
	`yield()`
		=> `coroutine.yield()`

Require some considerable translation
	`x ? y : z`
		=> don't even know.. `x and y or z` not an exact translation (gives z if x and y are false)
	`function name() {}` (as a literal)
		=> define function as a local before that line... but could conflict with other locals?
	`{ x foreach x, y; z }, [ x foreach x, y; z ]`
		=> YEESH.

Require a library
	`&, |, ^, ~ (com), <<, >>, >>>`
		=> `bit.band, bit.bor, bit.bxor, bit.bnot, bit.lshift, bit.rshift, bit.arshift`

What????
	`vararg[i]` (lhs)
		=> illegal
	`a[], a[x .. y]`
		=> nonsensical, no concept of slicing
	`in, not in`
		=> could be translated to some function like "contains" but there's no standard
	`as`
		=> nonsensical

Statements
==========

Trivial
	`if(e) {} else {}`
	`for(i; x .. y[, z]) {}`
	`foreach(x, y; a, b, c)`
	`local x`
	`x = y`
	`x, y = z, w`
	`break`
	`while(e) {}`
	`{}`
	`return`
	`function f() {}`
		=> would be good to add function o.x() and function o:x() syntax as well

Pretty easy
	`do {} while(e)`
		=> `repeat ... until not e`
	`throw e`
		=> `error(e)`

Require some considerable translation
	`import n [as m][: a as b]`
		=> `local temp_ = require(n);` then extract locals from `temp_`
	`@deco function f() {}`
		=> basically translate to what's really happening
	`for(init; cond; upd) {}`
		=> translate to what's really happening
	augmentation assigment and crements
		=> complex LHS (e.g. a[4].y++) requires generating a temp; basically what codegen does
	`if(local x = e) {} else {}`
		=> could do it as a more complex thing, like... `local _temp = e; if _temp then local x = _temp; ... else ... end`

MAYBE if using 5.2 or LuaJit 2.0.1+
	`continue, while name(e) {}, break name, continue name`
		=> gotos

What????
	`try{}catch(e){}finally{}, scope(action) {}`
		=> Lua's error mechanism works differently
	`global x`
		=> no global mechanism, though I suppose it could call a function or something
	`switch(e) { case .. default .. }`
		=> no way to translate this, especially with fallthrough
	`assert(e)`
		=> take it out, since assert() is a function in Lua and is commonly used as the RHS
	`module m, class C {}, namespace N {}`
		=> no equivalent
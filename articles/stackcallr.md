# Introduction to stackcallr

``` r

library(stackcallr)
```

## Why stackcallr

When you’re reading unfamiliar code, one of the first questions is: what
does this function actually call? For a simple function you can just
read the body. For an S3 generic like `dplyr::select()`, the body is a
single line, `UseMethod("select")`, and the real work happens in a
method you’d have to go find yourself.

`stackcallr` answers that question directly. Give
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
the name of a function, and it returns the tree of every function it
calls, the functions those call, and so on, resolving S3 dispatch along
the way.

## The basic call

[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
takes a single string naming a function, either bare (`"mean"`) or
namespaced (`"pkg::fun"`, `"pkg:::internal_fun"`):

``` r

call_stack("mean.default", max_depth = 1)
#> █─mean.default
#> ├─.Internal
#> ├─anyNA
#> ├─c
#> ├─floor
#> ├─is.complex
#> ├─is.logical
#> ├─is.na
#> ├─is.numeric
#> ├─isTRUE
#> ├─length
#> ├─return
#> ├─sort.int
#> ├─stop
#> ├─unique
#> └─warning
```

The result is a `call_stack` object: a tree where each node has a `name`
and a list of `calls` (its children). Printing it draws the tree.

## Limiting depth

Some call trees are deep. `max_depth` caps how many levels are followed,
so `max_depth = 1` returns only the functions called directly by
[`sd()`](https://rdrr.io/r/stats/sd.html):

``` r

call_stack("stats::sd", max_depth = 1)
#> █─sd
#> ├─as.double
#> ├─is.factor
#> ├─is.vector
#> ├─sqrt
#> └─var
```

Raising it to `2` expands each of those nodes one level further:

``` r

call_stack("stats::sd", max_depth = 2)
#> █─sd
#> ├─as.double
#> ├─█─is.factor
#> │ └─inherits
#> ├─█─is.vector
#> │ └─.Internal
#> ├─sqrt
#> └─█─var
#>   ├─.Call
#>   ├─as.matrix
#>   ├─c
#>   ├─is.atomic
#>   ├─is.data.frame
#>   ├─is.na
#>   ├─is.null
#>   ├─missing
#>   ├─pmatch
#>   ├─stop
#>   └─stopifnot
```

The default, `max_depth = Inf`, follows every call all the way down,
stopping only at primitives (functions with no R-level body to inspect)
and at calls it has already followed once, so recursive or mutually
recursive functions don’t loop forever.

## Following S3 dispatch

Static analysis alone can’t tell you what `UseMethod("select")` actually
runs, since that depends on the class of the argument at call time.
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
handles this case specifically: when a function’s body calls
[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html), it looks up
every method registered for that generic and follows each one, in place
of a single unhelpful `UseMethod` leaf.

``` r

call_stack("mean", max_depth = 1)
#> █─mean
#> ├─mean.Date
#> ├─mean.default
#> ├─mean.difftime
#> ├─mean.POSIXct
#> ├─mean.POSIXlt
#> └─mean.quosure
```

Each `mean.*` entry above is a real method, resolved and ready to be
expanded further with a larger `max_depth`.

## How resolution works

[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
never runs the function you point it at. It works entirely from source:

1.  The named function is resolved to a closure via
    [`get()`](https://rdrr.io/r/base/get.html) /
    [`getExportedValue()`](https://rdrr.io/r/base/ns-reflect.html).
2.  Its body is parsed with
    [`codetools::findGlobals()`](https://rdrr.io/pkg/codetools/man/findGlobals.html)
    to list the functions it references, with R’s own syntax (`{`, `if`,
    `<-`, `+`, …) filtered out, since those aren’t calls in any
    meaningful sense.
3.  Each referenced name is looked up in the function’s own lexical
    scope, the same place R itself would resolve it, so calls to
    internal, unexported helpers are found correctly.
4.  If the body calls
    [`UseMethod()`](https://rdrr.io/r/base/UseMethod.html), the
    generic’s registered methods are found and substituted in for that
    call.
5.  The process repeats for every function found, down to `max_depth` or
    until a cycle is detected.

## What it can’t resolve

[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html) is the one form
of dynamic dispatch
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
follows. Everything else that decides which function to run at call time
stays unresolved, and shows up as a leaf rather than being expanded:

- [`NextMethod()`](https://rdrr.io/r/base/UseMethod.html) calls, since
  the next method depends on the class vector in play at the time.
- S4 and R6 dispatch.
- Functions named only as data, such as those passed to
  [`do.call()`](https://rdrr.io/r/base/do.call.html),
  [`match.fun()`](https://rdrr.io/r/base/match.fun.html), or
  [`Recall()`](https://rdrr.io/r/base/Recall.html).

A leaf in the printed tree, then, means one of three things: a
primitive, a cycle already followed once, or a call that static analysis
can’t see through.

## How this differs from `lobstr::cst()`

If the printed trees look familiar, that’s because the block-character
style is the one `lobstr::ast()` uses. The resemblance stops at the
drawing. `lobstr::cst()` prints the *call stack tree* at the moment you
call it: it walks
[`sys.calls()`](https://rdrr.io/r/base/sys.parent.html), the frames that
are actually executing right now. You use it from inside running code,
usually mid-debug, after
[`browser()`](https://rdrr.io/r/base/browser.html) has dropped you at an
error, and it shows exactly one path, the sequence of calls that got you
to that point. A real call stack is linear, so there are no branches to
show.

[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
(and
[`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
/
[`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md))
work from the other direction. They never run the function. They parse
its body and recursively expand everything it *could* call, including
every branch, so a generic contributes all of its
[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html) dispatch targets
rather than the one method a particular run happened to hit. The result
is a tree of possibilities, not a record of an execution.

``` r

# mid-debug, "how did execution get here right now"
lobstr::cst()

# no execution at all, "what could this function call, in total"
call_stack("dplyr::select")
```

Reach for `cst()` when you’re already inside the problem. Reach for
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
when you want to audit a function you’d rather not execute, or map an
unfamiliar codebase before running any of it.

## Learning more

See
[`?call_stack`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
for the full argument reference, and
[`?print.call_stack`](https://mjfrigaard.github.io/stackcallr/reference/print.call_stack.md)
for how the tree is drawn.

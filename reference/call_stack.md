# Build the call tree of a function

`call_stack()` takes the name of a function, optionally namespaced (e.g.
`"dplyr::select"`), statically parses its body, and recursively resolves
every function it calls, building a tree of those calls, the calls those
functions make, and so on.

Resolution is static (read from the function's source code), not a
runtime trace: the function is never called.
[`UseMethod()`](https://rdrr.io/r/base/UseMethod.html) dispatch is
resolved by looking up the generic's registered S3 methods and following
each one. Other dynamic calls
([`NextMethod()`](https://rdrr.io/r/base/UseMethod.html), S4 and R6
dispatch, non-standard evaluation) show as leaves rather than being
followed further.

## Usage

``` r
call_stack(fn, max_depth = Inf)
```

## Arguments

- fn:

  Character string naming a function, e.g. `"dplyr::select"`,
  `"pkg:::internal_fun"`, or `"mean"`.

- max_depth:

  Maximum recursion depth. Default `Inf`, which follows every call down
  to a primitive or a cycle already visited.

## Value

An object of class `call_stack`: a named list with `name` (the function
name) and `calls` (a list of child nodes with the same shape).

## See also

[`print.call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/print.call_stack.md)
for how the tree is drawn.

## Examples

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

# a generic: UseMethod() is replaced by the methods it dispatches to
call_stack("mean", max_depth = 1)
#> █─mean
#> ├─mean.Date
#> ├─mean.POSIXct
#> ├─mean.POSIXlt
#> ├─mean.default
#> ├─mean.difftime
#> ├─mean.quosure
#> └─mean.vctrs_vctr
```

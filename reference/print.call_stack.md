# Print a call_stack tree

Draws a `call_stack` tree in the style of `lobstr::ast()`. A node with
children is prefixed with a solid block (`\u2588\u2500`) and a leaf is
shown as plain text; children are connected with `\u251c\u2500` and
`\u2514\u2500` branches, one level of indent per level of the tree.

## Usage

``` r
# S3 method for class 'call_stack'
print(x, ...)
```

## Arguments

- x:

  A `call_stack` object, as returned by
  [`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md).

- ...:

  Unused, present for compatibility with the
  [`print()`](https://rdrr.io/r/base/print.html) generic.

## Value

`x`, invisibly. Called for its side effect of printing the tree.

## Examples

``` r
print(call_stack("mean.default", max_depth = 1))
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

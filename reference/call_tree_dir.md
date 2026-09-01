# Build the call tree of every function defined in a directory of R files

`call_tree_dir()` parses every `.R` file in `path` without evaluating
any of it, extracts each top-level function definition
(`name <- function(...) ...`), and builds the call graph among those
locally-defined functions. The result is the tree of calls reachable
from `root`, in the same shape
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
returns, so it prints the same way.

Unlike
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md),
which resolves an already-loaded function through R's own namespace
lookup, `call_tree_dir()` never loads or runs the scanned files. That
makes it usable on a package's `R/` directory, or a Shiny app's source,
without installing or sourcing it first.

## Usage

``` r
call_tree_dir(path = "R", root, modules_only = FALSE)
```

## Arguments

- path:

  Character scalar; directory containing `.R` files. Default `"R"`.

- root:

  Character scalar; name of the function to root the tree at. Must be
  one of the top-level functions found in `path`.

- modules_only:

  Logical. When `TRUE`, prune the tree to `root` plus functions that
  call [`shiny::NS()`](https://rdrr.io/pkg/shiny/man/NS.html) or
  [`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html)
  (Shiny modules); everything else is spliced out, promoting its
  children so modules reached through a non-module wrapper function stay
  visible. Default `FALSE`, which keeps every locally-defined function
  reachable from `root`.

## Value

An object of class `call_stack` (see
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)).

## See also

[`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
for the equivalent on a running Shiny app.

## Examples

``` r
if (FALSE) { # \dontrun{
call_tree_dir("R", root = "launch_app")
call_tree_dir("R", root = "launch_app", modules_only = TRUE)
} # }
```

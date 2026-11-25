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
call_tree_dir(
  path = "R",
  root,
  modules_only = FALSE,
  exclude = NULL,
  max_depth = Inf,
  keep = NULL,
  prune = NULL,
  include_ns = NULL,
  include_defaults = FALSE
)
```

## Arguments

- path:

  Character scalar; directory containing `.R` files. Default `"R"`.

- root:

  Character scalar; name of the function to root the tree at. Must be
  one of the top-level functions found in `path`; otherwise
  `call_tree_dir()` errors rather than returning an empty tree.

- modules_only:

  Logical. When `TRUE`, prune the tree to `root`, the functions `root`
  calls directly, and functions that call
  [`shiny::NS()`](https://rdrr.io/pkg/shiny/man/NS.html) or
  [`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html)
  (Shiny modules); everything else is spliced out, promoting its
  children so modules reached through a non-module wrapper function stay
  visible. Default `FALSE`, which keeps every locally-defined function
  reachable from `root`.

- exclude:

  Character vector of function names to drop from the tree, e.g. a
  logging helper such as `"logr_msg"` that appears under every node. A
  dropped function's children are spliced up into its place, as with
  `modules_only`. The root is never dropped. Default `NULL`, which drops
  nothing.

- max_depth:

  Number of levels to show below `root`. Default `Inf`, which shows the
  whole tree; `1` shows only the functions `root` calls. Counted after
  `modules_only`, `exclude`, `prune`, and `keep` are applied.

- keep:

  Character vector of regular expressions, e.g. `"^mod_counts_"`. When
  given, the tree is trimmed to nodes whose name matches one of them
  (with their full subtrees) plus the nodes on the path from `root` down
  to each match. Use `"^name$"` for an exact name. Default `NULL`, which
  keeps everything.

- prune:

  Character vector of function names to drop together with everything
  below them. Unlike `exclude`, children are not spliced up. Default
  `NULL`, which drops nothing.

- include_ns:

  Character vector of package names, e.g. `c("shiny", "bslib")`. Calls
  to functions exported by these packages (bare, as `pkg::fun()`, or
  `pkg:::fun()`) are shown as nodes, nested by how the calls are
  written: `shinyApp(ui = app_ui, server = app_server)` puts `app_ui`
  and `app_server` under `shinyApp`. External functions are not followed
  into their own source, and syntax such as braces, `<-`, or `if` is
  never shown (so `"base"` is usable). The packages must be installed.
  Default `NULL`, which shows only locally-defined functions.

- include_defaults:

  Logical. When `TRUE`, calls in default argument values
  (`function(dir = util_dir())`) are included alongside calls in the
  body. Default `FALSE`.

## Value

An object of class `call_stack` (see
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)).

## Details

When `modules_only = TRUE`, the functions `root` calls directly (such as
`app_ui()` and `app_server()`) are always kept, so UI and server modules
stay grouped under them.

A function defined more than once in `path` raises a warning naming the
files; the definition parsed last (files in alphabetical order) is used.

## See also

[`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
for the equivalent on a Shiny app object.

## Examples

``` r
if (FALSE) { # \dontrun{
call_tree_dir("R", root = "launch_app")
call_tree_dir("R", root = "launch_app", modules_only = TRUE)
call_tree_dir("R", root = "launch_app", exclude = "logr_msg")
call_tree_dir("R", root = "nav_ui", keep = "^mod_counts_")
call_tree_dir("R", root = "launch_app", include_ns = "shiny", max_depth = 2)
} # }
```

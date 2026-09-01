# Shiny module trees

``` r

library(stackcallr)
```

## Two functions, two entry points

[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
starts from a function that R can already find by name. A Shiny app
usually isn’t in that position: its functions live in a directory of
`.R` files that hasn’t been installed, or inside the environment of an
app object that was built but never launched.

`stackcallr` covers both cases with two functions:

- [`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
  reads a directory of `.R` files from disk and builds the call graph
  among the functions defined there, without evaluating any of it.
- [`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
  inspects a `shiny.appobj` at runtime and builds the call graph among
  the functions visible to its server function.

Both return an object of class `call_stack`, the same class
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
returns, so both print as the same block-character tree. There’s no
separate renderer to learn.

## Scanning a directory with `call_tree_dir()`

`call_tree_dir(path, root, modules_only)` parses every `.R` file in
`path`, extracts each top-level function definition
(`name <- function(...) ...`), and builds the call graph among those
locally-defined functions. It returns the tree of calls reachable from
`root`.

Nothing in the scanned files is loaded, sourced, or run. That’s what
makes it usable on a package’s `R/` directory, or on a Shiny app’s
source, without installing it first.

The code below writes a throwaway app into a temporary directory: a
`launch()` function that assembles the app, an `app_ui()`/`app_server()`
pair, and one module, `mod_a_ui()`/`mod_a_server()`.

``` r

app_dir <- tempfile("app")
dir.create(app_dir)

writeLines(
  'launch <- function() { shinyApp(ui = app_ui(), server = app_server) }',
  file.path(app_dir, "launch.R")
)
writeLines(
  'app_ui <- function() { mod_a_ui("a") }',
  file.path(app_dir, "app_ui.R")
)
writeLines(
  'app_server <- function(input, output, session) { mod_a_server("a") }',
  file.path(app_dir, "app_server.R")
)
writeLines(
  'mod_a_ui <- function(id) { ns <- NS(id) }',
  file.path(app_dir, "mod_a_ui.R")
)
writeLines(
  c(
    'mod_a_server <- function(id) {',
    '  moduleServer(id, function(input, output, session) { helper() })',
    '}'
  ),
  file.path(app_dir, "mod_a_server.R")
)
writeLines(
  'helper <- function() 1',
  file.path(app_dir, "helper.R")
)
```

Rooting the tree at `launch` gives every locally-defined function
reachable from it:

``` r

call_tree_dir(app_dir, root = "launch")
#> █─launch
#> ├─█─app_ui
#> │ └─mod_a_ui
#> └─█─app_server
#>   └─█─mod_a_server
#>     └─helper
```

Note that `helper()` shows up under `mod_a_server()`, and that
[`shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html) does not
show up at all. Only functions defined in the scanned files become
nodes; calls out to `shiny` or any other package are ignored, since
there’s no local definition to expand.

If `root` isn’t one of the top-level functions found in `path`, the
function errors rather than returning an empty tree.

## Showing only modules with `modules_only`

Both functions take `modules_only`. When `TRUE`, the tree is pruned to
`root` plus the functions that call
[`shiny::NS()`](https://rdrr.io/pkg/shiny/man/NS.html) or
[`shiny::moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html).
That pair of names is the static test for “this function is a Shiny
module”: it’s a pattern match on the parsed expression, not a call into
shiny.

``` r

call_tree_dir(app_dir, root = "launch", modules_only = TRUE)
#> █─launch
#> ├─mod_a_ui
#> └─mod_a_server
```

The interesting part is what happened to `app_ui()` and `app_server()`.
Neither calls [`NS()`](https://rdrr.io/pkg/shiny/man/NS.html) or
[`moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html)
directly, so neither survives the prune, but the modules underneath them
are still in the tree. When a node is dropped, its children are spliced
up into its parent’s position rather than dropped with it. Without that,
a real module reached only through a plain wrapper function would vanish
from the pruned tree, and `modules_only` would be close to useless on
any app with a UI assembly layer.

`helper()` is gone, because it isn’t a module and has no module
descendants to promote.

## Inspecting a live app with `call_tree_app()`

`call_tree_app(app, app_fun, ui_fun, server_fun, modules_only)` works on
a `shiny.appobj`, the object returned by
[`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html) or
[`shiny::shinyAppDir()`](https://rdrr.io/pkg/shiny/man/shinyApp.html).
Instead of reading files, it extracts the app’s server function, walks
the server’s enclosing environment chain to collect every visible
function, and builds the call graph among those.

Constructing a `shiny.appobj` does not start a server, so the app below
is safe to build in a knitted document. It defines a module and a
UI/server pair, then passes both to
[`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html).

``` r

library(shiny)

app <- local({
  mod_a_ui <- function(id) {
    ns <- NS(id)
    tagList(textOutput(ns("out")))
  }
  mod_a_server <- function(id) {
    moduleServer(id, function(input, output, session) {
      output$out <- renderText("hello")
    })
  }
  app_ui <- function() fluidPage(mod_a_ui("a"))
  app_server <- function(input, output, session) mod_a_server("a")

  shinyApp(ui = app_ui, server = app_server)
})

call_tree_app(app)
#> █─app
#> ├─█─app_ui
#> │ └─mod_a_ui
#> └─█─app_server
#>   └─mod_a_server
```

The root node is labelled `"app"` by default. The app object doesn’t
store the name of the function that built it, so `app_fun` is display
text only:

``` r

call_tree_app(app, app_fun = "launch", modules_only = TRUE)
#> █─launch
#> ├─mod_a_ui
#> └─mod_a_server
```

### Naming the UI function

`ui_fun` and `server_fun` default to `NULL`, which means
[`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
recovers the names itself by comparing function bodies against the
functions it collected from the environment.

For the server function this is reliable. For the UI it depends on how
`ui` was passed to
[`shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html). Passing a
bare function reference (`shinyApp(ui = app_ui, ...)`) stores the
function, and the name can be recovered. Passing a pre-evaluated call
(`shinyApp(ui = app_ui(), ...)`) stores the resulting tag list, and
there’s no function left to match, so the UI branch is dropped.

That second form is common. When you’re using it, name the UI function
explicitly:

``` r

app2 <- local({
  mod_a_ui <- function(id) tagList(textOutput(NS(id)("out")))
  mod_a_server <- function(id) {
    moduleServer(id, function(input, output, session) {})
  }
  app_ui <- function() fluidPage(mod_a_ui("a"))
  app_server <- function(input, output, session) mod_a_server("a")

  shinyApp(ui = app_ui(), server = app_server)
})

call_tree_app(app2, ui_fun = "app_ui")
#> █─app
#> ├─█─app_ui
#> │ └─mod_a_ui
#> └─█─app_server
#>   └─mod_a_server
```

## How resolution works

Neither function runs the app.
[`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
works entirely from parsed source:

1.  Every `.R` file in `path` is parsed with
    [`parse()`](https://rdrr.io/r/base/parse.html). Files that fail to
    parse are skipped rather than raising an error.
2.  Each top-level expression is checked for a function assignment
    (`name <- function(...)`, `name = function(...)`, or
    `assign("name", function(...))`), and the name and unevaluated body
    are kept.
3.  Each body is walked recursively for references to the other
    collected names, counting both direct calls (`fun()`) and bare
    references (`fun`), so a function passed as an argument still
    registers as an edge.
4.  The tree is built depth-first from `root`, skipping any name already
    on the current path, so recursive or mutually recursive functions
    don’t loop forever.
5.  When `modules_only = TRUE`, each body is tested for
    [`NS()`](https://rdrr.io/pkg/shiny/man/NS.html) or
    [`moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html)
    (bare or namespaced), and non-matching nodes are spliced out.

[`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
follows the same steps 3 through 5. It differs only in where the
functions come from: `app$serverFuncSource()` gives the server function,
[`environment()`](https://rdrr.io/r/base/environment.html) gives its
enclosure, and the environment chain is walked upward, collecting
functions until it reaches
[`globalenv()`](https://rdrr.io/r/base/environment.html),
[`baseenv()`](https://rdrr.io/r/base/environment.html), or a loaded
package namespace.

## What it can’t inspect

[`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
requires a `shiny.appobj`. It cannot inspect the `ShinyAppHandle`
returned by
[`shiny::startApp()`](https://rdrr.io/pkg/shiny/man/startApp.html)
(added in shiny 1.14.0). That handle is a runtime control object,
exposing [`stop()`](https://rdrr.io/r/base/stop.html), `status()`,
[`url()`](https://rdrr.io/r/base/connections.html), and `result()` for
an app that may be running in a separate process, and it holds no
reference back to the app’s UI, server, or environment. Passing one
raises an error that says so, and tells you to pass the `shiny.appobj`
itself, before calling
[`startApp()`](https://rdrr.io/pkg/shiny/man/startApp.html) on it.

Two other limits are worth knowing:

- [`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
  only sees top-level function definitions. A function defined inside
  another function, or built by a factory, isn’t a node.
- [`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
  only sees what’s visible from the server’s environment chain.
  Functions that live in an unrelated environment, or in a package
  namespace, stop the walk rather than being expanded.

## Shiny isn’t a dependency

Neither function requires shiny to be installed for `stackcallr` to
work.
[`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
matches on the names `NS` and `moduleServer` in parsed code, which is
text, not a call.
[`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
identifies the object it’s handed with
[`inherits()`](https://rdrr.io/r/base/class.html) and reaches into it
with `$`; there is no `shiny::` call anywhere in its body.

Shiny is in `Suggests`, and you need it only if you’re building a
`shiny.appobj` to pass in.

## Learning more

See
[`?call_tree_dir`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
and
[`?call_tree_app`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
for the full argument reference, and
[`vignette("stackcallr")`](https://mjfrigaard.github.io/stackcallr/articles/stackcallr.md)
for
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md),
which covers the case these two complement: a single function R can
already resolve by name.

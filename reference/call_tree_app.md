# Build the call tree of a running Shiny app

`call_tree_app()` inspects a
[`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html)
object at runtime, rather than parsing source files on disk. It extracts
the server function, collects every function visible in the server's
enclosing environment chain, and builds the call graph among them, in
the same shape
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)
returns.

`call_tree_app()` never calls into the shiny package itself; it only
inspects the structure of the `shiny.appobj` you pass in, so stackcallr
does not need shiny installed unless you're building one.

This only works on a `shiny.appobj`. It can't inspect the
`ShinyAppHandle` returned by
[`shiny::startApp()`](https://rdrr.io/pkg/shiny/man/startApp.html): that
handle is a runtime control object
([`stop()`](https://rdrr.io/r/base/stop.html)/`status()`/[`url()`](https://rdrr.io/r/base/connections.html)/`result()`)
for an app that may be running in a separate process, and it exposes no
reference back to the app's UI, server, or environment. Pass the
`shiny.appobj` itself, before calling `startApp()` on it.

## Usage

``` r
call_tree_app(
  app,
  app_fun = "app",
  ui_fun = NULL,
  server_fun = NULL,
  modules_only = FALSE
)
```

## Arguments

- app:

  A `shiny.appobj`, as returned by
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html) or
  [`shiny::shinyAppDir()`](https://rdrr.io/pkg/shiny/man/shinyApp.html).
  Not the `ShinyAppHandle` returned by
  [`shiny::startApp()`](https://rdrr.io/pkg/shiny/man/startApp.html).

- app_fun:

  Character scalar; label used for the root node. The app object doesn't
  store the name of its own launch function, so this is display text
  only. Default `"app"`.

- ui_fun:

  Character scalar or `NULL`; name of the UI function. When `NULL` (the
  default), `call_tree_app()` tries to recover it automatically, which
  only works when `ui` was passed to
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html) as
  an unevaluated function (`shinyApp(ui = app_ui, ...)`). If `ui` was
  pre-evaluated (`shinyApp(ui = app_ui(), ...)`), supply the name
  explicitly so the UI branch is included.

- server_fun:

  Character scalar or `NULL`; name of the server function. When `NULL`
  (the default), the name is inferred by comparing function bodies
  against those visible in the server's environment.

- modules_only:

  Logical; see
  [`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md).
  Default `FALSE`.

## Value

An object of class `call_stack` (see
[`call_stack()`](https://mjfrigaard.github.io/stackcallr/reference/call_stack.md)).

## See also

[`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
for the file-based equivalent.

## Examples

``` r
if (FALSE) { # \dontrun{
app <- shiny::shinyApp(ui = app_ui, server = app_server)
call_tree_app(app)
call_tree_app(app, modules_only = TRUE)
} # }
```

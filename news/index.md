# Changelog

## stackcallr 0.1.0

### New features

- New
  [`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
  builds the call tree of every function defined in a directory of `.R`
  files, by parsing them without loading or running any of it. Works on
  a package’s `R/` directory or a Shiny app’s source before it’s
  installed.

- New
  [`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
  builds the same kind of tree from a running Shiny app, by inspecting a
  `shiny.appobj`’s server function and its enclosing environment at
  runtime.

- Both functions gain a `modules_only` argument that prunes the tree to
  `root` plus functions that call
  [`NS()`](https://rdrr.io/pkg/shiny/man/NS.html)/[`moduleServer()`](https://rdrr.io/pkg/shiny/man/moduleServer.html)
  (Shiny modules). A dropped wrapper function’s children are spliced up
  into its parent’s position, so a real module reached only through a
  non-module wrapper stays visible.

- [`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md)
  detects the `ShinyAppHandle` returned by
  [`shiny::startApp()`](https://rdrr.io/pkg/shiny/man/startApp.html)
  (shiny \>= 1.14.0) and errors with an explanation, since that handle
  is a runtime control object with no reference back to the app’s UI or
  server for inspection.

### Documentation

- New vignette, “Shiny module trees”
  ([`vignette("shiny-modules", package = "stackcallr")`](https://mjfrigaard.github.io/stackcallr/articles/shiny-modules.md)),
  covering
  [`call_tree_dir()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_dir.md)
  and
  [`call_tree_app()`](https://mjfrigaard.github.io/stackcallr/reference/call_tree_app.md).

### Other

- `shiny` and `withr` added to `Suggests`, used only in tests. Neither
  new function requires shiny to be installed for stackcallr itself to
  work.

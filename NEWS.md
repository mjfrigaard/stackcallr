# stackcallr 0.1.0

## New features

* New `call_tree_dir()` builds the call tree of every function defined in a directory of `.R` files, by parsing them without loading or running any of it. Works on a package's `R/` directory or a Shiny app's source before it's installed.

* New `call_tree_app()` builds the same kind of tree from a running Shiny app, by inspecting a `shiny.appobj`'s server function and its enclosing environment at runtime.

* Both functions gain a `modules_only` argument that prunes the tree to `root` plus functions that call `NS()`/`moduleServer()` (Shiny modules). A dropped wrapper function's children are spliced up into its parent's position, so a real module reached only through a non-module wrapper stays visible.

* `call_tree_app()` detects the `ShinyAppHandle` returned by `shiny::startApp()` (shiny >= 1.14.0) and errors with an explanation, since that handle is a runtime control object with no reference back to the app's UI or server for inspection.

## Documentation

* New vignette, "Shiny module trees" (`vignette("shiny-modules", package = "stackcallr")`), covering `call_tree_dir()` and `call_tree_app()`.

## Other

* `shiny` and `withr` added to `Suggests`, used only in tests. Neither new function requires shiny to be installed for stackcallr itself to work.

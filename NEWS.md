# stackcallr 0.3.0

## New features

* `call_tree_dir()` reads R6 classes. Each method is a node named `Class$method`, with `initialize` shown as `Class$new`. `Class$new()`, `self$m()`, `private$m()`, `super$m()`, and `x$m()` on a local `x <- Class$new()` are followed. Methods can be roots (`root = "ModInputs$ui"`). With `modules_only`, a class whose methods call `NS()` or `moduleServer()` counts as a module.

## Bug fixes

* The name after `$` or `@` is no longer read as a call: `result$class_diffs` doesn't draw an edge to a `class_diffs()` function.

# stackcallr 0.2.1

## Bug fixes

* `call_tree_dir()` and `call_tree_app()` no longer draw an edge when a parameter or local variable shares a function's name. In `function(savings_rate) income * savings_rate`, the bare `savings_rate` refers to the argument, not the `savings_rate()` function. Calls in call position (`savings_rate()`) still count.

# stackcallr 0.2.0

## New features

* `call_tree_dir()` and `call_tree_app()` gain `max_depth` (levels shown below `root`), `prune` (drop a function and its whole subtree, without splicing its children up), and `keep` (regular expressions; keep matching functions with their subtrees plus the path from `root` to them).

* `call_tree_dir()` gains `include_ns`: calls to functions exported by the named packages are shown as nodes, nested as written, so `shinyApp(ui = app_ui, server = app_server)` puts both functions under `shinyApp`.

* `call_tree_dir()` gains `include_defaults`: when `TRUE`, calls in default argument values (`function(dir = util_dir())`) are included.

* `call_tree_dir()` warns when a function is defined more than once in `path`, naming each function and its files.

## Breaking changes

* With `modules_only = TRUE`, the functions `root` calls directly (such as `app_ui()` and `app_server()`) are now kept, so UI and server modules stay grouped under them. Deeper non-module functions are still spliced out.

## Earlier changes


* `call_stack()`, `call_tree_dir()`, and `call_tree_app()` gain an `exclude` argument: a character vector of function names to drop from the tree (for example a logging helper that appears under every node). A dropped function's children are spliced up into its place.

* `call_tree_dir()` no longer errors on files with a top-level namespaced call such as `utils::globalVariables(...)`.

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

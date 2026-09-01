#' Build the call tree of a running Shiny app
#'
#' @description
#' `call_tree_app()` inspects a [shiny::shinyApp()] object at runtime,
#' rather than parsing source files on disk. It extracts the server
#' function, collects every function visible in the server's enclosing
#' environment chain, and builds the call graph among them, in the same
#' shape [call_stack()] returns.
#'
#' `call_tree_app()` never calls into the shiny package itself; it only
#' inspects the structure of the `shiny.appobj` you pass in, so stackcallr
#' does not need shiny installed unless you're building one.
#'
#' This only works on a `shiny.appobj`. It can't inspect the
#' `ShinyAppHandle` returned by [shiny::startApp()]: that handle is a
#' runtime control object (`stop()`/`status()`/`url()`/`result()`) for an
#' app that may be running in a separate process, and it exposes no
#' reference back to the app's UI, server, or environment. Pass the
#' `shiny.appobj` itself, before calling `startApp()` on it.
#'
#' @param app A `shiny.appobj`, as returned by [shiny::shinyApp()] or
#'   [shiny::shinyAppDir()]. Not the `ShinyAppHandle` returned by
#'   [shiny::startApp()].
#' @param app_fun Character scalar; label used for the root node. The app
#'   object doesn't store the name of its own launch function, so this is
#'   display text only. Default `"app"`.
#' @param ui_fun Character scalar or `NULL`; name of the UI function. When
#'   `NULL` (the default), `call_tree_app()` tries to recover it
#'   automatically, which only works when `ui` was passed to
#'   `shiny::shinyApp()` as an unevaluated function
#'   (`shinyApp(ui = app_ui, ...)`). If `ui` was pre-evaluated
#'   (`shinyApp(ui = app_ui(), ...)`), supply the name explicitly so the UI
#'   branch is included.
#' @param server_fun Character scalar or `NULL`; name of the server
#'   function. When `NULL` (the default), the name is inferred by
#'   comparing function bodies against those visible in the server's
#'   environment.
#' @param modules_only Logical; see [call_tree_dir()]. Default `FALSE`.
#'
#' @return An object of class `call_stack` (see [call_stack()]).
#'
#' @examples
#' \dontrun{
#' app <- shiny::shinyApp(ui = app_ui, server = app_server)
#' call_tree_app(app)
#' call_tree_app(app, modules_only = TRUE)
#' }
#'
#' @seealso [call_tree_dir()] for the file-based equivalent.
#'
#' @export
call_tree_app <- function(app,
                           app_fun = "app",
                           ui_fun = NULL,
                           server_fun = NULL,
                           modules_only = FALSE) {
  if (inherits(app, "ShinyAppHandle")) {
    stop(
      "`app` is a ShinyAppHandle, returned by shiny::startApp(). ",
      "It's a runtime control handle (stop()/status()/url()/result()) for ",
      "an app that may be running in a separate process, so it doesn't ",
      "expose the app's UI, server, or environment for call_tree_app() to ",
      "inspect. Pass the shiny.appobj itself, before calling startApp() ",
      "on it, e.g. call_tree_app(app) where `app <- shiny::shinyApp(...)`.",
      call. = FALSE
    )
  }

  if (!inherits(app, "shiny.appobj")) {
    stop(
      "`app` must be a shiny.appobj, created with shiny::shinyApp() or ",
      "shiny::shinyAppDir().",
      call. = FALSE
    )
  }

  server_fn <- app$serverFuncSource()
  env <- environment(server_fn)

  known_fns <- collect_env_functions(env)
  known_names <- names(known_fns)

  s_name <- server_fun
  if (is.null(s_name)) {
    s_name <- find_fn_name(server_fn, known_fns)
  }
  if (is.null(s_name)) {
    s_name <- "server"
  }

  ui_stored <- tryCatch(environment(app$httpHandler)$ui, error = function(e) NULL)

  if (!is.null(ui_fun)) {
    ui_fn <- tryCatch(get(ui_fun, envir = env, inherits = TRUE), error = function(e) NULL)
    ui_name <- ui_fun
    if (!is.null(ui_fn) && !ui_name %in% known_names) {
      known_fns[[ui_name]] <- ui_fn
      known_names <- c(known_names, ui_name)
    }
  } else if (is.function(ui_stored)) {
    ui_fn <- ui_stored
    ui_name <- find_fn_name(ui_fn, known_fns)
    if (is.null(ui_name)) {
      ui_name <- "ui"
      known_fns[["ui"]] <- ui_fn
      known_names <- c(known_names, "ui")
    }
  } else {
    ui_name <- NULL
  }

  call_graph <- list()
  call_graph[[app_fun]] <- Filter(Negate(is.null), c(ui_name, s_name))

  for (nm in setdiff(known_names, app_fun)) {
    fn <- known_fns[[nm]]
    call_graph[[nm]] <- intersect(find_calls(body(fn), known_names), known_names)
  }

  tree <- build_tree(app_fun, call_graph)

  if (modules_only) {
    is_module <- vapply(known_fns, function(f) uses_ns(body(f)), logical(1))
    tree$calls <- prune_children(tree$calls, names(which(is_module)))
  }

  class(tree) <- "call_stack"
  tree
}

#' Collect every function visible in an environment and its parents
#'
#' Walks up the environment chain from `env`, gathering functions until
#' `globalenv()`/`baseenv()` or a loaded package namespace is reached.
#'
#' @noRd
collect_env_functions <- function(env) {
  known_fns <- list()
  e <- env
  while (!identical(e, emptyenv())) {
    local_fns <- Filter(is.function, as.list(e))
    new_names <- setdiff(names(local_fns), names(known_fns))
    known_fns <- c(known_fns, local_fns[new_names])
    if (identical(e, globalenv()) || identical(e, baseenv())) {
      break
    }
    env_nm <- environmentName(e)
    if (nchar(env_nm) > 0 && env_nm %in% loadedNamespaces()) {
      break
    }
    e <- parent.env(e)
  }
  known_fns
}

#' Match a function to its name in a named list by comparing bodies
#'
#' @noRd
find_fn_name <- function(fn, known_fns) {
  for (nm in names(known_fns)) {
    if (identical(body(fn), body(known_fns[[nm]]))) {
      return(nm)
    }
  }
  NULL
}

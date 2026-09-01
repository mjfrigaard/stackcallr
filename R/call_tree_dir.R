#' Build the call tree of every function defined in a directory of R files
#'
#' @description
#' `call_tree_dir()` parses every `.R` file in `path` without evaluating any
#' of it, extracts each top-level function definition
#' (`name <- function(...) ...`), and builds the call graph among those
#' locally-defined functions. The result is the tree of calls reachable
#' from `root`, in the same shape [call_stack()] returns, so it prints the
#' same way.
#'
#' Unlike [call_stack()], which resolves an already-loaded function through
#' R's own namespace lookup, `call_tree_dir()` never loads or runs the
#' scanned files. That makes it usable on a package's `R/` directory, or a
#' Shiny app's source, without installing or sourcing it first.
#'
#' @param path Character scalar; directory containing `.R` files. Default
#'   `"R"`.
#' @param root Character scalar; name of the function to root the tree at.
#'   Must be one of the top-level functions found in `path`.
#' @param modules_only Logical. When `TRUE`, prune the tree to `root` plus
#'   functions that call [shiny::NS()] or [shiny::moduleServer()] (Shiny
#'   modules); everything else is spliced out, promoting its children so
#'   modules reached through a non-module wrapper function stay visible.
#'   Default `FALSE`, which keeps every locally-defined function reachable
#'   from `root`.
#'
#' @return An object of class `call_stack` (see [call_stack()]).
#'
#' @examples
#' \dontrun{
#' call_tree_dir("R", root = "launch_app")
#' call_tree_dir("R", root = "launch_app", modules_only = TRUE)
#' }
#'
#' @seealso [call_tree_app()] for the equivalent on a running Shiny app.
#'
#' @export
call_tree_dir <- function(path = "R", root, modules_only = FALSE) {
  stopifnot(
    "`path` must be a single character string" = is.character(path) && length(path) == 1,
    "`root` must be a single character string" = is.character(root) && length(root) == 1
  )

  func_defs <- parse_dir_functions(path)
  known_names <- names(func_defs)

  if (!root %in% known_names) {
    stop(
      "Could not find a top-level function named `", root, "` in \"", path, "\".",
      call. = FALSE
    )
  }

  call_graph <- lapply(func_defs, function(body) {
    intersect(find_calls(body, known_names), known_names)
  })

  tree <- build_tree(root, call_graph)

  if (modules_only) {
    is_module <- vapply(func_defs, uses_ns, logical(1))
    tree$calls <- prune_children(tree$calls, names(which(is_module)))
  }

  class(tree) <- "call_stack"
  tree
}

#' Parse every .R file in a directory and collect top-level function defs
#'
#' Returns a named list of function bodies (unevaluated), keyed by the name
#' each was assigned to. Files that fail to parse are skipped.
#'
#' @noRd
parse_dir_functions <- function(path) {
  r_files <- list.files(path, pattern = "\\.[Rr]$", full.names = TRUE)

  func_defs <- list()
  for (f in r_files) {
    exprs <- tryCatch(parse(f), error = function(e) NULL)
    if (is.null(exprs)) {
      next
    }
    for (expr in exprs) {
      def <- extract_func_def(expr)
      if (!is.null(def)) {
        func_defs[[def$name]] <- def$body
      }
    }
  }
  func_defs
}

#' Extract a function definition from a parsed expression
#'
#' Checks whether `expr` is a top-level function assignment
#' (`name <- function(...) ...`, `name = function(...) ...`, or
#' `assign("name", function(...) ...)`) and returns its name and body.
#'
#' @noRd
extract_func_def <- function(expr) {
  if (!is.call(expr)) {
    return(NULL)
  }

  op <- as.character(expr[[1]])

  if (op %in% c("<-", "=", "assign") && length(expr) == 3) {
    name <- if (op == "assign") {
      if (is.character(expr[[2]])) expr[[2]] else return(NULL)
    } else {
      if (is.name(expr[[2]])) as.character(expr[[2]]) else return(NULL)
    }

    val <- expr[[3]]

    if (is.call(val) && as.character(val[[1]]) == "function") {
      return(list(name = name, body = val))
    }
  }

  NULL
}

#' Find references to known functions within a parsed expression
#'
#' Recursively walks `expr` and collects the names of any functions that
#' appear as either direct calls (`fun()`) or bare name references (`fun`).
#'
#' @noRd
find_calls <- function(expr, known_names) {
  found <- character(0)
  if (is.call(expr)) {
    fn <- expr[[1]]
    if (is.name(fn)) {
      fn_name <- as.character(fn)
      if (fn_name %in% known_names) {
        found <- c(found, fn_name)
      }
    }
    for (i in seq_along(expr)) {
      found <- c(found, find_calls(expr[[i]], known_names))
    }
  } else if (is.name(expr)) {
    nm <- as.character(expr)
    if (nm %in% known_names) {
      found <- c(found, nm)
    }
  }
  unique(found)
}

#' Check whether an expression contains Shiny module identifiers
#'
#' Recursively walks a parsed expression to detect calls to
#' [shiny::NS()] or [shiny::moduleServer()], a reliable indicator that a
#' function is a Shiny module. This is a static pattern match on function
#' names, not a call into the shiny package.
#'
#' @noRd
uses_ns <- function(expr) {
  if (is.call(expr)) {
    fn <- expr[[1]]
    if (is.name(fn)) {
      fn_name <- as.character(fn)
      if (fn_name %in% c("NS", "moduleServer")) {
        return(TRUE)
      }
    }
    if (is.call(fn) && length(fn) == 3) {
      op <- as.character(fn[[1]])
      if (op %in% c("::", ":::")) {
        if (as.character(fn[[3]]) %in% c("NS", "moduleServer")) {
          return(TRUE)
        }
      }
    }
    for (i in seq_along(expr)) {
      if (uses_ns(expr[[i]])) {
        return(TRUE)
      }
    }
  }
  FALSE
}

#' Depth-first build of a call_stack-shaped tree from a call graph
#'
#' @param node Character scalar; the root function name.
#' @param call_graph Named list where each element is a character vector of
#'   function names called by that function.
#' @param visited Character vector of already-visited node names (used
#'   internally to prevent cycles).
#'
#' @noRd
build_tree <- function(node, call_graph, visited = character(0)) {
  child_names <- setdiff(call_graph[[node]], c(visited, node))

  calls <- lapply(child_names, function(child) {
    build_tree(child, call_graph, visited = c(visited, node))
  })

  list(name = node, calls = calls)
}

#' Prune a list of call_stack nodes to only those named in `keep_names`
#'
#' A dropped node's children are spliced up into its parent's position, so
#' a kept descendant reached only through a dropped node stays reachable.
#'
#' @noRd
prune_children <- function(calls, keep_names) {
  out <- list()
  for (child in calls) {
    pruned_grandchildren <- prune_children(child$calls, keep_names)
    if (child$name %in% keep_names) {
      out <- c(out, list(list(name = child$name, calls = pruned_grandchildren)))
    } else {
      out <- c(out, pruned_grandchildren)
    }
  }
  out
}

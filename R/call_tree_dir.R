#' Build the call tree of every function defined in a directory of R files
#'
#' @description
#' `call_tree_dir()` parses every `.R` file in `path` without evaluating any
#' of it, extracts each top-level function definition
#' (`name <- function(...) ...`) and the methods of each R6 class
#' (`Name <- R6Class(...)`), and builds the call graph among those
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
#' @param root Character scalar; name of the function to root the tree at,
#'   or an R6 method written as `"Class$method"` (`"Class$new"` for
#'   `initialize`). Must be one of the functions found in `path`; otherwise
#'   `call_tree_dir()` errors rather than returning an empty tree.
#' @param modules_only Logical. When `TRUE`, prune the tree to `root`, the
#'   functions `root` calls directly, and functions that call [shiny::NS()]
#'   or [shiny::moduleServer()] (Shiny modules); everything else is spliced
#'   out, promoting its children so
#'   modules reached through a non-module wrapper function stay visible.
#'   Default `FALSE`, which keeps every locally-defined function reachable
#'   from `root`.
#' @param exclude Character vector of function names to drop from the tree,
#'   e.g. a logging helper such as `"logr_msg"` that appears under every
#'   node. A dropped function's children are spliced up into its place, as
#'   with `modules_only`. The root is never dropped. Default `NULL`, which
#'   drops nothing.
#' @param max_depth Number of levels to show below `root`. Default `Inf`,
#'   which shows the whole tree; `1` shows only the functions `root` calls.
#'   Counted after `modules_only`, `exclude`, `prune`, and `keep` are
#'   applied.
#' @param keep Character vector of regular expressions, e.g.
#'   `"^mod_counts_"`. When given, the tree is trimmed to nodes whose name
#'   matches one of them (with their full subtrees) plus the nodes on the
#'   path from `root` down to each match. Use `"^name$"` for an exact name.
#'   Default `NULL`, which keeps everything.
#' @param prune Character vector of function names to drop together with
#'   everything below them. Unlike `exclude`, children are not spliced up.
#'   Default `NULL`, which drops nothing.
#' @param include_ns Character vector of package names, e.g.
#'   `c("shiny", "bslib")`. Calls to functions exported by these packages
#'   (bare, as `pkg::fun()`, or `pkg:::fun()`) are shown as nodes, nested
#'   by how the calls are written: `shinyApp(ui = app_ui, server =
#'   app_server)` puts `app_ui` and `app_server` under `shinyApp`. External
#'   functions are not followed into their own source, and syntax such as
#'   braces, `<-`, or `if` is never shown (so `"base"` is usable). The packages
#'   must be installed. Default `NULL`, which shows only locally-defined functions.
#' @param include_defaults Logical. When `TRUE`, calls in default argument
#'   values (`function(dir = util_dir())`) are included alongside calls in
#'   the body. Default `FALSE`.
#'
#' @details
#' When `modules_only = TRUE`, the functions `root` calls directly (such as
#' `app_ui()` and `app_server()`) are always kept, so UI and server modules
#' stay grouped under them.
#'
#' R6 methods are nodes named `Class$method`, with `initialize` shown as
#' `Class$new`. `Class$new()` calls that node. `self$m()`, `private$m()`,
#' and `super$m()` resolve within the class, following `inherit`. A
#' variable assigned `Class$new(...)` inside a function (`x <-
#' Class$new()`) resolves `x$m()` to `Class$m`. With `modules_only`, a
#' class with any method that calls `NS()` or `moduleServer()` is a
#' module, and its `$new` and public methods are kept. The name after `$`
#' is never read as a call to a function of the same name.
#'
#' A function defined more than once in `path` raises a warning naming the
#' files; the definition parsed last (files in alphabetical order) is used.
#'
#' @return An object of class `call_stack` (see [call_stack()]).
#'
#' @examples
#' \dontrun{
#' call_tree_dir("R", root = "launch_app")
#' call_tree_dir("R", root = "launch_app", modules_only = TRUE)
#' call_tree_dir("R", root = "launch_app", exclude = "logr_msg")
#' call_tree_dir("R", root = "nav_ui", keep = "^mod_counts_")
#' call_tree_dir("R", root = "launch_app", include_ns = "shiny", max_depth = 2)
#' }
#'
#' @seealso [call_tree_app()] for the equivalent on a Shiny app object.
#'
#' @export
call_tree_dir <- function(path = "R",
                          root,
                          modules_only = FALSE,
                          exclude = NULL,
                          max_depth = Inf,
                          keep = NULL,
                          prune = NULL,
                          include_ns = NULL,
                          include_defaults = FALSE) {
  stopifnot(
    "`path` must be a single character string" = is.character(path) && length(path) == 1,
    "`root` must be a single character string" = is.character(root) && length(root) == 1,
    "`include_ns` must be NULL or a character vector" = is.null(include_ns) || is.character(include_ns),
    "`include_defaults` must be TRUE or FALSE" = isTRUE(include_defaults) || isFALSE(include_defaults)
  )
  check_trim_args(exclude, max_depth, keep, prune)

  func_defs <- parse_dir_functions(path)
  known_names <- names(func_defs)

  if (!root %in% known_names) {
    stop(
      "Could not find a top-level function named `", root, "` in \"", path, "\".",
      call. = FALSE
    )
  }

  ext_names <- ns_exports(include_ns)
  classes <- attr(func_defs, "r6_classes")
  call_graph <- lapply(structure(known_names, names = known_names), function(nm) {
    def <- func_defs[[nm]]
    exprs <- list(def)
    if (include_defaults) {
      exprs <- c(as.list(def[[2]]), exprs)
    }
    ctx <- if (length(classes) > 0) {
      list(classes = classes, self = r6_owner(nm, classes), vars = r6_instances(def, classes))
    }
    call_items(exprs, known_names, include_ns, ext_names, local_names(def), ctx)
  })

  tree <- build_tree(root, call_graph)

  modules <- if (modules_only) {
    unique(c(names(which(vapply(func_defs, uses_ns, logical(1)))), r6_module_nodes(classes)))
  }
  tree <- trim_tree(tree, modules, exclude, max_depth, keep, prune)

  class(tree) <- "call_stack"
  tree
}

#' Parse every .R file in a directory and collect top-level function defs
#'
#' Returns a named list of function definitions (unevaluated), keyed by the
#' name each was assigned to. R6 class methods are included as `Class$method`
#' (see `r6_method_defs()`), and the classes are kept in the `"r6_classes"`
#' attribute. Files that fail to parse are skipped. Names defined more than
#' once raise one warning listing each name and its files.
#'
#' @noRd
parse_dir_functions <- function(path) {
  r_files <- list.files(path, pattern = "\\.[Rr]$", full.names = TRUE)

  func_defs <- list()
  classes <- list()
  def_files <- list()
  for (f in r_files) {
    exprs <- tryCatch(parse(f), error = function(e) NULL)
    if (is.null(exprs)) {
      next
    }
    for (expr in exprs) {
      def <- extract_func_def(expr)
      cls <- if (is.null(def)) extract_r6_def(expr)
      if (!is.null(def)) {
        func_defs[[def$name]] <- def$body
        def_files[[def$name]] <- c(def_files[[def$name]], basename(f))
      } else if (!is.null(cls)) {
        classes[[cls$name]] <- cls
        def_files[[cls$name]] <- c(def_files[[cls$name]], basename(f))
      }
    }
  }

  dups <- Filter(function(x) length(x) > 1, def_files)
  if (length(dups) > 0) {
    warning(
      "Functions defined more than once in \"", path, "\" (the last one is used): ",
      paste0("`", names(dups), "` (", vapply(dups, paste, character(1), collapse = ", "), ")",
             collapse = "; "),
      call. = FALSE
    )
  }
  func_defs <- c(func_defs, r6_method_defs(classes))
  attr(func_defs, "r6_classes") <- classes
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
  if (!is.call(expr) || !is.name(expr[[1]])) {
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

    if (is.call(val) && identical(val[[1]], as.name("function"))) {
      return(list(name = name, body = val))
    }
  }

  NULL
}

#' Find references to known functions within a parsed expression
#'
#' Recursively walks `expr` and collects the names of any functions that
#' appear as either direct calls (`fun()`) or bare name references (`fun`).
#' A bare name is skipped when it is in `bound` (by default, the names
#' bound inside `expr`; see `local_names()`), since it then refers to a
#' parameter or variable, not the function.
#'
#' @noRd
find_calls <- function(expr, known_names, bound = local_names(expr)) {
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
      found <- c(found, find_calls(expr[[i]], known_names, bound))
    }
  } else if (is.name(expr)) {
    nm <- as.character(expr)
    if (nm %in% known_names && !nm %in% bound) {
      found <- c(found, nm)
    }
  }
  unique(found)
}

#' Names bound inside an expression
#'
#' Collects the parameters of every `function()` in `expr`, the targets of
#' `<-` and `=` assignments, and `for` loop variables. Scopes are not
#' tracked separately, so a name bound anywhere in `expr` counts for all of
#' it. Calls in call position (`fun()`) are unaffected, because R skips
#' non-function bindings when it looks up a function to call.
#'
#' @noRd
local_names <- function(expr) {
  if (!is.call(expr)) {
    return(character(0))
  }
  out <- character(0)
  fn <- expr[[1]]
  if (is.name(fn)) {
    op <- as.character(fn)
    if (op == "function") {
      out <- names(expr[[2]])
    } else if (op %in% c("<-", "=", "for") && is.name(expr[[2]])) {
      out <- as.character(expr[[2]])
    }
  }
  for (i in seq_along(expr)) {
    if (!identical(expr[[i]], quote(expr = ))) {
      out <- c(out, local_names(expr[[i]]))
    }
  }
  unique(out)
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

#' Calls made in a list of parsed expressions, as call graph items
#'
#' Walks each expression and returns a list of items in the order they
#' appear, deduplicated by name. A character item is a locally-defined
#' function (a call `fun()` or a bare reference `fun`). A list item,
#' `list(name, calls)`, is a call to a function exported by a package in
#' `include_ns`; its `calls` are the items found inside its arguments, so
#' nesting follows how the calls are written.
#'
#' @noRd
call_items <- function(exprs, known_names, include_ns = NULL, ext_names = character(0),
                       bound = character(0), ctx = NULL) {
  items <- list()
  for (i in seq_along(exprs)) {
    if (identical(exprs[[i]], quote(expr = ))) {
      next
    }
    items <- c(items, expr_items(exprs[[i]], known_names, include_ns, ext_names, bound, ctx))
  }
  merge_items(items)
}

#' @noRd
expr_items <- function(expr, known_names, include_ns, ext_names, bound, ctx = NULL) {
  if (is.name(expr)) {
    nm <- as.character(expr)
    return(if (nm %in% known_names && !nm %in% bound) list(nm) else list())
  }
  if (!is.call(expr)) {
    return(list())
  }
  if (is_dollar(expr)) {
    return(expr_items(expr[[2]], known_names, include_ns, ext_names, bound, ctx))
  }

  fn <- expr[[1]]
  args <- call_items(as.list(expr)[-1], known_names, include_ns, ext_names, bound, ctx)

  if (is_dollar(fn)) {
    target <- r6_target(fn, ctx)
    if (!is.null(target) && target %in% known_names) {
      return(c(list(target), args))
    }
  }

  if (is.call(fn) && length(fn) == 3 && is.name(fn[[1]]) && as.character(fn[[1]]) %in% c("::", ":::")) {
    if (as.character(fn[[2]]) %in% include_ns) {
      return(list(list(name = as.character(fn[[3]]), calls = args)))
    }
    return(args)
  }
  if (is.name(fn)) {
    nm <- as.character(fn)
    if (nm %in% known_names) {
      return(c(list(nm), args))
    }
    if (nm %in% ext_names) {
      return(list(list(name = nm, calls = args)))
    }
    return(args)
  }
  c(expr_items(fn, known_names, include_ns, ext_names, bound, ctx), args)
}

#' Deduplicate call graph items by name, merging repeated external calls
#'
#' @noRd
merge_items <- function(items) {
  out <- list()
  keys <- character(0)
  for (item in items) {
    key <- if (is.character(item)) paste0("local:", item) else paste0("ext:", item$name)
    i <- match(key, keys)
    if (is.na(i)) {
      out <- c(out, list(item))
      keys <- c(keys, key)
    } else if (!is.character(item)) {
      out[[i]]$calls <- merge_items(c(out[[i]]$calls, item$calls))
    }
  }
  out
}

#' Names exported by each package in `include_ns`
#'
#' Syntax and control flow (`{`, `<-`, `if`, `function`, ...) are left out,
#' so `include_ns = "base"` shows calls such as `options()` but not the
#' structure of the code itself.
#'
#' @noRd
ns_exports <- function(include_ns) {
  out <- character(0)
  for (pkg in include_ns) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Package \"", pkg, "\" in `include_ns` is not installed.", call. = FALSE)
    }
    out <- c(out, getNamespaceExports(pkg))
  }
  out <- out[grepl("^[.a-zA-Z][.a-zA-Z0-9_]*$", out)]
  setdiff(unique(out), control_flow_keywords)
}

#' Depth-first build of a call_stack-shaped tree from a call graph
#'
#' @param node Character scalar; the root function name.
#' @param call_graph Named list where each element holds the items called
#'   by that function: a character vector of local function names, or a
#'   list mixing those names with external `list(name, calls)` items (see
#'   `call_items()`).
#' @param visited Character vector of function names on the path from the
#'   root (used internally to prevent cycles).
#'
#' @noRd
build_tree <- function(node, call_graph, visited = character(0)) {
  visited <- c(visited, node)
  list(name = node, calls = expand_items(call_graph[[node]], call_graph, visited))
}

#' @noRd
expand_items <- function(items, call_graph, visited) {
  out <- list()
  for (item in as.list(items)) {
    if (is.character(item)) {
      if (!item %in% visited) {
        out <- c(out, list(build_tree(item, call_graph, visited)))
      }
    } else {
      out <- c(out, list(list(name = item$name, calls = expand_items(item$calls, call_graph, visited))))
    }
  }
  out
}

#' Validate the arguments shared by trim_tree()
#'
#' @noRd
check_trim_args <- function(exclude, max_depth, keep, prune) {
  stopifnot(
    "`exclude` must be NULL or a character vector" = is.null(exclude) || is.character(exclude),
    "`max_depth` must be a single number of 0 or more" =
      is.numeric(max_depth) && length(max_depth) == 1 && !is.na(max_depth) && max_depth >= 0,
    "`keep` must be NULL or a character vector" = is.null(keep) || is.character(keep),
    "`prune` must be NULL or a character vector" = is.null(prune) || is.character(prune)
  )
}

#' Apply prune, modules_only, exclude, keep, and max_depth to a tree
#'
#' `modules` is `NULL` to skip the modules_only step, or the names of the
#' module functions. The root and its direct children survive that step.
#'
#' @noRd
trim_tree <- function(tree, modules, exclude, max_depth, keep, prune) {
  calls <- drop_subtrees(tree$calls, prune)
  if (!is.null(modules)) {
    calls <- lapply(calls, function(child) {
      list(name = child$name, calls = prune_children(child$calls, modules))
    })
  }
  calls <- splice_out(calls, exclude)
  if (!is.null(keep)) {
    calls <- keep_matching(calls, keep)
  }
  tree$calls <- truncate_depth(calls, max_depth)
  tree
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

#' Drop call_stack nodes named in `exclude`, splicing their children up
#'
#' The inverse of `prune_children()`: a node named in `exclude` is removed
#' and its (already processed) children take its place in the parent.
#'
#' @noRd
splice_out <- function(calls, exclude) {
  out <- list()
  for (child in calls) {
    grandchildren <- splice_out(child$calls, exclude)
    if (child$name %in% exclude) {
      out <- c(out, grandchildren)
    } else {
      out <- c(out, list(list(name = child$name, calls = grandchildren)))
    }
  }
  out
}

#' Drop call_stack nodes named in `prune` along with their subtrees
#'
#' @noRd
drop_subtrees <- function(calls, prune) {
  out <- list()
  for (child in calls) {
    if (!child$name %in% prune) {
      out <- c(out, list(list(name = child$name, calls = drop_subtrees(child$calls, prune))))
    }
  }
  out
}

#' Keep nodes matching any `keep` pattern, plus the paths leading to them
#'
#' A matching node keeps its whole subtree. A non-matching node is kept
#' only when something below it matches, and then only with those branches.
#'
#' @noRd
keep_matching <- function(calls, keep) {
  out <- list()
  for (child in calls) {
    if (any(vapply(keep, grepl, logical(1), x = child$name))) {
      out <- c(out, list(child))
    } else {
      sub <- keep_matching(child$calls, keep)
      if (length(sub) > 0) {
        out <- c(out, list(list(name = child$name, calls = sub)))
      }
    }
  }
  out
}

#' Cut a list of call_stack nodes off below `max_depth` levels
#'
#' @noRd
truncate_depth <- function(calls, max_depth) {
  if (max_depth < 1) {
    return(list())
  }
  lapply(calls, function(child) {
    list(name = child$name, calls = truncate_depth(child$calls, max_depth - 1))
  })
}

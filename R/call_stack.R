#' Build the call tree of a function
#'
#' @description
#' `call_stack()` takes the name of a function, optionally namespaced
#' (e.g. `"dplyr::select"`), statically parses its body, and recursively
#' resolves every function it calls, building a tree of those calls, the
#' calls those functions make, and so on.
#'
#' Resolution is static (read from the function's source code), not a
#' runtime trace: the function is never called. `UseMethod()` dispatch is
#' resolved by looking up the generic's registered S3 methods and
#' following each one. Other dynamic calls (`NextMethod()`, S4 and R6
#' dispatch, non-standard evaluation) show as leaves rather than being
#' followed further.
#'
#' @param fn Character string naming a function, e.g. `"dplyr::select"`,
#'   `"pkg:::internal_fun"`, or `"mean"`.
#' @param max_depth Maximum recursion depth. Default `Inf`, which follows
#'   every call down to a primitive or a cycle already visited.
#'
#' @return An object of class `call_stack`: a named list with `name` (the
#'   function name) and `calls` (a list of child nodes with the same shape).
#'
#' @seealso [print.call_stack()] for how the tree is drawn.
#'
#' @examples
#' call_stack("mean.default", max_depth = 1)
#'
#' # a generic: UseMethod() is replaced by the methods it dispatches to
#' call_stack("mean", max_depth = 1)
#'
#' @export
call_stack <- function(fn, max_depth = Inf) {
  stopifnot(
    "`fn` must be a single character string" = is.character(fn) && length(fn) == 1
  )

  root <- resolve_fn(fn)
  visited <- new.env(parent = emptyenv())

  node <- build_node(root$name, root$fun, depth = 1L, max_depth = max_depth, visited = visited)
  class(node) <- "call_stack"
  node
}

#' Resolve a "pkg::fun" / "pkg:::fun" / "fun" string to a function
#'
#' `fn` is user-supplied text naming a package and function that may not
#' exist, so lookup failures here are expected usage errors, not bugs.
#' They're caught and re-raised with a message naming the string that
#' failed and the underlying reason, instead of leaking a raw `get()` or
#' `asNamespace()` error.
#'
#' @noRd
resolve_fn <- function(fn) {
  parsed <- parse_fn_string(fn)

  f <- tryCatch(
    if (parsed$mode == "internal") {
      get(parsed$name, envir = asNamespace(parsed$pkg), mode = "function")
    } else if (parsed$mode == "exported") {
      getExportedValue(parsed$pkg, parsed$name)
    } else {
      get(parsed$name, mode = "function")
    },
    error = function(e) {
      stop(
        "Could not resolve `fn = \"", fn, "\"`: ", conditionMessage(e),
        call. = FALSE
      )
    }
  )

  stopifnot("`fn` must resolve to a function" = is.function(f))
  list(name = parsed$name, fun = f)
}

#' Split a "pkg::fun" / "pkg:::fun" / "fun" string into its parts
#'
#' @noRd
parse_fn_string <- function(fn) {
  if (grepl(":::", fn, fixed = TRUE)) {
    parts <- strsplit(fn, ":::", fixed = TRUE)[[1]]
    list(mode = "internal", pkg = parts[1], name = parts[2])
  } else if (grepl("::", fn, fixed = TRUE)) {
    parts <- strsplit(fn, "::", fixed = TRUE)[[1]]
    list(mode = "exported", pkg = parts[1], name = parts[2])
  } else {
    list(mode = "bare", pkg = NA_character_, name = fn)
  }
}

#' Recursively build one node of the call tree
#'
#' @noRd
build_node <- function(name, fun, depth, max_depth, visited) {
  node <- list(name = name, calls = list())
  key <- fn_key(name, fun)

  if (depth > max_depth || is.primitive(fun) || exists(key, envir = visited, inherits = FALSE)) {
    return(node)
  }
  assign(key, TRUE, envir = visited)

  called_names <- find_called_names(fun)
  generic <- find_use_method_generic(fun, name)

  method_nodes <- list()
  if (!is.na(generic)) {
    called_names <- setdiff(called_names, "UseMethod")
    method_nodes <- lapply(resolve_s3_methods(generic, fun), function(m) {
      if (is.null(m$fun)) {
        list(name = m$name, calls = list())
      } else {
        build_node(m$name, m$fun, depth + 1L, max_depth, visited)
      }
    })
  }

  call_nodes <- lapply(called_names, function(nm) {
    child_fun <- tryCatch(
      get(nm, envir = environment(fun), mode = "function"),
      error = function(e) NULL
    )
    if (is.null(child_fun)) {
      list(name = nm, calls = list())
    } else {
      build_node(nm, child_fun, depth + 1L, max_depth, visited)
    }
  })

  node$calls <- c(method_nodes, call_nodes)
  node
}

#' Generic name dispatched by a UseMethod() call in a function's body
#'
#' Returns `NA_character_` when the body contains no `UseMethod()` call.
#' Falls back to `name` when `UseMethod()` is called with no arguments,
#' matching R's own behavior of dispatching on the calling function's name.
#'
#' @noRd
find_use_method_generic <- function(fun, name) {
  generic <- NULL

  walk <- function(expr) {
    if (!is.null(generic) || !is.call(expr)) {
      return(invisible())
    }
    if (identical(expr[[1L]], quote(UseMethod))) {
      generic <<- if (length(expr) >= 2L && is.character(expr[[2L]])) expr[[2L]] else name
      return(invisible())
    }
    for (part in as.list(expr)[-1L]) {
      if (missing(part)) {
        next
      }
      walk(part)
    }
  }

  walk(body(fun))
  if (is.null(generic)) NA_character_ else generic
}

#' Resolve the S3 methods registered for a generic
#'
#' @param generic Character. The generic's name.
#' @param fun The generic function itself, used to locate its namespace so
#'   methods can be found even when that namespace isn't attached.
#'
#' @return A list of `list(name, fun)` pairs; `fun` is `NULL` when a method
#'   could not be resolved.
#'
#' @noRd
resolve_s3_methods <- function(generic, fun) {
  method_names <- as.character(tryCatch(
    suppressWarnings(utils::.S3methods(generic, envir = environment(fun))),
    error = function(e) character(0)
  ))

  lapply(method_names, function(m) {
    cls <- sub(paste0("^", generic, "\\."), "", m)
    method_fun <- tryCatch(
      utils::getS3method(generic, cls, optional = TRUE, envir = environment(fun)),
      error = function(e) NULL
    )
    list(name = m, fun = method_fun)
  })
}

#' Reserved control-flow keywords to exclude from call trees
#'
#' @noRd
control_flow_keywords <- c(
  "if", "for", "while", "repeat", "function", "break", "next"
)

#' Function names called directly in a function's body
#'
#' Excludes R's syntactic/operator tokens (`{`, `<-`, `+`, ...) and
#' control-flow keywords (`if`, `for`, ...), which
#' `codetools::findGlobals()` reports alongside real function calls.
#'
#' @noRd
find_called_names <- function(fun) {
  if (!is.function(fun) || is.primitive(fun)) {
    return(character(0))
  }
  called <- codetools::findGlobals(fun, merge = FALSE)$functions
  called <- called[grepl("^[.a-zA-Z][.a-zA-Z0-9_]*$", called)]
  setdiff(called, control_flow_keywords)
}

#' Unique key identifying a function for cycle detection
#'
#' @noRd
fn_key <- function(name, fun) {
  paste0(format(environment(fun)), "::", name)
}

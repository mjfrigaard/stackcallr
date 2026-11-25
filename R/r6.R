#' Extract an R6 class definition from a parsed expression
#'
#' Checks whether `expr` is a top-level `Name <- R6Class(...)` (or
#' `R6::R6Class(...)`) assignment. Returns the class name, the name of the
#' class it inherits from (or `NULL`), and its methods: every function in
#' `public`, `private`, and `active`, keyed by method name. `public`
#' records which of those are public.
#'
#' @noRd
extract_r6_def <- function(expr) {
  if (!is.call(expr) || !is.name(expr[[1]]) || length(expr) != 3 ||
      !as.character(expr[[1]]) %in% c("<-", "=") || !is.name(expr[[2]])) {
    return(NULL)
  }
  val <- expr[[3]]
  if (!is_r6class_call(val)) {
    return(NULL)
  }

  args <- as.list(val)[-1]
  methods <- list()
  public <- character(0)
  for (part in c("public", "private", "active")) {
    lst <- args[[part]]
    if (!is.call(lst) || !identical(lst[[1]], as.name("list"))) {
      next
    }
    items <- as.list(lst)[-1]
    for (m in names(items)) {
      fn <- items[[m]]
      if (nzchar(m) && is.call(fn) && identical(fn[[1]], as.name("function"))) {
        methods[[m]] <- fn
        if (part == "public") public <- c(public, m)
      }
    }
  }

  inherit <- args[["inherit"]]
  list(
    name = as.character(expr[[2]]),
    inherit = if (is.name(inherit)) as.character(inherit),
    methods = methods,
    public = public
  )
}

#' @noRd
is_r6class_call <- function(x) {
  if (!is.call(x)) {
    return(FALSE)
  }
  fn <- x[[1]]
  identical(fn, as.name("R6Class")) ||
    (is.call(fn) && identical(fn[[1]], as.name("::")) && identical(fn[[3]], as.name("R6Class")))
}

#' Call graph nodes for R6 classes
#'
#' Each method becomes a function definition named `Class$method`.
#' `initialize` is named `Class$new`, since that's how it is called. A class
#' without `initialize` still gets a `Class$new` node: empty, or calling the
#' parent's `$new` when it inherits.
#'
#' @noRd
r6_method_defs <- function(classes) {
  defs <- list()
  for (cls in classes) {
    for (m in names(cls$methods)) {
      node <- if (m == "initialize") "new" else m
      defs[[paste0(cls$name, "$", node)]] <- cls$methods[[m]]
    }
    new_node <- paste0(cls$name, "$new")
    if (is.null(defs[[new_node]])) {
      defs[[new_node]] <- if (!is.null(cls$inherit) && cls$inherit %in% names(classes)) {
        call("function", NULL, as.call(list(call("$", as.name(cls$inherit), as.name("new")))))
      } else {
        quote(function() NULL)
      }
    }
  }
  defs
}

#' The class a method node belongs to, or NULL for a plain function
#'
#' @noRd
r6_owner <- function(node, classes) {
  cls <- sub("\\$.*$", "", node)
  if (grepl("$", node, fixed = TRUE) && cls %in% names(classes)) cls
}

#' Names in `expr` assigned an instance of a known class
#'
#' `x <- Class$new(...)`, including when the `$new()` call is nested in the
#' right-hand side (`x <- tryCatch(Class$new(), ...)`), maps `x` to `Class`.
#'
#' @noRd
r6_instances <- function(expr, classes) {
  out <- character(0)
  if (!is.call(expr)) {
    return(out)
  }
  if (is.name(expr[[1]]) && as.character(expr[[1]]) %in% c("<-", "=") &&
      length(expr) == 3 && is.name(expr[[2]])) {
    cls <- r6_new_class(expr[[3]], classes)
    if (!is.null(cls)) {
      out[[as.character(expr[[2]])]] <- cls
    }
  }
  for (i in seq_along(expr)) {
    if (!identical(expr[[i]], quote(expr = ))) {
      out <- c(out, r6_instances(expr[[i]], classes))
    }
  }
  out
}

#' @noRd
r6_new_class <- function(expr, classes) {
  if (!is.call(expr)) {
    return(NULL)
  }
  fn <- expr[[1]]
  if (is_dollar(fn) && is.name(fn[[2]]) && identical(fn[[3]], as.name("new")) &&
      as.character(fn[[2]]) %in% names(classes)) {
    return(as.character(fn[[2]]))
  }
  for (i in seq_along(expr)) {
    if (!identical(expr[[i]], quote(expr = ))) {
      cls <- r6_new_class(expr[[i]], classes)
      if (!is.null(cls)) return(cls)
    }
  }
  NULL
}

#' @noRd
is_dollar <- function(x) {
  is.call(x) && length(x) == 3 && is.name(x[[1]]) && as.character(x[[1]]) %in% c("$", "@")
}

#' Resolve a `lhs$method` call head to a method node, or NULL
#'
#' `ctx` holds `classes`, `self` (the class of the method being walked, or
#' NULL), and `vars` (instance variables, from `r6_instances()`).
#'
#' @noRd
r6_target <- function(fn, ctx) {
  if (is.null(ctx) || !is.name(fn[[2]]) || !is.name(fn[[3]])) {
    return(NULL)
  }
  lhs <- as.character(fn[[2]])
  m <- as.character(fn[[3]])
  classes <- ctx$classes

  if (lhs %in% names(classes) && m == "new") {
    return(paste0(lhs, "$new"))
  }
  start <- if (lhs %in% c("self", "private")) {
    ctx$self
  } else if (lhs == "super" && !is.null(ctx$self)) {
    classes[[ctx$self]]$inherit
  } else if (lhs %in% names(ctx$vars)) {
    ctx$vars[[lhs]]
  }

  cls <- start
  while (!is.null(cls) && cls %in% names(classes)) {
    if (m %in% names(classes[[cls]]$methods) && m != "initialize") {
      return(paste0(cls, "$", m))
    }
    cls <- classes[[cls]]$inherit
  }
  NULL
}

#' Method nodes that count as modules for `modules_only`
#'
#' A class is a module when any of its methods uses `NS()` or
#' `moduleServer()`; its `$new` and public methods are then modules.
#'
#' @noRd
r6_module_nodes <- function(classes) {
  out <- character(0)
  for (cls in classes) {
    if (any(vapply(cls$methods, uses_ns, logical(1)))) {
      out <- c(out, paste0(cls$name, "$", c("new", setdiff(cls$public, "initialize"))))
    }
  }
  out
}

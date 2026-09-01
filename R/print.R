#' Print a call_stack tree
#'
#' @description
#' Draws a `call_stack` tree in the style of `lobstr::ast()`. A node with
#' children is prefixed with a solid block (`\u2588\u2500`) and a leaf is
#' shown as plain text; children are connected with `\u251c\u2500` and
#' `\u2514\u2500` branches, one level of indent per level of the tree.
#'
#' @param x A `call_stack` object, as returned by [call_stack()].
#' @param ... Unused, present for compatibility with the `print()` generic.
#'
#' @return `x`, invisibly. Called for its side effect of printing the tree.
#'
#' @examples
#' print(call_stack("mean.default", max_depth = 1))
#'
#' @export
print.call_stack <- function(x, ...) {
  cat(node_label(x), "\n", sep = "")
  print_children(x$calls, prefix = "")
  invisible(x)
}

#' @noRd
node_label <- function(node) {
  if (length(node$calls) > 0) {
    paste0("\u2588\u2500", node$name)
  } else {
    node$name
  }
}

#' @noRd
print_children <- function(calls, prefix) {
  n <- length(calls)
  for (i in seq_along(calls)) {
    last <- i == n
    branch <- if (last) "\u2514\u2500" else "\u251C\u2500"
    cat(prefix, branch, node_label(calls[[i]]), "\n", sep = "")
    child_prefix <- paste0(prefix, if (last) "  " else "\u2502 ")
    print_children(calls[[i]]$calls, child_prefix)
  }
}

test_that("resolves pkg::fun and returns a call_stack", {
  result <- call_stack("stats::sd", max_depth = 1)

  expect_s3_class(result, "call_stack")
  expect_identical(result$name, "sd")
  expect_true(is.list(result$calls))
})

test_that("finds direct calls in a simple function body", {
  result <- call_stack("stats::sd", max_depth = 1)
  names <- vapply(result$calls, function(x) x$name, character(1))

  expect_true(all(c("as.double", "is.factor", "is.vector", "sqrt", "var") %in% names))
})

test_that("excludes syntax tokens and control-flow keywords", {
  result <- call_stack("stats::sd", max_depth = 1)
  names <- vapply(result$calls, function(x) x$name, character(1))

  expect_false(any(c("{", "if", "for", "<-", "+") %in% names))
})

test_that("max_depth limits recursion", {
  shallow <- call_stack("stats::sd", max_depth = 1)
  expect_true(all(vapply(shallow$calls, function(x) length(x$calls) == 0, logical(1))))
})

test_that("resolves plain function names without a package prefix", {
  result <- call_stack("mean.default", max_depth = 1)
  expect_identical(result$name, "mean.default")
})

test_that("errors on non-character or multi-element input", {
  expect_error(call_stack(mean), "single character string")
  expect_error(call_stack(c("mean", "sd")), "single character string")
})

test_that("errors when fn does not resolve to a function", {
  expect_error(call_stack("stats::not_a_real_function"), "Could not resolve")
})

test_that("errors when fn names a package that isn't installed", {
  expect_error(call_stack("notarealpkg123::fun"), "Could not resolve")
})

test_that("resolves UseMethod dispatch into registered methods", {
  result <- call_stack("mean", max_depth = 1)
  names <- vapply(result$calls, function(x) x$name, character(1))

  expect_true("mean.default" %in% names)
  expect_false("UseMethod" %in% names)
})

test_that("find_use_method_generic extracts an explicit generic name", {
  f <- function(x) UseMethod("othergeneric")
  expect_identical(find_use_method_generic(f, "myfun"), "othergeneric")
})

test_that("find_use_method_generic falls back to the function name with no arg", {
  f <- function(x) UseMethod()
  expect_identical(find_use_method_generic(f, "myfun"), "myfun")
})

test_that("find_use_method_generic returns NA when there is no UseMethod call", {
  f <- function(x) x + 1
  expect_true(is.na(find_use_method_generic(f, "myfun")))
})

test_that("find_use_method_generic handles calls with missing arguments", {
  f <- function(x) {
    y <- x[, 1]
    UseMethod("g")
  }
  expect_identical(find_use_method_generic(f, "myfun"), "g")
})

test_that("cycles do not cause infinite recursion", {
  f <- function() g()
  g <- function() f()
  environment(f) <- environment()
  environment(g) <- environment()

  fn_env <- new.env()
  assign("f", f, envir = fn_env)
  assign("g", g, envir = fn_env)
  environment(fn_env$f) <- fn_env
  environment(fn_env$g) <- fn_env

  root <- build_node("f", fn_env$f, depth = 1L, max_depth = Inf, visited = new.env())
  expect_identical(root$name, "f")
})

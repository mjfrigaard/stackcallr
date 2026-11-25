r6_files <- function(dir) {
  write_r_files(dir, list(
    "ModInputs.R" = c(
      "ModInputs <- R6::R6Class('ModInputs',",
      "  public = list(",
      "    initialize = function(id) { private$id <- id; private$ns <- shiny::NS(id) },",
      "    ui = function() private$picker(),",
      "    server = function() shiny::moduleServer(private$id, function(input, output, session) helper())",
      "  ),",
      "  private = list(id = NULL, ns = NULL, picker = function() util_picker())",
      ")"
    ),
    "Plain.R" = "Plain <- R6Class('Plain', public = list(go = function() helper()))",
    "Child.R" = "Child <- R6::R6Class('Child', inherit = Plain, public = list(run = function() { self$go(); super$go() }))",
    "app.R" = c(
      "app_ui <- function() { inputs <- ModInputs$new(id = 'inputs'); inputs$ui() }",
      "app_server <- function() { inputs <- ModInputs$new(id = 'inputs'); inputs$server(); Plain$new() }",
      "use_child <- function() { kid <- tryCatch(Child$new(), error = function(e) NULL); kid$run() }",
      "launch <- function() { app_ui(); app_server() }",
      "helper <- function() 1",
      "util_picker <- function() 1"
    )
  ))
}

test_that("R6 methods are nodes reached through Class$new() and instance variables", {
  dir <- withr::local_tempdir()
  r6_files(dir)

  tree <- call_tree_dir(dir, root = "app_ui")
  expect_equal(child_names(tree), c("ModInputs$new", "ModInputs$ui"))
  expect_equal(child_names(tree$calls[[2]]), "ModInputs$picker")
  expect_equal(child_names(tree$calls[[2]]$calls[[1]]), "util_picker")

  tree <- call_tree_dir(dir, root = "app_server")
  expect_equal(child_names(tree), c("ModInputs$new", "ModInputs$server", "Plain$new"))
  expect_equal(child_names(tree$calls[[2]]), "helper")
})

test_that("R6 methods can be roots, and self and super follow inheritance", {
  dir <- withr::local_tempdir()
  r6_files(dir)

  expect_equal(child_names(call_tree_dir(dir, root = "ModInputs$server")), "helper")
  tree <- call_tree_dir(dir, root = "use_child")
  expect_equal(child_names(tree), c("Child$new", "Child$run"))
  expect_equal(child_names(tree$calls[[2]]), "Plain$go")
})

test_that("$new on a class without initialize calls the parent's $new", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "Base <- R6::R6Class('Base', public = list(initialize = function() setup()))",
    "Kid <- R6::R6Class('Kid', inherit = Base, public = list(go = function() 1))",
    "make <- function() Kid$new()",
    "setup <- function() 1"
  )))

  tree <- call_tree_dir(dir, root = "make")
  expect_equal(child_names(tree), "Kid$new")
  expect_equal(child_names(tree$calls[[1]]), "Base$new")
  expect_equal(child_names(tree$calls[[1]]$calls[[1]]), "setup")
})

test_that("modules_only keeps every method of a class that uses NS() or moduleServer()", {
  dir <- withr::local_tempdir()
  r6_files(dir)

  tree <- call_tree_dir(dir, root = "launch", modules_only = TRUE)
  expect_equal(child_names(tree), c("app_ui", "app_server"))
  expect_equal(child_names(tree$calls[[1]]), c("ModInputs$new", "ModInputs$ui"))
  expect_equal(child_names(tree$calls[[2]]), c("ModInputs$new", "ModInputs$server"))
})

test_that("the name after $ is not a call to a function with that name", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "f <- function(obj) { obj$g(); obj$g; x@g }",
    "g <- function() 1"
  )))
  expect_length(call_tree_dir(dir, root = "f")$calls, 0)
})

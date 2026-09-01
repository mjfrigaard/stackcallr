write_r_files <- function(dir, files) {
  for (nm in names(files)) {
    writeLines(files[[nm]], file.path(dir, nm))
  }
}

test_that("extract_func_def extracts <- and = assignments", {
  expect_equal(extract_func_def(parse(text = "f <- function(x) x")[[1]])$name, "f")
  expect_equal(extract_func_def(parse(text = "f = function(x) x")[[1]])$name, "f")
  expect_equal(extract_func_def(parse(text = 'assign("f", function(x) x)')[[1]])$name, "f")
})

test_that("extract_func_def returns NULL for non-function code", {
  expect_null(extract_func_def(parse(text = "x <- 5")[[1]]))
  expect_null(extract_func_def(parse(text = "print('hi')")[[1]]))
})

test_that("find_calls finds direct calls and bare references", {
  expr <- parse(text = "function() { foo(); bar }")[[1]]
  expect_setequal(find_calls(expr, c("foo", "bar", "baz")), c("foo", "bar"))
})

test_that("find_calls ignores unknown names and dedupes", {
  expr <- parse(text = "function() { foo(); foo(); unknown() }")[[1]]
  expect_equal(find_calls(expr, c("foo")), "foo")
})

test_that("find_calls finds calls nested inside control flow", {
  expr <- parse(text = "function() { if (TRUE) tryCatch(foo(), error = function(e) bar()) }")[[1]]
  expect_setequal(find_calls(expr, c("foo", "bar")), c("foo", "bar"))
})

test_that("uses_ns detects NS() and moduleServer(), bare and namespaced", {
  expect_true(uses_ns(parse(text = "function(id) NS(id)")[[1]]))
  expect_true(uses_ns(parse(text = "function(id) shiny::NS(id)")[[1]]))
  expect_true(uses_ns(parse(text = "function(id) moduleServer(id, function(i, o, s) {})")[[1]]))
  expect_false(uses_ns(parse(text = "function(x) x + 1")[[1]]))
})

test_that("build_tree builds a simple tree and handles cycles", {
  cg <- list(root = c("a", "b"), a = character(0), b = character(0))
  tree <- build_tree("root", cg)
  expect_equal(tree$name, "root")
  expect_length(tree$calls, 2)

  cyclic <- build_tree("a", list(a = "b", b = "a"))
  expect_equal(cyclic$name, "a")
  expect_length(cyclic$calls, 1)
  expect_length(cyclic$calls[[1]]$calls, 0)
})

test_that("build_tree on an unknown root produces a childless node", {
  tree <- build_tree("missing", list(a = "b", b = character(0)))
  expect_equal(tree$name, "missing")
  expect_length(tree$calls, 0)
})

test_that("call_tree_dir builds the full call tree from a directory", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list(
    "launch.R"     = 'launch <- function() { shinyApp(ui = app_ui(), server = app_server) }',
    "app_ui.R"     = 'app_ui <- function() { mod_a_ui("a") }',
    "app_server.R" = 'app_server <- function(input, output, session) { mod_a_server("a") }',
    "mod_a.R"      = 'mod_a_ui <- function(id) { ns <- NS(id) }',
    "mod_a_srv.R"  = 'mod_a_server <- function(id) { moduleServer(id, function(i, o, s) {}) }'
  ))

  tree <- call_tree_dir(dir, root = "launch")

  expect_s3_class(tree, "call_stack")
  expect_equal(tree$name, "launch")
  names <- vapply(tree$calls, function(x) x$name, character(1))
  expect_setequal(names, c("app_ui", "app_server"))
})

test_that("call_tree_dir modules_only prunes non-module wrappers and splices through", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list(
    "launch.R"     = 'launch <- function() { shinyApp(ui = app_ui(), server = app_server) }',
    "app_ui.R"     = 'app_ui <- function() { mod_a_ui("a") }',
    "app_server.R" = 'app_server <- function(input, output, session) { mod_a_server("a") }',
    "mod_a.R"      = 'mod_a_ui <- function(id) { ns <- NS(id) }',
    "mod_a_srv.R"  = 'mod_a_server <- function(id) { moduleServer(id, function(i, o, s) { helper() }) }',
    "helper.R"     = 'helper <- function() 1'
  ))

  tree <- call_tree_dir(dir, root = "launch", modules_only = TRUE)

  names <- vapply(tree$calls, function(x) x$name, character(1))
  expect_setequal(names, c("mod_a_ui", "mod_a_server"))
  expect_false("helper" %in% unlist(lapply(tree$calls, function(x) vapply(x$calls, `[[`, character(1), "name"))))
})

test_that("call_tree_dir errors when root isn't found", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = "f <- function() 1"))
  expect_error(call_tree_dir(dir, root = "missing"), "Could not find")
})

test_that("call_tree_dir errors on non-character path or root", {
  expect_error(call_tree_dir(1, root = "f"), "single character string")
  expect_error(call_tree_dir("R", root = 1), "single character string")
})

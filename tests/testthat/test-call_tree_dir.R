write_r_files <- function(dir, files) {
  for (nm in names(files)) {
    writeLines(files[[nm]], file.path(dir, nm))
  }
}

all_names <- function(node) c(node$name, unlist(lapply(node$calls, all_names)))

child_names <- function(node) vapply(node$calls, `[[`, character(1), "name")

test_that("extract_func_def extracts <- and = assignments", {
  expect_equal(extract_func_def(parse(text = "f <- function(x) x")[[1]])$name, "f")
  expect_equal(extract_func_def(parse(text = "f = function(x) x")[[1]])$name, "f")
  expect_equal(extract_func_def(parse(text = 'assign("f", function(x) x)')[[1]])$name, "f")
})

test_that("extract_func_def returns NULL for non-function code", {
  expect_null(extract_func_def(parse(text = "x <- 5")[[1]]))
  expect_null(extract_func_def(parse(text = "print('hi')")[[1]]))
  expect_null(extract_func_def(parse(text = "utils::globalVariables(c('a', 'b'))")[[1]]))
  expect_null(extract_func_def(parse(text = "x <- utils::head(1:3)")[[1]]))
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

test_that("call_tree_dir modules_only keeps root's children and splices deeper wrappers", {
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

  expect_equal(vapply(tree$calls, `[[`, character(1), "name"), c("app_ui", "app_server"))
  expect_equal(tree$calls[[1]]$calls[[1]]$name, "mod_a_ui")
  expect_equal(tree$calls[[2]]$calls[[1]]$name, "mod_a_server")
  expect_length(tree$calls[[2]]$calls[[1]]$calls, 0)
})

test_that("call_tree_dir modules_only splices non-module wrappers below root's children", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list(
    "launch.R" = "launch <- function() app_ui()",
    "app_ui.R" = "app_ui <- function() tabs_ui()",
    "tabs.R"   = 'tabs_ui <- function() { mod_a_ui("a"); helper() }',
    "mod_a.R"  = "mod_a_ui <- function(id) NS(id)",
    "helper.R" = "helper <- function() 1"
  ))

  tree <- call_tree_dir(dir, root = "launch", modules_only = TRUE)

  expect_equal(all_names(tree), c("launch", "app_ui", "mod_a_ui"))
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

test_that("splice_out drops named nodes and promotes their children", {
  calls <- list(
    list(name = "a", calls = list(list(name = "log", calls = list()))),
    list(name = "log", calls = list(list(name = "b", calls = list())))
  )
  out <- splice_out(calls, "log")
  expect_equal(vapply(out, `[[`, character(1), "name"), c("a", "b"))
  expect_length(out[[1]]$calls, 0)
})

test_that("call_tree_dir exclude removes noise functions at every level", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list(
    "launch.R" = 'launch <- function() { logr_msg("start"); app_ui() }',
    "app_ui.R" = 'app_ui <- function() { logr_msg("ui"); mod_a_ui("a") }',
    "mod_a.R"  = 'mod_a_ui <- function(id) { logr_msg("mod"); NS(id) }',
    "logr.R"   = 'logr_msg <- function(x) message(x)'
  ))

  tree <- call_tree_dir(dir, root = "launch", exclude = "logr_msg")

  expect_false("logr_msg" %in% all_names(tree))
  expect_equal(all_names(tree), c("launch", "app_ui", "mod_a_ui"))
})

test_that("call_tree_dir exclude composes with modules_only and ignores root", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list(
    "launch.R" = 'launch <- function() { app_ui() }',
    "app_ui.R" = 'app_ui <- function() { mod_a_ui("a"); mod_b_ui("b") }',
    "mod_a.R"  = 'mod_a_ui <- function(id) NS(id)',
    "mod_b.R"  = 'mod_b_ui <- function(id) NS(id)'
  ))

  tree <- call_tree_dir(dir, root = "launch", modules_only = TRUE, exclude = c("launch", "mod_b_ui"))

  expect_equal(all_names(tree), c("launch", "app_ui", "mod_a_ui"))
})

test_that("call_tree_dir errors on non-character exclude", {
  expect_error(call_tree_dir("R", root = "f", exclude = 1), "`exclude`")
})

test_that("call_tree_dir max_depth limits the levels below root", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "a <- function() b()",
    "b <- function() c()",
    "c <- function() d()",
    "d <- function() 1"
  )))

  expect_equal(all_names(call_tree_dir(dir, root = "a", max_depth = 1)), c("a", "b"))
  expect_equal(all_names(call_tree_dir(dir, root = "a", max_depth = 2)), c("a", "b", "c"))
  expect_equal(all_names(call_tree_dir(dir, root = "a", max_depth = 0)), "a")
  expect_equal(all_names(call_tree_dir(dir, root = "a")), c("a", "b", "c", "d"))
})

test_that("call_tree_dir max_depth counts levels after exclude", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "a <- function() log_it()",
    "log_it <- function() b()",
    "b <- function() c()",
    "c <- function() 1"
  )))

  tree <- call_tree_dir(dir, root = "a", exclude = "log_it", max_depth = 1)
  expect_equal(all_names(tree), c("a", "b"))
})

test_that("call_tree_dir errors on a bad max_depth", {
  expect_error(call_tree_dir("R", root = "f", max_depth = -1), "`max_depth`")
  expect_error(call_tree_dir("R", root = "f", max_depth = "1"), "`max_depth`")
  expect_error(call_tree_dir("R", root = "f", max_depth = c(1, 2)), "`max_depth`")
})

test_that("call_tree_dir keep trims the tree to matching subtrees", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "nav_ui <- function() { tab_ui(); mod_compare_ui() }",
    "tab_ui <- function() { mod_counts_a_ui(); mod_dist_ui() }",
    "mod_counts_a_ui <- function() helper()",
    "mod_compare_ui <- function() 1",
    "mod_dist_ui <- function() 1",
    "helper <- function() 1"
  )))

  tree <- call_tree_dir(dir, root = "nav_ui", keep = "^mod_counts_")

  expect_equal(all_names(tree), c("nav_ui", "tab_ui", "mod_counts_a_ui", "helper"))
})

test_that("call_tree_dir keep accepts several patterns and can match nothing", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "root <- function() { a(); b(); c() }",
    "a <- function() 1",
    "b <- function() 1",
    "c <- function() 1"
  )))

  expect_equal(child_names(call_tree_dir(dir, root = "root", keep = c("^a$", "^c$"))), c("a", "c"))
  expect_length(call_tree_dir(dir, root = "root", keep = "^zzz")$calls, 0)
  expect_error(call_tree_dir(dir, root = "root", keep = 1), "`keep`")
})

test_that("call_tree_dir prune drops a node and its whole subtree", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "nav_server <- function() { mod_point_server(); mod_tbl_server() }",
    "mod_point_server <- function() 1",
    "mod_tbl_server <- function() create_awards()",
    "create_awards <- function() 1"
  )))

  pruned <- call_tree_dir(dir, root = "nav_server", prune = "mod_tbl_server")
  excluded <- call_tree_dir(dir, root = "nav_server", exclude = "mod_tbl_server")

  expect_equal(all_names(pruned), c("nav_server", "mod_point_server"))
  expect_equal(all_names(excluded), c("nav_server", "mod_point_server", "create_awards"))
  expect_equal(all_names(call_tree_dir(dir, root = "nav_server", prune = "nav_server")),
               all_names(call_tree_dir(dir, root = "nav_server")))
  expect_error(call_tree_dir(dir, root = "nav_server", prune = 1), "`prune`")
})

test_that("call_tree_dir include_ns shows external calls nested as written", {
  skip_if_not_installed("shiny")
  dir <- withr::local_tempdir()
  write_r_files(dir, list(
    "launch.R" = "launch_app <- function() shinyApp(ui = app_ui, server = app_server)",
    "app_ui.R" = "app_ui <- function() shiny::fluidPage(shiny::sidebarLayout(shiny::sidebarPanel(), shiny::mainPanel()))",
    "app_server.R" = "app_server <- function(input, output, session) helper()",
    "helper.R" = "helper <- function() 1"
  ))

  plain <- call_tree_dir(dir, root = "launch_app")
  expect_equal(child_names(plain), c("app_ui", "app_server"))

  tree <- call_tree_dir(dir, root = "launch_app", include_ns = "shiny")
  expect_equal(child_names(tree), "shinyApp")
  shiny_app <- tree$calls[[1]]
  expect_equal(child_names(shiny_app), c("app_ui", "app_server"))
  expect_equal(
    all_names(shiny_app$calls[[1]]),
    c("app_ui", "fluidPage", "sidebarLayout", "sidebarPanel", "mainPanel")
  )
  expect_equal(all_names(shiny_app$calls[[2]]), c("app_server", "helper"))
})

test_that("call_tree_dir include_ns merges repeated external calls", {
  skip_if_not_installed("shiny")
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "ui <- function() { shiny::tagList(a()); shiny::tagList(b()) }",
    "a <- function() 1",
    "b <- function() 1"
  )))

  tree <- call_tree_dir(dir, root = "ui", include_ns = "shiny")
  expect_equal(child_names(tree), "tagList")
  expect_equal(child_names(tree$calls[[1]]), c("a", "b"))
})

test_that("call_tree_dir include_ns ignores packages not listed and errors on missing ones", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = "f <- function() { utils::head(g()); stats::sd(1) }\ng <- function() 1"))

  tree <- call_tree_dir(dir, root = "f", include_ns = "utils")
  expect_equal(child_names(tree), "head")
  expect_equal(child_names(tree$calls[[1]]), "g")
  expect_error(call_tree_dir(dir, root = "f", include_ns = "notapkgzzz"), "not installed")
  expect_error(call_tree_dir(dir, root = "f", include_ns = 1), "`include_ns`")
})

test_that("call_tree_dir include_ns external nodes work with exclude and prune", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = "f <- function() { utils::head(g()); utils::tail(h()) }\ng <- function() 1\nh <- function() 1"))

  expect_equal(all_names(call_tree_dir(dir, root = "f", include_ns = "utils", exclude = "head")),
               c("f", "g", "tail", "h"))
  expect_equal(all_names(call_tree_dir(dir, root = "f", include_ns = "utils", prune = "head")),
               c("f", "tail", "h"))
})

test_that("call_tree_dir include_defaults follows calls in default arguments", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "launch_app <- function(dir = util_dir(), quiet) app_ui(dir)",
    "app_ui <- function(dir = util_dir()) 1",
    "util_dir <- function() 1"
  )))

  expect_equal(all_names(call_tree_dir(dir, root = "launch_app")), c("launch_app", "app_ui"))
  tree <- call_tree_dir(dir, root = "launch_app", include_defaults = TRUE)
  expect_equal(child_names(tree), c("util_dir", "app_ui"))
  expect_equal(child_names(tree$calls[[2]]), "util_dir")
  expect_error(call_tree_dir(dir, root = "launch_app", include_defaults = NA), "`include_defaults`")
})

test_that("call_tree_dir warns once about functions defined in several files", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list(
    "a.R" = c("f <- function() 1", "g <- function() 1"),
    "b.R" = c("f <- function() h()", "g <- function() 2"),
    "c.R" = "h <- function() 1"
  ))

  expect_warning(
    tree <- call_tree_dir(dir, root = "f"),
    "`f` \\(a.R, b.R\\); `g` \\(a.R, b.R\\)"
  )
  expect_equal(child_names(tree), "h")
})

test_that("call_tree_dir does not warn without duplicates", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("a.R" = "f <- function() 1", "b.R" = "g <- function() 1"))
  expect_no_warning(call_tree_dir(dir, root = "f"))
})

test_that("call_items handles missing arguments and complex call heads", {
  expr <- parse(text = "function(x) { x[, 1]; f()(); obj$fn(); (function() h())() }")[[1]]
  expect_equal(call_items(list(expr), c("f", "h")), list("f", "h"))
})

test_that("call_tree_dir include_ns = 'base' skips syntax and control flow", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "f <- function() { x <- 1; if (TRUE) options(a = g()); for (i in 1) g() }",
    "g <- function() 1"
  )))

  tree <- call_tree_dir(dir, root = "f", include_ns = "base")
  expect_equal(child_names(tree), c("options", "g"))
  expect_equal(child_names(tree$calls[[1]]), "g")
})

test_that("call_tree_dir ignores parameters and local variables named like functions", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "wealth <- function(income, savings_rate) income * savings_rate",
    "savings_rate <- function() 0.1",
    "version <- function() { scc <- find_scc(); run(scc) }",
    "scc <- function() 1",
    "find_scc <- function() 1",
    "loop <- function(xs) for (scc in xs) print(scc)",
    "both <- function(savings_rate) savings_rate()"
  )))

  expect_length(call_tree_dir(dir, root = "wealth")$calls, 0)
  expect_equal(child_names(call_tree_dir(dir, root = "version")), "find_scc")
  expect_length(call_tree_dir(dir, root = "loop")$calls, 0)
  expect_equal(child_names(call_tree_dir(dir, root = "both")), "savings_rate")
})

test_that("call_tree_dir still counts bare function references", {
  dir <- withr::local_tempdir()
  write_r_files(dir, list("f.R" = c(
    "launch <- function() shinyApp(app_ui, app_server)",
    "app_ui <- function() 1",
    "app_server <- function(input, output) lapply(1:2, helper)",
    "helper <- function(x) x"
  )))

  tree <- call_tree_dir(dir, root = "launch")
  expect_equal(child_names(tree), c("app_ui", "app_server"))
  expect_equal(child_names(tree$calls[[2]]), "helper")
})

test_that("find_calls skips names bound inside the function", {
  expr <- parse(text = "function(a) { b <- 1; a; b; c; d() }")[[1]]
  expect_setequal(find_calls(expr, c("a", "b", "c", "d")), c("c", "d"))
})

skip_if_not_installed("shiny")

mod_a_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(shiny::textOutput(ns("out")))
}

mod_a_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    output$out <- shiny::renderText("hello")
  })
}

a_helper <- function(x) x + 1

test_that("errors on non-shiny.appobj input", {
  expect_error(call_tree_app("not_an_app"))
  expect_error(call_tree_app(list()))
})

test_that("errors with a specific message on a startApp() ShinyAppHandle", {
  skip_if_not(exists("startApp", where = asNamespace("shiny")))

  app <- shiny::shinyApp(
    ui = function() shiny::fluidPage(),
    server = function(input, output, session) {}
  )
  handle <- shiny::startApp(app, port = 0, launch.browser = FALSE, quiet = TRUE)
  withr::defer(handle$stop())

  expect_error(call_tree_app(handle), "ShinyAppHandle")
  expect_error(call_tree_app(handle), "startApp")
})

test_that("detects a module when UI is an unevaluated function", {
  my_ui <- function() shiny::fluidPage(mod_a_ui("a"))
  my_server <- function(input, output, session) mod_a_server("a")

  app <- shiny::shinyApp(ui = my_ui, server = my_server)
  tree <- call_tree_app(app)

  expect_s3_class(tree, "call_stack")
  expect_equal(tree$name, "app")
  names <- vapply(tree$calls, function(x) x$name, character(1))
  expect_true("my_ui" %in% names)
  expect_true("my_server" %in% names)

  server_node <- tree$calls[[which(names == "my_server")]]
  grandchild_names <- vapply(server_node$calls, function(x) x$name, character(1))
  expect_true("mod_a_server" %in% grandchild_names)
})

test_that("app_fun sets the root label", {
  app <- shiny::shinyApp(ui = function() shiny::fluidPage(), server = function(input, output, session) {})
  tree <- call_tree_app(app, app_fun = "launch")
  expect_equal(tree$name, "launch")
})

test_that("ui_fun fallback resolves the UI branch when UI is pre-evaluated", {
  pre_ui <- function() shiny::fluidPage(mod_a_ui("a"))
  pre_server <- function(input, output, session) mod_a_server("a")

  app <- shiny::shinyApp(ui = pre_ui(), server = pre_server)
  tree <- call_tree_app(app, ui_fun = "pre_ui")

  names <- vapply(tree$calls, function(x) x$name, character(1))
  expect_true("pre_ui" %in% names)
})

test_that("modules_only prunes non-module helpers while keeping modules reachable", {
  helper_server <- function(input, output, session) {
    mod_a_server("a")
    a_helper(42)
  }
  app <- shiny::shinyApp(ui = function() shiny::fluidPage(), server = helper_server)

  tree <- call_tree_app(app, modules_only = TRUE)

  all_names <- function(node) c(node$name, unlist(lapply(node$calls, all_names)))
  expect_false("a_helper" %in% all_names(tree))
  expect_true("mod_a_server" %in% all_names(tree))
})

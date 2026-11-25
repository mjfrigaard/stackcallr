select_var <- function(id) shiny::selectInput(id, "Variable", names(mtcars))
make_plot <- function(x) graphics::hist(x)
log_msg <- function(id, msg) message("[", id, "] ", msg)

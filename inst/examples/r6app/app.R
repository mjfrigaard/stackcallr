app_ui <- function() {
  inputs <- ModInputs$new("inputs")
  plot <- ModPlot$new("plot")
  shiny::fluidPage(inputs$ui(), plot$ui())
}

app_server <- function(input, output, session) {
  inputs <- ModInputs$new("inputs")
  plot <- ModPlot$new("plot")
  var <- inputs$server()
  plot$server(var)
}

launch <- function() shiny::shinyApp(app_ui, app_server)

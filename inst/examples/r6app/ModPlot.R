ModPlot <- R6::R6Class("ModPlot",
  inherit = ModBase,
  public = list(
    ui = function() shiny::plotOutput(private$ns("plot")),
    server = function(var) {
      shiny::moduleServer(private$id, function(input, output, session) {
        private$log("plot ready")
        output$plot <- shiny::renderPlot(make_plot(var()))
      })
    }
  )
)

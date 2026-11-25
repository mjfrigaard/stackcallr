ModInputs <- R6::R6Class("ModInputs",
  inherit = ModBase,
  public = list(
    ui = function() private$picker(),
    server = function() {
      shiny::moduleServer(private$id, function(input, output, session) {
        private$log("inputs ready")
        shiny::reactive(input$var)
      })
    }
  ),
  private = list(
    picker = function() select_var(private$ns("var"))
  )
)

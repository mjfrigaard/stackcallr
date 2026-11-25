ModBase <- R6::R6Class("ModBase",
  public = list(
    initialize = function(id) {
      private$id <- id
      private$ns <- shiny::NS(id)
    }
  ),
  private = list(
    id = NULL,
    ns = NULL,
    log = function(msg) log_msg(private$id, msg)
  )
)

#' Launch Workflow Chat in RStudio Viewer Pane
#'
#' @description
#' `r lifecycle::badge("deprecated")`
#'
#' \code{workflow_gadget()} has been renamed to \code{\link{workflow_create}}.
#' This wrapper calls \code{workflow_create(mode = "viewer")} and will be
#' removed in a future version.
#'
#' @inheritParams workflow_create
#'
#' @return See \code{\link{workflow_create}}.
#'
#' @seealso \code{\link{workflow_create}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Use workflow_create() instead:
#' workflow_create(mode = "viewer")
#' }
workflow_gadget <- function(model      = "claude-sonnet-4-6",
                            api_key    = NULL,
                            output_dir = ".",
                            trial      = FALSE) {

  message("Note: workflow_gadget() is deprecated. Use workflow_create() instead.")
  workflow_create(
    mode       = "viewer",
    output_dir = output_dir,
    model      = model,
    api_key    = api_key,
    trial      = trial
  )
}

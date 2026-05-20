#' @keywords internal
"_PACKAGE"

#' TaxaFlag: Flag Anomalous Detections in Taxonomic Assignments
#'
#' Identifies and flags anomalous detections in taxonomic assignment results.
#' Detects laboratory and field contamination, flags handler-related artifacts,
#' and provides LLM-based expert review of assignment plausibility.
#'
#' @section Contamination:
#' \itemize{
#'   \item \code{\link{flag_contaminant}} -- compare against control samples
#' }
#'
#' @section Handler artifacts:
#' \itemize{
#'   \item \code{\link{flag_handler}} -- temporal proximity flagging
#' }
#'
#' @section Expert review:
#' \itemize{
#'   \item \code{\link{review_assignments}} -- LLM-based plausibility review
#' }
#'
#' @section Reporting:
#' \itemize{
#'   \item \code{\link{report_flags}} -- generate Methods/Results section
#' }
#'
#' @name TaxaFlag-package
#' @aliases TaxaFlag
NULL

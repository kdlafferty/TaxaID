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
#' @section Post-hoc plausibility and discrimination:
#' \itemize{
#'   \item \code{\link{add_posthoc_assessment}} -- occurrence plausibility
#'     (Axis 1) and evidence discrimination (Axis 2) for a
#'     \code{TaxaAssign::posterior_consensus()} output
#'   \item \code{\link{build_review_covariates}} -- collapse a long-format
#'     reads table into per-observation covariates for modelling how an
#'     observation was classified
#' }
#'
#' @section Spatial context:
#' \itemize{
#'   \item \code{\link{check_gbif_tile_range}} -- cheap, global, approximate
#'     isolation signal from GBIF's occurrence-density map tiles
#'   \item \code{\link{compute_local_occurrence_distance}} -- free, local,
#'     exact distance to the nearest already-fetched occurrence
#'   \item \code{\link{review_spatial_context}} -- interactive click-through
#'     gadget combining both, plus a live GBIF density-tile map
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

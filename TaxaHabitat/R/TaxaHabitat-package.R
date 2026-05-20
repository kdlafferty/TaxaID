#' @keywords internal
"_PACKAGE"

#' TaxaHabitat: Habitat Assignment and Spatial Quality Control
#'
#' Assigns habitat classifications to species using LLM-based biological
#' consensus and performs spatial quality control on occurrence records.
#' Supports multiple habitat schemes (3-category, IUCN Level 1, custom).
#'
#' @section Habitat assignment:
#' \itemize{
#'   \item \code{\link{build_habitat_prompt}} -- create LLM prompt for habitat
#'     classification
#'   \item \code{\link{parse_hierarchical_habitat_response}} -- parse LLM output
#'     to habitat weights
#'   \item \code{\link{assign_habitat_biological}} -- assign site-level habitat
#'     from species weights
#'   \item \code{\link{consensus_habitat}} -- assemblage-level consensus
#' }
#'
#' @section Spatial quality control:
#' \itemize{
#'   \item \code{\link{flag_habitat_inconsistencies}} -- flag spatial outliers
#' }
#'
#' @section Reporting:
#' \itemize{
#'   \item \code{\link{report_habitat}} -- generate Methods/Results section
#' }
#'
#' @name TaxaHabitat-package
#' @aliases TaxaHabitat
NULL

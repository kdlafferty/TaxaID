#' @keywords internal
"_PACKAGE"

#' TaxaExpect: Estimate Bayesian Priors for Species Occurrence
#'
#' Generates theta priors (occupancy x detectability) for taxonomic assignment
#' from occurrence data. Uses spatial biodiversity models to estimate expected
#' species composition at grid cells, incorporating habitat and geographic
#' distance effects.
#'
#' @section High-level wrapper:
#' \itemize{
#'   \item \code{\link{build_priors}} -- end-to-end: GBIF fetch through prior
#'     generation
#' }
#'
#' @section Spatial modelling:
#' \itemize{
#'   \item \code{\link{create_sites_from_grid}} -- generate spatial grid
#'   \item \code{\link{optimize_grid_size}} -- find optimal grid resolution
#'   \item \code{\link{train_biodiversity_model}} -- fit hierarchical spatial
#'     model
#'   \item \code{\link{generate_full_priors}} -- predict priors at new sites
#' }
#'
#' @section Dark diversity:
#' \itemize{
#'   \item \code{\link{generate_undetected_diversity}} -- estimate priors for
#'     unobserved species
#' }
#'
#' @section Reporting:
#' \itemize{
#'   \item \code{\link{report_priors}} -- generate Methods/Results section
#' }
#'
#' @name TaxaExpect-package
#' @aliases TaxaExpect
NULL

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
#'   \item \code{\link{compute_moran_basis}} -- Moran eigenvector spatial
#'     autocorrelation basis
#'   \item \code{\link{prepare_model_dataframe}} -- aggregate occurrences to
#'     species x site-habitat counts
#'   \item \code{\link{screen_spatial_formula}} -- screen/select a
#'     parsimonious spatial formula by AIC
#'   \item \code{\link{train_biodiversity_model}} -- fit hierarchical spatial
#'     model
#'   \item \code{\link{train_biodiversity_model_by_group}} -- fit one model
#'     per sampling group (broad-marker data spanning multiple detection
#'     processes)
#'   \item \code{\link{compute_adaptive_sampling_groups}} -- automate the
#'     sampling-group classification \code{train_biodiversity_model_by_group}
#'     needs
#'   \item \code{\link{add_pca_covariates}} -- orthogonalize correlated
#'     covariates via PCA
#'   \item \code{\link{generate_full_priors}} -- predict priors at new sites
#'   \item \code{\link{plot_theta_map_interactive}} -- interactive Leaflet
#'     exploration of predicted priors
#' }
#'
#' @section Dark diversity:
#' \itemize{
#'   \item \code{\link{generate_undetected_diversity}} -- estimate priors for
#'     unobserved species
#'   \item \code{\link{generate_domestic_food_priors}} -- non-GBIF priors for
#'     domestic/food/cultivated-plant species
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

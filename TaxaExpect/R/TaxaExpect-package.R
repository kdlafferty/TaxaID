#' @keywords internal
"_PACKAGE"

#' TaxaExpect: Estimate Bayesian Priors for Species Occurrence
#'
#' Generates theta priors (compositional shares) for taxonomic assignment
#' from occurrence data, using a site-centered distance kernel that
#' incorporates habitat and geographic (and optionally covariate) distance
#' effects.
#'
#' @section Spatial modelling:
#' \itemize{
#'   \item \code{\link{estimate_kernel_priors}} -- site-centered kernel
#'     estimator; \code{sampling_group_col} fits
#'     one composition/budget per sampling group (broad-marker data spanning
#'     multiple detection processes) -- \strong{omitting it is not safe}:
#'     with no \code{sampling_group_col}, the function pools every record
#'     regardless of detection process, with no warning or error, even
#'     when that means silently mixing e.g. phytoplankton cell counts with
#'     bird point counts. Build the column yourself from domain knowledge --
#'     there is no automated way to detect a "comparable detection method"
#'     from taxonomy or data alone (see \code{README.md}'s "Shared detection
#'     effort" section for why an automatic classifier is not used).
#'   \item \code{\link{calibrate_kernel_bandwidth}} -- leave-one-block-out
#'     bandwidth selection for the kernel estimator
#'   \item \code{\link{plot_theta_surface}} -- KDE prior-field map for the
#'     kernel-priors path
#' }
#'
#' @section Why a kernel estimator:
#' TaxaExpect considered a range of modeling strategies, including grid-cell
#' mixed models (GLMM) and per-species latent spatial fields, but adopted a
#' site-centered kernel estimator: leave-one-block-out validation on real
#' occurrence data shows it out-predicts both grid-based and single-cell
#' prediction at every bandwidth tested, and it scales to many-species
#' composition prediction without the per-species model-fitting cost a
#' spatial model would require (see \code{\link{estimate_kernel_priors}}'s
#' own \verb{Why an estimator, not a spatial model} section for the
#' validation numbers).
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

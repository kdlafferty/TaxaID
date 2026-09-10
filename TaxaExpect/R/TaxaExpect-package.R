#' @keywords internal
"_PACKAGE"

#' TaxaExpect: Estimate Bayesian Priors for Species Occurrence
#'
#' Generates theta priors (occupancy x detectability) for taxonomic assignment
#' from occurrence data. Uses spatial biodiversity models to estimate expected
#' species composition at grid cells, incorporating habitat and geographic
#' distance effects.
#'
#' @section Spatial modelling:
#' \itemize{
#'   \item \code{\link{estimate_kernel_priors}} -- site-centered kernel
#'     estimator (current recommended path); \code{sampling_group_col} fits
#'     one composition/budget per sampling group (broad-marker data spanning
#'     multiple detection processes) -- \strong{omitting it is not safe}:
#'     with no \code{sampling_group_col}, the function pools every record
#'     regardless of detection process, with no warning or error, even
#'     when that means silently mixing e.g. phytoplankton cell counts with
#'     bird point counts. Build the column yourself from domain knowledge --
#'     there is no automated way to detect a "comparable detection method"
#'     from taxonomy or data alone (see \code{README.md}'s "Shared detection
#'     effort" section for why an automatic classifier was tried and
#'     rejected).
#'   \item \code{\link{calibrate_kernel_bandwidth}} -- leave-one-block-out
#'     bandwidth selection for the kernel estimator
#'   \item \code{\link{plot_theta_surface}} -- KDE prior-field map for the
#'     kernel-priors path
#' }
#'
#' @section Archived (GLMM/grid prior-fitting chain):
#' \code{build_priors()}, \code{optimize_grid_size()},
#' \code{prepare_model_dataframe()}, \code{add_pca_covariates()}/
#' \code{apply_pca_transform()}, \code{compute_moran_basis()},
#' \code{screen_spatial_formula()}, \code{train_biodiversity_model()},
#' \code{train_biodiversity_model_by_group()}, \code{generate_full_priors()},
#' and their dedicated visualization, \code{plot_theta_map_interactive()},
#' are archived -- no longer present in the installed package. This
#' 9-function GLMM/grid chain was archived 2026-09-09, deprecated
#' ecosystem-wide 2026-08-31 in favor of \code{\link{estimate_kernel_priors}}/
#' \code{\link{calibrate_kernel_bandwidth}} above, once every real
#' production workflow's migration to the kernel path was confirmed
#' complete. This part of the retirement is not reconsidered here -- the
#' GLMM modeling math itself really is obsolete on the kernel path.
#' \code{create_sites_from_grid()}/\code{compute_adaptive_sampling_groups()}
#' are ALSO archived, here with the rest of the chain -- their own real,
#' three-stage 2026-09-09 history (kept live, archived, restored, archived
#' again FINAL) is recorded in full in TaxaExpect/CLAUDE.md's session notes.
#' The final archival reason: empirical testing against a real, full-scale
#' 9-group expert-classified 18S occurrence checkpoint showed
#' \code{compute_adaptive_sampling_groups()} answers a different question
#' than \code{sampling_group} is meant to answer (per-site record adequacy,
#' not shared detection process), fragments a single real detection process
#' into dozens of automatic groups, and can conflate genuinely distinct
#' detection processes (e.g. marine parasites with terrestrial arthropod
#' contamination) purely because neither clears a sample-size floor. The
#' same real data confirmed \code{estimate_kernel_priors()} does NOT need
#' pre-merged, sample-size-adequate groups at all -- it degrades gracefully
#' for a sparse group (honestly wide uncertainty), so no automatic-merge
#' fallback was ever actually necessary. See TaxaExpect/CLAUDE.md's
#' 2026-09-09 session notes for the full record, including the real Finding
#' 1-5 evidence. The rest of the chain's archive is kept, not committed, at
#' \code{archive_glmm_prior_pipeline/}.
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

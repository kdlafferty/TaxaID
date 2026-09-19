# ==============================================================================
# Shared internal helpers used by multiple exported functions in this package.
# Consolidated here (code-review response, 2026-08-04) to close out three
# separate instances of the same duplication flagged in inst/taxaexpect_review.Rmd:
#   - beta_mean()/beta_sd() were reimplemented identically in
#     generate_full_priors.R, generate_undetected_diversity.R, and
#     generate_domestic_food_priors.R.
#   - A grid_id-string-to-centroid parser was reimplemented (with two
#     different internal approaches) in compute_moran_basis.R and
#     plot_theta_map_interactive.R.
#   - The genus/family/order/class/phylum rank-column vector used to join
#     taxonomy onto proxy prior rows was reimplemented identically in
#     generate_undetected_diversity.R and generate_domestic_food_priors.R.
#
# 2026-09-09: .parse_grid_id_coords() and .glmm_deprecation_notice() removed
# -- both were used only by the GLMM grid/prior-fitting chain archived this
# session (see TaxaExpect/CLAUDE.md's 2026-09-09 session note); with every
# one of their callers gone, both were fully orphaned dead code. Moved intact
# (not just deleted) as part of archive_glmm_prior_pipeline/'s own record --
# see that directory's R/plot_theta_map_interactive.R and R/compute_moran_
# basis.R for .parse_grid_id_coords()'s original callers, and any archived
# chain file's .glmm_deprecation_notice("<fn_name>") call for that helper's.
# ==============================================================================

#' Beta distribution mean from alpha/beta
#' @param a,b Numeric vectors. Beta shape parameters.
#' @return Numeric vector.
#' @noRd
.beta_mean <- function(a, b) a / (a + b)

#' Beta distribution SD from alpha/beta
#' @param a,b Numeric vectors. Beta shape parameters.
#' @return Numeric vector.
#' @noRd
.beta_sd <- function(a, b) sqrt((a * b) / ((a + b)^2 * (a + b + 1)))

#' Rank columns used to join taxonomy onto anonymous/named proxy prior rows
#'
#' Deliberately excludes \code{kingdom} (rarely useful for grouping proxy
#' rows) and \code{species} (proxy rows never carry a species-level identity
#' -- either \code{taxon_name} is NA (dark-diversity proxies) or the row's
#' species-level name IS \code{taxon_name} already, not a separate rank
#' column). Ordered finest to coarsest, matching the order both consumers
#' historically used.
#' @noRd
.dark_diversity_rank_cols <- c("genus", "family", "order", "class", "phylum")

#' Is an occurrence point's habitat unassigned?
#'
#' Mirrors \code{TaxaHabitat}'s own predicate. TRUE for \code{NA}, for an
#' empty/whitespace string, and for the \code{"Uncertain"} sentinel that
#' \code{TaxaHabitat::assign_habitat_biological()} has written since
#' 2026-09-19 where no habitat reaches \code{threshold}.
#'
#' Reimplemented here rather than called from TaxaHabitat because TaxaExpect
#' only \emph{Suggests} that package -- an occurrence table can reach these
#' functions from anywhere, and a hard Import for a three-line predicate
#' would invert the dependency between the habitat producer and the prior
#' consumer.
#'
#' \strong{Both vocabularies must keep working.} Every occurrence table and
#' decision file written before 2026-09-19 stores \code{NA}, and they are read
#' by the same code as tables written after it. A bare \code{is.na()} or a
#' bare \code{== "Uncertain"} is wrong in one direction or the other; this is
#' the only safe test.
#' @param x Character vector (or coercible) of habitat labels.
#' @return Logical vector, same length as \code{x}.
#' @noRd
.is_habitat_unassigned <- function(x) {
  x <- as.character(x)
  is.na(x) | !nzchar(trimws(x)) | x == "Uncertain"
}

# generate_inat_range_evidence.R
# TaxaExpect package

#' Evidence rows for species inside their iNaturalist range polygon
#'
#' The third evidence generator for \code{\link{apply_undetected_evidence}}
#' (2026-08-26 mixture redesign, D6), alongside
#' \code{\link{generate_invasive_watch_evidence}} and
#' \code{\link{generate_regional_proximity_evidence}}. Converts
#' \code{TaxaFetch::check_inat_range()} output into presence-probability
#' evidence, replacing \code{TaxaAssign::adjust_inat_range_priors()}'s
#' post-join binary elevation for the mixture pathway -- so iNat evidence
#' shares the same anchors, moment-matched concentration, and multi-source
#' probabilistic-OR combination as every other evidence channel, instead of
#' jumping rows straight to the singleton level outside the framework.
#'
#' @section Where iNat sits, and why below the singleton:
#' An in-range polygon with substantial observation coverage is close to
#' observational evidence of regional presence -- much stronger than a lone
#' distant GBIF record -- so its weight sits near the ceiling but at a
#' deliberate "small disadvantage" (user design decision, 2026-08-26): the
#' default \code{weight = 0.8} reads as P(locally present | in range,
#' well-observed), discounted below 1 because (a) a range polygon is regional,
#' not site-scale, and (b) citizen-science identifications carry a real
#' misidentification rate.
#'
#' @section Calibration status (2026-09-05 critical-fix-review, finding A2):
#' Unlike \code{\link{generate_regional_proximity_evidence}}'s \code{w_scale}
#' (checklist-calibrated against a real site species list) and
#' \code{generate_invasive_watch_evidence()}'s weight (derived from the
#' dataset-independent ordering bound), this function's \code{0.8} default is
#' design intuition, not empirically calibrated -- it predates the checklist-
#' calibration work by two days and was never re-examined against it. Under
#' \code{pricing = "blend"} (see \code{\link{apply_undetected_evidence}}), the
#' printed dataset-specific veto bound is often far below 0.8 (~0.05 on
#' GreatLakes' own real anchors) -- a weight this high can block species-level
#' resolution of a genuinely observed singleton-level native, the exact
#' failure the pre-calibration invasive weight (0.6) caused for yellow perch
#' before it was cut to 0.05. \code{apply_undetected_evidence()} already warns
#' generically whenever any evidence source's combined weight exceeds that
#' bound in blend mode, so a blend-mode misuse of this default will not pass
#' silently -- but the warning fires after the row is built, not before, and
#' no number here has been chosen to avoid triggering it. Under
#' \code{pricing = "curve"} the bound is structurally unreachable (see that
#' function's own docs), so \code{0.8} carries no such risk there -- this is
#' the only pricing mode any real production caller currently uses this
#' function under. Before wiring this into a blend-mode workflow, either lower
#' \code{weight} below that call's own printed bound or calibrate it by the
#' same checklist recipe \code{w_scale} used, rather than trusting this
#' default's intuition-only provenance.
#'
#' @section The fuzzy-match gate is mandatory by default:
#' iNaturalist's taxon search takes the single best TEXT match, so a query
#' can silently resolve to a DIFFERENT species (real production case:
#' \emph{Gasterosteus gymnurus} resolved to \emph{G. aculeatus}, returning
#' \code{in_range = TRUE} for the wrong organism). At near-singleton weight
#' that error is far more consequential than at the floor, so rows whose
#' \code{name_match} is not \code{TRUE} are excluded by default
#' (\code{require_name_match = TRUE}) and counted in a message. Requires
#' \code{check_inat_range()} output that carries the \code{name_match}
#' column (2026-08-28+); older cached tables lacking it are treated as
#' unverified and excluded, with a message saying to re-run the check.
#'
#' @param inat_range Data frame from \code{TaxaFetch::check_inat_range()}.
#' @param weight Numeric, 0-1. P(locally present) for an in-range,
#'   well-observed, name-verified species. Default \code{0.8}.
#' @param p_conc Numeric > 0. Presence-claim confidence in
#'   pseudo-observations (drives the confirmation update, not the static
#'   prior -- see \code{\link{apply_undetected_evidence}}). Default \code{1}.
#' @param n_obs_threshold Integer. Minimum \code{n_observations} for the
#'   range polygon to count as well-observed. Default \code{500L}, matching
#'   \code{TaxaAssign::adjust_inat_range_priors()}'s established value.
#' @param require_name_match Logical. Exclude rows whose resolved iNat name
#'   differs from the query (or cannot be verified). Default \code{TRUE};
#'   set \code{FALSE} only with a reviewed name mapping in hand.
#'
#' @return Evidence tibble (\code{taxon_name}, \code{weight}, \code{p_conc},
#'   \code{source = "inat_range"}), ready to \code{dplyr::bind_rows()} with
#'   other generators' output and feed to
#'   \code{\link{apply_undetected_evidence}}. Zero rows when nothing
#'   qualifies.
#'
#' @examples
#' \dontrun{
#' inat_evidence <- generate_inat_range_evidence(inat_range)
#' evidence <- dplyr::bind_rows(invasive_evidence, regional_evidence, inat_evidence)
#' }
#'
#' @export
generate_inat_range_evidence <- function(
  inat_range,
  weight = 0.8,
  p_conc = 1,
  n_obs_threshold = 500L,
  require_name_match = TRUE
) {
  required_cols <- c("taxon_name", "in_range", "n_observations")
  if (!is.data.frame(inat_range) || !all(required_cols %in% names(inat_range))) {
    stop(
      "generate_inat_range_evidence: `inat_range` must be a data frame with columns ",
      paste(required_cols, collapse = ", "),
      " (TaxaFetch::check_inat_range() output)."
    )
  }
  if (!is.numeric(weight) || length(weight) != 1L || is.na(weight) ||
    weight < 0 || weight > 1) {
    stop("generate_inat_range_evidence: `weight` must be a single non-NA value in [0, 1].")
  }
  if (!is.numeric(p_conc) || length(p_conc) != 1L || is.na(p_conc) || p_conc <= 0) {
    stop("generate_inat_range_evidence: `p_conc` must be a single non-NA positive value.")
  }
  if (!is.logical(require_name_match) || length(require_name_match) != 1L ||
    is.na(require_name_match)) {
    stop("generate_inat_range_evidence: `require_name_match` must be TRUE or FALSE.")
  }

  keep <- !is.na(inat_range$in_range) & inat_range$in_range &
    !is.na(inat_range$n_observations) &
    inat_range$n_observations >= n_obs_threshold

  if (require_name_match) {
    if (!"name_match" %in% names(inat_range)) {
      message(
        "generate_inat_range_evidence: `inat_range` has no name_match ",
        "column (pre-2026-08-28 check_inat_range() output) -- every row ",
        "is unverifiable against the fuzzy-match risk and is excluded. ",
        "Re-run TaxaFetch::check_inat_range() to get the column."
      )
      keep <- keep & FALSE
    } else {
      unverified <- keep & !(inat_range$name_match %in% TRUE)
      if (any(unverified)) {
        message(sprintf(
          "generate_inat_range_evidence: %d in-range row(s) excluded -- resolved iNat name differs from the query (or is unverifiable): %s",
          sum(unverified),
          paste(utils::head(inat_range$taxon_name[unverified], 5L), collapse = ", ")
        ))
      }
      keep <- keep & (inat_range$name_match %in% TRUE)
    }
  }

  taxa <- unique(inat_range$taxon_name[keep])
  if (length(taxa) == 0L) {
    message("generate_inat_range_evidence: no qualifying in-range taxa -- zero evidence rows.")
    return(tibble::tibble(
      taxon_name = character(0), weight = numeric(0),
      p_conc = numeric(0), source = character(0)
    ))
  }
  tibble::tibble(
    taxon_name = taxa,
    weight     = weight,
    p_conc     = p_conc,
    source     = "inat_range"
  )
}

#' Evidence rows for a user-supplied invasive/nonindigenous watch list
#'
#' A thin evidence generator for
#' \code{\link{apply_undetected_evidence}}: given a plain, user-supplied list
#' of taxa (e.g. hand-pulled from the USGS Nonindigenous Aquatic Species
#' database, or any other invasion-biology source relevant to your study),
#' produces one evidence row per listed taxon with a flat, caller-chosen
#' weight and confidence. Deliberately does no live querying, no
#' geography/watershed reasoning, and no Beta-parameter math -- see
#' \code{\link{apply_undetected_evidence}} for why that split exists and
#' where the actual prior construction happens.
#'
#' @section Why no live query or region-scoping here:
#' An earlier version of this mechanism queried the USGS NAS database live
#' and scoped results by watershed (HUC8). That baked a narrow (aquatic-only,
#' United-States-only) external data source and freshwater-specific
#' watershed-connectivity logic into a package meant to stay generic across
#' taxa and geography. Region-scoping now happens entirely on the caller's
#' side, in how \code{invasive_taxa} is built (e.g. filter a NAS pull to
#' species actually relevant to your basin before calling this function) --
#' this function only knows "is this taxon on the list," nothing else.
#'
#' @section Tiering via repeated calls, not a built-in tier system:
#' If different taxa on your list warrant different confidence (e.g. a
#' species with multiple confirmed regional populations vs. one with a
#' single distant record), call this function once per tier with a
#' different \code{weight}/\code{p_conc} and \code{dplyr::bind_rows()} the
#' results before passing them to \code{apply_undetected_evidence()} --
#' \code{evidence} tables from any number of calls combine naturally, so no
#' tiering logic needs to live inside this function itself.
#'
#' @param invasive_taxa Character vector of taxon names. Required, no
#'   default.
#' @param weight Numeric, 0-1. How strongly this list's membership should
#'   pull an unobserved taxon's prior toward the singleton-mirror ceiling --
#'   see \code{\link{apply_undetected_evidence}}'s \verb{How the elevation
#'   works} section for the exact blend. Required, no default: there is no
#'   universally defensible value (an invasion risk you're highly confident
#'   about locally warrants a different weight than a precautionary
#'   watch-list entry, and this function has no way to know which is which
#'   for your study).
#' @param p_conc Numeric, > 0. How much weight the presence claim carries
#'   against future evidence (the confirmation update), in
#'   pseudo-observations. Default 1 -- a curated listing counts as roughly
#'   one direct observation about presence. Does NOT affect the static
#'   prior's mean or concentration (both now derive from \code{weight} via
#'   \code{\link{apply_undetected_evidence}}'s presence-mixture moment
#'   matching -- the former \code{n_eff} knob is retired).
#' @param match_list_taxa Optional character vector of taxa that actually
#'   have a likelihood this run (e.g. \code{unique(match_obj$taxon_name)}).
#'   When supplied, \code{invasive_taxa} is restricted to the intersection
#'   -- avoids emitting evidence for list members that were never even
#'   candidates this run. Default \code{NULL} (no restriction).
#'
#' @return A tibble with one row per taxon in scope: \code{taxon_name},
#'   \code{weight}, \code{p_conc}, \code{source} (always
#'   \code{"invasive_watch"}). Matches the evidence-table schema
#'   \code{\link{apply_undetected_evidence}} expects. Empty tibble (correct
#'   schema, zero rows) when nothing is in scope.
#'
#' @seealso \code{\link{apply_undetected_evidence}}
#'
#' @examples
#' \dontrun{
#' # A list you built by hand, e.g. from the USGS NAS database, restricted
#' # to species genuinely relevant to your study region.
#' invasive_evidence <- generate_invasive_watch_evidence(
#'   invasive_taxa = c("Gymnocephalus cernua", "Neogobius melanostomus"),
#'   weight = 0.05
#' )
#' }
#'
#' @importFrom tibble tibble
#' @export
generate_invasive_watch_evidence <- function(
    invasive_taxa,
    weight,
    p_conc = 1,
    match_list_taxa = NULL
) {
  if (!is.character(invasive_taxa) || length(invasive_taxa) == 0L) {
    stop("generate_invasive_watch_evidence: `invasive_taxa` must be a non-empty character vector.")
  }
  if (!is.numeric(weight) || length(weight) != 1L || is.na(weight) || weight < 0 || weight > 1) {
    stop("generate_invasive_watch_evidence: `weight` must be a single non-NA value in [0, 1].")
  }
  if (!is.numeric(p_conc) || length(p_conc) != 1L || is.na(p_conc) || p_conc <= 0) {
    stop("generate_invasive_watch_evidence: `p_conc` must be a single non-NA positive value.")
  }
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    stop("generate_invasive_watch_evidence: the TaxaTools package is required ",
         "(used to normalize candidate taxon names via clean_taxon_names()).")
  }

  raw_names     <- unique(invasive_taxa)
  cleaned_names <- TaxaTools::clean_taxon_names(raw_names)
  dropped       <- unique(raw_names[is.na(cleaned_names)])
  if (length(dropped) > 0L) {
    warning(sprintf(
      "generate_invasive_watch_evidence: %d taxon name(s) could not be cleaned by TaxaTools::clean_taxon_names() and were dropped: %s",
      length(dropped), paste(dropped, collapse = ", ")
    ), call. = FALSE)
  }
  candidates <- unique(stats::na.omit(cleaned_names))

  if (!is.null(match_list_taxa) && length(match_list_taxa) > 0L) {
    match_set  <- unique(stats::na.omit(TaxaTools::clean_taxon_names(match_list_taxa)))
    n_before   <- length(candidates)
    candidates <- intersect(candidates, match_set)
    message(sprintf(
      "generate_invasive_watch_evidence: match_list_taxa supplied -- restricted %d listed taxon/taxa to %d actually present in the match list.",
      n_before, length(candidates)
    ))
  }

  if (length(candidates) == 0L) {
    message("generate_invasive_watch_evidence: no candidate taxa in scope.")
    return(tibble::tibble(
      taxon_name = character(0), weight = numeric(0),
      p_conc = numeric(0), source = character(0)
    ))
  }

  tibble::tibble(
    taxon_name = candidates,
    weight     = weight,
    p_conc     = p_conc,
    source     = "invasive_watch"
  )
}

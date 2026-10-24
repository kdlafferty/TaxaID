# ==============================================================================
# TaxaFlag -- Detected-site facts for the LLM review prompt
# ==============================================================================
# A study-wide geographic question has no single answer when the study spans a
# range edge, so with a site table the prompt asks for the taxon's range LIMITS
# and tells each taxon line which of the study's sites that taxon was actually
# detected at. The verdicts are then computed here, per site, from the limits.
#
# Which sites a taxon was detected at is the study's own design, not evidence
# about the taxon: it fixes what the question is about, and it is what keeps the
# study-wide verdict from being taken over by a site where the taxon never
# appeared.

#' The "[detected at: ...]" bracket for one taxon
#'
#' Sites north to south, latitude to one decimal. A detected site the site
#' table does not know has no latitude, so it is left out here and takes the
#' study-wide verdict downstream; .validate_review_sites() has already warned
#' about it by name.
#' @noRd
.detected_sites_bracket <- function(site_vec, sites) {
  if (length(site_vec) == 0L) {
    return(NA_character_)
  }
  idx <- match(site_vec, sites$site)
  idx <- idx[!is.na(idx)]
  if (length(idx) == 0L) {
    return(NA_character_)
  }
  idx <- idx[order(-sites$lat[idx])]
  sprintf(
    "[detected at: %s]",
    paste(sprintf("%s (%.1f N)", sites$site[idx], sites$lat[idx]), collapse = "; ")
  )
}

#' The sites where each reviewed label was detected
#'
#' One reviewed label can stand for several canonical candidate sets, so the
#' sites are gathered over every join key the label covers rather than by name.
#' Returned in north-to-south order so the bracket and the facts agree.
#' @noRd
.review_detected_sites <- function(labels, input_df, site_col, sites,
                                   label_canon_map = NULL) {
  by_key <- split(
    as.character(input_df[[site_col]]), as.character(input_df$.join_key)
  )
  lapply(labels, function(lab) {
    keys <- if (is.null(label_canon_map)) lab else label_canon_map[[lab]]
    v <- unique(unlist(by_key[as.character(keys)], use.names = FALSE))
    v <- v[!is.na(v) & v %in% sites$site]
    v[order(-sites$lat[match(v, sites$site)])]
  })
}

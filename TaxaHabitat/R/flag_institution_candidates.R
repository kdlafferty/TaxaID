# ==============================================================================
# flag_institution_candidates.R
# TaxaHabitat -- classify TaxaFetch::filter_gbif_quality()'s institution flags
# by suspicion tier, using institution type crossed with the record's kingdom
# ==============================================================================

#' Tier Institution-Proximity Flags by Suspicion
#'
#' Classification stage for the records \code{TaxaFetch::filter_gbif_quality()}
#' flags as near a biodiversity institution (\code{institution_flag = TRUE}).
#' Proximity alone is a weak signal: a live fish record near a university's
#' botanical garden pond and an herbarium sheet near the same garden mean very
#' different things. This function narrows that down using the matched
#' institution's own \code{type} (from \code{CoordinateCleaner::institutions})
#' crossed against the record's \code{kingdom} -- a herbarium match for a
#' plant is a real concern; a herbarium match for a fish essentially never is.
#'
#' This is a pure classification step -- no interaction, no rows removed or
#' reordered, mirroring \code{\link{flag_habitat_inconsistencies}}'s role
#' ahead of an interactive review gadget. It adds one column
#' (\code{institution_suspicion}) and makes no other change to \code{data}.
#'
#' @param data A dataframe, typically the output of
#'   \code{TaxaFetch::filter_gbif_quality()}. Must contain
#'   \code{institution_flag} and \code{institution_type} (both added by that
#'   function when \code{flag_institution = TRUE}, its default).
#' @param kingdom_col Character. Column holding each record's kingdom.
#'   Default \code{"kingdom"} (GBIF's standard column name).
#' @param suspicion_rules A dataframe with columns \code{institution_type},
#'   \code{kingdom}, \code{suspicion} (\code{"high"} or \code{"low"}) used to
#'   classify flagged records. \code{kingdom = NA} in a rule means "any
#'   kingdom for this institution type." A flagged record whose
#'   (\code{institution_type}, \code{kingdom}) combination doesn't match any
#'   rule -- including every \code{"Museum"}, \code{"University"}, and
#'   \code{"Research_centre"} match by default, since none are listed below
#'   -- gets \code{"ambiguous"}. Default rules (a first-pass heuristic, not a
#'   settled taxonomy -- override freely):
#'   \preformatted{
#'   institution_type  kingdom   suspicion
#'   Herbarium         Plantae   high
#'   Herbarium         Fungi     high
#'   Herbarium         <NA>      low
#'   Botanic_garden    Plantae   high
#'   Botanic_garden    <NA>      low
#'   Zoo               Animalia  high
#'   Zoo               <NA>      low
#'   }
#'   \code{"Museum"}/\code{"University"}/\code{"Research_centre"} are
#'   deliberately absent from the default rules -- real institutions of these
#'   types range from pure specimen archives to active field stations sited
#'   at the exact habitat they study (e.g. a marine lab on its own shoreline),
#'   and \code{institution_type} alone cannot tell those apart. That's exactly
#'   the case \code{\link{review_institution_flags}} exists for.
#'
#' @return \code{data} with one additional column, \code{institution_suspicion}:
#'   \code{"high"}, \code{"low"}, or \code{"ambiguous"} for a flagged record
#'   (\code{institution_flag = TRUE}); \code{NA} for every other record
#'   (never checked -- mirrors \code{\link{flag_habitat_inconsistencies}}'s
#'   convention of never conflating "not evaluated" with a real category).
#'
#' @seealso \code{\link{review_institution_flags}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' clean   <- TaxaFetch::filter_gbif_quality(gbif_raw)
#' tiered  <- flag_institution_candidates(clean)
#' table(tiered$institution_suspicion, useNA = "ifany")
#' }
flag_institution_candidates <- function(
    data,
    kingdom_col      = "kingdom",
    suspicion_rules  = NULL
) {

  if (!is.data.frame(data)) {
    stop("flag_institution_candidates: 'data' must be a dataframe.")
  }
  required_cols <- c("institution_flag", "institution_type")
  missing_cols  <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      paste0(
        "flag_institution_candidates: missing column(s): %s.\n",
        "  Run TaxaFetch::filter_gbif_quality(flag_institution = TRUE) first."
      ),
      paste(missing_cols, collapse = ", ")
    ))
  }
  if (!kingdom_col %in% names(data)) {
    stop(sprintf(
      "flag_institution_candidates: kingdom column '%s' not found.", kingdom_col
    ))
  }

  if (is.null(suspicion_rules)) {
    suspicion_rules <- data.frame(
      institution_type = c("Herbarium", "Herbarium", "Herbarium",
                           "Botanic_garden", "Botanic_garden",
                           "Zoo", "Zoo"),
      kingdom          = c("Plantae", "Fungi", NA,
                           "Plantae", NA,
                           "Animalia", NA),
      suspicion        = c("high", "high", "low",
                           "high", "low",
                           "high", "low"),
      stringsAsFactors = FALSE
    )
  }

  data$institution_suspicion <- NA_character_

  is_flagged <- !is.na(data$institution_flag) & data$institution_flag
  if (!any(is_flagged)) {
    message("flag_institution_candidates: no flagged records to tier.")
    return(data)
  }

  flagged_type    <- data$institution_type[is_flagged]
  flagged_kingdom <- data[[kingdom_col]][is_flagged]

  tier <- mapply(function(t, k) {
    # A record's own matched institution can genuinely have no recorded
    # `type` (real CoordinateCleaner::institutions rows do -- e.g. some
    # Scripps Institution of Oceanography matches). `suspicion_rules$
    # institution_type == t` with t = NA produces an all-NA logical index,
    # which subsets to NA elements rather than zero -- without this guard,
    # such a record silently gets institution_suspicion = NA instead of the
    # documented "ambiguous" fallback. Guard suspicion_rules$institution_type
    # on the other side too, in case a caller-supplied rules table has its
    # own NA institution_type row.
    if (is.na(t)) return("ambiguous")

    exact <- suspicion_rules$suspicion[
      !is.na(suspicion_rules$institution_type) &
      !is.na(suspicion_rules$kingdom) &
      suspicion_rules$institution_type == t &
      suspicion_rules$kingdom == k
    ]
    if (length(exact) > 0L) return(exact[[1]])

    wildcard <- suspicion_rules$suspicion[
      !is.na(suspicion_rules$institution_type) &
      is.na(suspicion_rules$kingdom) &
      suspicion_rules$institution_type == t
    ]
    if (length(wildcard) > 0L) return(wildcard[[1]])

    "ambiguous"
  }, flagged_type, flagged_kingdom, SIMPLIFY = TRUE, USE.NAMES = FALSE)

  data$institution_suspicion[is_flagged] <- tier

  message(sprintf(
    "flag_institution_candidates: %d flagged record(s) tiered -- %d high, %d low, %d ambiguous.",
    sum(is_flagged),
    sum(tier == "high", na.rm = TRUE),
    sum(tier == "low", na.rm = TRUE),
    sum(tier == "ambiguous", na.rm = TRUE)
  ))

  data
}

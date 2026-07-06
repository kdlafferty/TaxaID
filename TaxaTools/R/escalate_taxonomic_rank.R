#' Escalate a Taxon to the Next Coarser Rank
#'
#' @description
#' Given a taxon name currently being queried at `current_rank`, looks up its
#' full classification via [verify_taxon_names()] and returns the name at the
#' next coarser rank in `rank_system` -- e.g. broadening a genus with no
#' reference sequences or occurrence records to its family. If the immediate
#' next-coarser rank is itself absent from the classification path (a gap in
#' the backbone's own data, not a fetch-availability decision), continues
#' walking coarser ranks, up to `max_levels` steps from `current_rank`,
#' before giving up.
#'
#' This function only walks the taxonomic hierarchy -- it has no notion of
#' whether a fetch at any rank actually returned usable data. A consuming
#' retry loop (e.g. broadening a reference-sequence or occurrence fetch when
#' a singleton's own genus comes back empty) calls this once per escalation
#' step, refetches at the returned rank/name, and calls again with that pair
#' as the new `current_rank`/`taxon_name` if the refetch is still empty.
#'
#' @param taxon_name Character scalar. The taxon name currently being queried.
#' @param current_rank Character scalar. The rank `taxon_name` is at; must be
#'   present in `rank_system`.
#' @param rank_system Character vector of rank names, coarse to fine (see
#'   [standard_ranks]). Default `standard_ranks`.
#' @param max_levels Integer. Maximum number of rank levels to walk up from
#'   `current_rank` in a single call. Default `2L` (e.g. genus -> family ->
#'   order).
#' @param backbone_id Integer. Primary backbone for the classification
#'   lookup. Default `4L` (NCBI). Set `NULL` to skip straight to
#'   `fallback_backbone_id`.
#' @param fallback_backbone_id Integer. Secondary backbone tried if the
#'   primary backbone doesn't resolve `taxon_name`. Default `11L` (GBIF). Set
#'   `NULL` or equal to `backbone_id` to skip.
#' @param verbose Logical. Print progress messages. Default `TRUE`.
#'
#' @return A list with `taxon_name` and `rank`. Both are `NA_character_` if
#'   `current_rank` is already the coarsest rank in `rank_system`, if the
#'   classification cannot be resolved at all, or if no coarser rank resolves
#'   within `max_levels` steps.
#'
#' @seealso [verify_taxon_names()], [parse_classification_path()],
#'   [standard_ranks]
#'
#' @examples
#' \dontrun{
#' escalate_taxonomic_rank("Rhacochilus", current_rank = "genus")
#' # list(taxon_name = "Embiotocidae", rank = "family")
#' }
#'
#' @export
escalate_taxonomic_rank <- function(taxon_name,
                                     current_rank,
                                     rank_system = standard_ranks,
                                     max_levels = 2L,
                                     backbone_id = 4L,
                                     fallback_backbone_id = 11L,
                                     verbose = TRUE) {

  # ---- Input validation ------------------------------------------------------
  if (!is.character(taxon_name) || length(taxon_name) != 1L ||
      is.na(taxon_name) || !nzchar(trimws(taxon_name)))
    stop("taxon_name must be a single non-empty character string")
  if (!is.character(current_rank) || length(current_rank) != 1L || is.na(current_rank))
    stop("current_rank must be a single character string")
  if (!is.character(rank_system) || length(rank_system) == 0L)
    stop("rank_system must be a non-empty character vector")
  if (!(current_rank %in% rank_system))
    stop(sprintf("current_rank (\"%s\") not found in rank_system", current_rank))
  if (!is.numeric(max_levels) || length(max_levels) != 1L || is.na(max_levels) ||
      max_levels < 1L)
    stop("max_levels must be a single positive integer")
  if (!is.null(backbone_id) && (!is.numeric(backbone_id) ||
      length(backbone_id) != 1L || is.na(backbone_id)))
    stop("backbone_id must be a single integer or NULL")
  if (!is.null(fallback_backbone_id) && (!is.numeric(fallback_backbone_id) ||
      length(fallback_backbone_id) != 1L || is.na(fallback_backbone_id)))
    stop("fallback_backbone_id must be a single integer or NULL")
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose))
    stop("verbose must be TRUE or FALSE")

  no_result <- list(taxon_name = NA_character_, rank = NA_character_)

  # ---- Already at the coarsest rank: nothing to escalate to -------------------
  current_idx <- which(rank_system == current_rank)[1L]
  if (current_idx <= 1L) {
    return(no_result)
  }

  candidate_idx <- seq(current_idx - 1L, max(1L, current_idx - max_levels))

  # ---- Resolve full classification, primary then fallback backbone -----------
  verified <- NULL
  if (!is.null(backbone_id)) {
    verified <- tryCatch(
      verify_taxon_names(taxon_name, backbone_id = backbone_id),
      error = function(e) {
        warning(sprintf(
          "escalate_taxonomic_rank: backbone %d query failed: %s",
          as.integer(backbone_id), conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )
  }

  unresolved <- is.null(verified) || nrow(verified) == 0L ||
    is.na(verified$classification_path[1L])

  if (unresolved && !is.null(fallback_backbone_id) &&
      !identical(as.integer(fallback_backbone_id), as.integer(backbone_id))) {
    if (verbose) message(sprintf(
      "escalate_taxonomic_rank: primary backbone did not resolve \"%s\"; trying fallback backbone %d...",
      taxon_name, as.integer(fallback_backbone_id)
    ))
    verified <- tryCatch(
      verify_taxon_names(taxon_name, backbone_id = fallback_backbone_id),
      error = function(e) {
        warning(sprintf(
          "escalate_taxonomic_rank: fallback backbone %d query failed: %s",
          as.integer(fallback_backbone_id), conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )
  }

  if (is.null(verified) || nrow(verified) == 0L || is.na(verified$classification_path[1L])) {
    if (verbose) message(sprintf(
      "escalate_taxonomic_rank: could not resolve classification for \"%s\"; returning NA.",
      taxon_name
    ))
    return(no_result)
  }

  path  <- verified$classification_path[1L]
  ranks <- verified$classification_ranks[1L]

  # ---- Walk coarser ranks, up to max_levels steps, first hit wins ------------
  for (idx in candidate_idx) {
    candidate_rank <- rank_system[idx]
    candidate_name <- parse_classification_path(path, ranks, candidate_rank)
    if (!is.na(candidate_name) && nzchar(trimws(candidate_name))) {
      return(list(taxon_name = candidate_name, rank = candidate_rank))
    }
  }

  if (verbose) message(sprintf(
    "escalate_taxonomic_rank: no coarser rank resolved for \"%s\" within %d level(s).",
    taxon_name, as.integer(max_levels)
  ))
  no_result
}

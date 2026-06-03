# ==============================================================================
# unreferenced_candidates()
# ==============================================================================

#' Add unreferenced taxon placeholder rows to a match object
#'
#' Given a canonical match object (one row per `observation_id` x reference
#' accession), adds placeholder rows for taxon hypotheses absent from the
#' reference database:
#' \itemize{
#'   \item \code{"unreferenced_species"} — genus is represented in the
#'     reference but the species is not.
#'   \item \code{"unreferenced_genus"} — family is represented but the genus
#'     is not.
#'   \item \code{"unreferenced_family"} — optional catch-all (see
#'     \code{include_unreferenced_family}).
#' }
#'
#' Both placeholder rows are anchored on the best-scoring H1 candidate for
#' each observation (highest median \code{score_original} across accessions;
#' first row if no scores are present).  This is the same anchor convention
#' used by [evaluate_likelihoods()].
#'
#' The expanded data frame is passed to [assign_scores()] to obtain
#' \code{score_likelihood} values, or directly to [model_likelihoods()] for
#' the bivariate-normal (similarity) pathway.
#'
#' @param match_df Data frame. Canonical match object from
#'   \code{TaxaMatch::standardize_match_data()} or equivalent. Must contain
#'   \code{observation_id}, \code{taxon_name}, and \code{taxon_name_rank}.
#'   Taxonomy columns matching \code{rank_system} (e.g., \code{family},
#'   \code{genus}, \code{species}) are used to derive H2/H3 taxon names.
#'   A \code{score_original} column is optional; when present it identifies
#'   the best anchor candidate.
#' @param rank_system Character vector of rank names \strong{coarse to fine}
#'   (e.g., \code{c("family", "genus", "species")}).  When \code{NULL}
#'   (default), auto-detected from column names using
#'   \code{TaxaTools::extended_ranks}.  At least two ranks are required.
#' @param include_unreferenced_family Logical (default \code{FALSE}).  When
#'   \code{TRUE}, one \code{"unreferenced_family"} catch-all row is added per
#'   observation with all taxonomy columns set to \code{NA}.  Use when
#'   running [assign_scores()] without TaxaExpect priors (e.g., the LLM
#'   shortcut pathway) to absorb posterior mass from taxa outside all
#'   represented families.  Do \strong{not} set to \code{TRUE} when using
#'   TaxaExpect priors — the prior distribution already covers unrepresented
#'   families.
#'
#' @return A data frame with the same columns as \code{match_df}, plus
#'   \code{hypothesis_type} (\code{"specific_candidate"} for original rows;
#'   \code{"unreferenced_species"}, \code{"unreferenced_genus"}, or
#'   \code{"unreferenced_family"} for added rows).  Added rows have
#'   \code{score_original = NA} (and any other score columns set to \code{NA}).
#'
#' @seealso [assign_scores()], [model_likelihoods()], [compute_likelihoods()]
#'
#' @examples
#' \dontrun{
#' # Expand a match object before assign_scores()
#' hyp_df <- unreferenced_candidates(
#'   match_df,
#'   rank_system = c("family", "genus", "species")
#' )
#' table(hyp_df$hypothesis_type)
#' # specific_candidate  unreferenced_species  unreferenced_genus
#' }
#'
#' @importFrom TaxaTools create_taxon_names extended_ranks
#' @importFrom dplyr bind_rows
#' @importFrom stats median
#' @export
unreferenced_candidates <- function(match_df,
                                    rank_system                 = NULL,
                                    include_unreferenced_family = FALSE) {

  # ---- validate ---------------------------------------------------------------
  if (!is.data.frame(match_df))
    stop("`match_df` must be a data frame.", call. = FALSE)
  if (!is.logical(include_unreferenced_family) ||
      length(include_unreferenced_family) != 1L ||
      is.na(include_unreferenced_family))
    stop("`include_unreferenced_family` must be TRUE or FALSE.", call. = FALSE)

  names(match_df) <- tolower(names(match_df))

  required <- c("observation_id", "taxon_name", "taxon_name_rank")
  missing_cols <- setdiff(required, names(match_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("`match_df` is missing required column(s): %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)

  # ---- auto-detect rank_system ------------------------------------------------
  if (is.null(rank_system)) {
    canonical   <- TaxaTools::extended_ranks
    df_lower    <- tolower(names(match_df))
    found_lower <- intersect(canonical, df_lower)
    rank_system <- names(match_df)[match(found_lower, df_lower)]
    if (length(rank_system) < 2L)
      stop(
        "Could not auto-detect `rank_system` (need >= 2 rank columns). ",
        "Supply it explicitly, e.g. rank_system = c(\"family\", \"genus\", \"species\").",
        call. = FALSE
      )
    message(sprintf("unreferenced_candidates: detected rank_system: %s",
                    paste(rank_system, collapse = ", ")))
  } else {
    if (!is.character(rank_system) || length(rank_system) < 2L)
      stop("`rank_system` must be a character vector with at least 2 ranks.",
           call. = FALSE)
  }
  rank_cols <- tolower(rank_system)

  # ---- mark original rows as specific_candidate ------------------------------
  if (!"hypothesis_type" %in% names(match_df)) {
    match_df$hypothesis_type <- "specific_candidate"
  } else {
    is_na_ht <- is.na(match_df$hypothesis_type)
    if (any(is_na_ht))
      match_df$hypothesis_type[is_na_ht] <- "specific_candidate"
  }

  finest <- rank_cols[length(rank_cols)]
  second  <- if (length(rank_cols) >= 2L) rank_cols[length(rank_cols) - 1L] else NULL
  has_score <- "score_original" %in% names(match_df)

  # ---- per-observation: build H2, H3, (H4) rows ------------------------------
  obs_ids <- unique(match_df$observation_id[!is.na(match_df$observation_id)])
  n_extra_per_obs <- 2L + as.integer(include_unreferenced_family)
  extra_rows <- vector("list", length(obs_ids) * n_extra_per_obs)
  k <- 0L

  for (sid in obs_ids) {
    h1_rows <- match_df[
      !is.na(match_df$observation_id) &
      match_df$observation_id == sid &
      match_df$hypothesis_type == "specific_candidate", ,
      drop = FALSE
    ]
    if (nrow(h1_rows) == 0L) next

    # Anchor: taxon with highest median score_original (or first row)
    if (has_score && !all(is.na(h1_rows$score_original))) {
      by_taxon <- tapply(h1_rows$score_original, h1_rows$taxon_name,
                         function(x) stats::median(x, na.rm = TRUE))
      best_taxon <- names(which.max(by_taxon))
      anchor_row <- h1_rows[h1_rows$taxon_name == best_taxon, , drop = FALSE][1L, ]
    } else {
      anchor_row <- h1_rows[1L, , drop = FALSE]
    }

    existing_rank_cols <- intersect(rank_cols, names(anchor_row))

    # H2: unreferenced_species — finest rank → NA
    if (finest %in% names(anchor_row)) {
      row_h2 <- anchor_row
      row_h2[[finest]] <- NA_character_
      ec <- intersect(rank_cols, names(row_h2))
      row_h2 <- TaxaTools::create_taxon_names(row_h2, ec)
      row_h2$hypothesis_type <- "unreferenced_species"
      if (has_score) row_h2$score_original <- NA_real_
      k <- k + 1L
      extra_rows[[k]] <- row_h2
    }

    # H3: unreferenced_genus — two finest ranks → NA
    if (!is.null(second) && second %in% names(anchor_row)) {
      row_h3 <- anchor_row
      if (finest %in% names(row_h3))  row_h3[[finest]]  <- NA_character_
      row_h3[[second]] <- NA_character_
      ec <- intersect(rank_cols, names(row_h3))
      row_h3 <- TaxaTools::create_taxon_names(row_h3, ec)
      row_h3$hypothesis_type <- "unreferenced_genus"
      if (has_score) row_h3$score_original <- NA_real_
      k <- k + 1L
      extra_rows[[k]] <- row_h3
    }

    # H4: unreferenced_family — all rank columns → NA
    if (include_unreferenced_family) {
      row_h4 <- anchor_row
      for (rc in rank_cols) {
        if (rc %in% names(row_h4)) row_h4[[rc]] <- NA_character_
      }
      row_h4$taxon_name      <- NA_character_
      row_h4$taxon_name_rank <- NA_character_
      row_h4$hypothesis_type <- "unreferenced_family"
      if (has_score) row_h4$score_original <- NA_real_
      k <- k + 1L
      extra_rows[[k]] <- row_h4
    }
  }

  if (k > 0L) {
    dplyr::bind_rows(match_df, extra_rows[seq_len(k)])
  } else {
    match_df
  }
}

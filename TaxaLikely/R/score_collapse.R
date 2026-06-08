# ==============================================================================
# detect_score_collapse()  /  restore_suppressed_candidates()
# ==============================================================================
# Motivation: some pipelines (e.g. BLAST with a "100% rule") return only the
# top-scoring candidate(s) and silently drop lower-scoring matches.  When a
# sequence has a perfect reference match, all sub-100% congeners are suppressed.
# evaluate_likelihoods() then sees only one H1 candidate and falls back to
# singleton mode -- the gap feature is uninformative and referenced alternatives
# are invisible.
#
# detect_score_collapse() diagnoses whether this is happening.
# restore_suppressed_candidates() appends the missing congeners from the
# reference database so that evaluate_likelihoods() can evaluate them properly.


#' Detect score-collapse pipeline rules in a match object
#'
#' Inspects a match object for evidence that an upstream tool (e.g. BLAST with
#' a 100\% rule, or a top-hit-only classifier) suppressed lower-scoring
#' candidates.  Two patterns are recognised:
#'
#' \describe{
#'   \item{`"perfect_only"`}{Observations with exactly one candidate whose
#'     score equals the maximum possible value (100 for percent-identity; 1.0
#'     for similarity). The pipeline appears to have dropped all sub-perfect
#'     matches.}
#'   \item{`"max_score_ties"`}{Observations with multiple candidates that all
#'     share the same (maximum) score -- i.e. only tied top-hits were returned.}
#' }
#'
#' Both patterns may coexist (\code{type = "both"}).
#'
#' @param match_obj Data frame. Standardised match object containing at least
#'   \code{observation_id_col} and \code{score_col}.
#' @param score_col Character. Name of the score column (default
#'   \code{"score_original"}).
#' @param observation_id_col Character. Name of the observation identifier
#'   column (default \code{"observation_id"}).
#' @param perfect_threshold Numeric or \code{NULL}. Score value that defines a
#'   perfect match.  Auto-detected when \code{NULL}: 100 for 0--100 scale,
#'   1.0 for 0--1 scale.
#' @param min_fraction Numeric. Minimum fraction of observations that must show
#'   a pattern for it to be flagged as \code{rule_detected = TRUE} (default
#'   \code{0.05}).  Prevents single-observation artefacts from triggering a
#'   detection.
#'
#' @return A named list:
#' \describe{
#'   \item{`rule_detected`}{Logical.}
#'   \item{`type`}{Character: \code{"perfect_only"}, \code{"max_score_ties"},
#'     \code{"both"}, or \code{"none"}.}
#'   \item{`n_total`}{Integer. Unique observations in \code{match_obj}.}
#'   \item{`n_perfect_only`}{Integer. Singleton observations at perfect score.}
#'   \item{`n_ties_only`}{Integer. Multi-candidate observations where all
#'     candidates share the same score.}
#'   \item{`fraction_perfect_only`}{Numeric.}
#'   \item{`fraction_ties_only`}{Numeric.}
#'   \item{`example_observations`}{Character. Up to 5 affected observation IDs.}
#' }
#'
#' @examples
#' m <- data.frame(
#'   observation_id = c("obs1", "obs2", "obs3", "obs3"),
#'   score_original = c(100, 100, 98, 97),
#'   taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D")
#' )
#' detect_score_collapse(m)
#'
#' @seealso [restore_suppressed_candidates()]
#' @importFrom utils head
#' @export
detect_score_collapse <- function(match_obj,
                                   score_col          = "score_original",
                                   observation_id_col = "observation_id",
                                   perfect_threshold  = NULL,
                                   min_fraction       = 0.05) {

  if (!is.data.frame(match_obj))
    stop("detect_score_collapse: 'match_obj' must be a data frame.", call. = FALSE)
  if (!score_col %in% names(match_obj))
    stop(sprintf("detect_score_collapse: score column '%s' not found.", score_col),
         call. = FALSE)
  if (!observation_id_col %in% names(match_obj))
    stop(sprintf("detect_score_collapse: observation ID column '%s' not found.",
                 observation_id_col), call. = FALSE)

  scores  <- match_obj[[score_col]]
  obs_ids <- match_obj[[observation_id_col]]

  if (is.null(perfect_threshold))
    perfect_threshold <- if (max(scores, na.rm = TRUE) > 1) 100 else 1.0

  # per-observation summary using base tapply
  per_obs <- tapply(seq_len(nrow(match_obj)), obs_ids, function(idx) {
    s  <- scores[idx]
    s  <- s[!is.na(s)]
    n  <- length(idx)
    mx <- if (length(s) > 0L) max(s) else NA_real_
    list(
      n         = n,
      singleton = (n == 1L),
      perfect   = isTRUE(!is.na(mx) && mx >= perfect_threshold),
      all_same  = (n > 1L) && length(s) > 0L && (length(unique(s)) == 1L)
    )
  }, simplify = FALSE)

  n_total <- length(per_obs)

  is_perfect_only <- vapply(per_obs,
                            function(x) isTRUE(x$singleton && x$perfect),
                            logical(1L))
  is_ties_only    <- vapply(per_obs,
                            function(x) isTRUE(x$all_same),
                            logical(1L))

  n_perfect <- sum(is_perfect_only)
  n_ties    <- sum(is_ties_only)
  frac_perf <- n_perfect / n_total
  frac_ties <- n_ties    / n_total

  has_perfect <- frac_perf >= min_fraction
  has_ties    <- frac_ties >= min_fraction

  type <- if (has_perfect && has_ties) "both"           else
          if (has_perfect)             "perfect_only"   else
          if (has_ties)                "max_score_ties" else "none"

  affected_ids <- names(which(is_perfect_only | is_ties_only))

  list(
    rule_detected         = has_perfect || has_ties,
    type                  = type,
    n_total               = n_total,
    n_perfect_only        = n_perfect,
    n_ties_only           = n_ties,
    fraction_perfect_only = round(frac_perf, 4),
    fraction_ties_only    = round(frac_ties, 4),
    example_observations  = head(affected_ids, 5L)
  )
}


#' Restore candidates suppressed by top-hit pipeline rules
#'
#' When an upstream tool (e.g. BLAST with a 100\% rule) returns only the
#' single highest-scoring candidate, other species sharing that genus in the
#' reference database are silently suppressed.  This function identifies
#' affected observations and appends rows for missing same-genus congeners so
#' that [evaluate_likelihoods()] can evaluate them as real alternatives rather
#' than as generic unreferenced hypotheses.
#'
#' Restored rows receive:
#' \itemize{
#'   \item An imputed score derived from \code{score_rule}.
#'   \item \code{hypothesis_type = "suppressed_candidate"}.
#'   \item \code{accession} prefixed with \code{"RESTORED_"} (when present).
#'   \item All taxonomy columns populated from \code{reference_df}.
#'   \item \code{coverage = NA} (when present in \code{match_obj}).
#' }
#'
#' Use [detect_score_collapse()] first to confirm that a collapse rule is
#' present before calling this function.
#'
#' @param match_obj Data frame. Standardised match object.
#' @param reference_df Data frame. Reference database (output of
#'   [fetch_reference_sequences()], [read_reference_fasta()], or
#'   [read_crabs_output()]).  Must contain genus and species columns matching
#'   \code{rank_system}.
#' @param rank_system Character vector or \code{NULL}. Taxonomic rank columns
#'   coarse-to-fine (e.g. \code{c("family","genus","species")}).  Auto-detected
#'   from \code{match_obj} when \code{NULL}.
#' @param score_col Character. Score column name (default
#'   \code{"score_original"}).
#' @param observation_id_col Character. Observation ID column name (default
#'   \code{"observation_id"}).
#' @param score_rule Numeric or \code{"sub_max"}.  Score to assign restored
#'   candidates.  \code{"sub_max"} (default) sets the imputed score to the H1
#'   candidate's score minus a small delta (1.0 on a 0--100 scale; 0.01 on a
#'   0--1 scale).  Pass a fixed numeric to override.
#' @param perfect_only Logical (default \code{TRUE}).  When \code{TRUE}, only
#'   singleton observations whose score equals the perfect threshold are
#'   restored.  Set to \code{FALSE} to restore all singleton observations.
#' @param perfect_threshold Numeric or \code{NULL}.  Auto-detected when
#'   \code{NULL} (100 for 0--100 scale; 1.0 for 0--1 scale).
#' @param min_score Numeric or \code{NULL}. Restored rows whose imputed score
#'   falls below this value are dropped.  Default \code{NULL} (no floor).
#' @param max_per_obs Integer. Maximum restored candidates per observation
#'   (default \code{10L}).  Prevents large genera from inflating the data frame.
#' @param verbose Logical. Emit a summary message (default \code{TRUE}).
#'
#' @return The input \code{match_obj} with additional rows for suppressed
#'   congeners.  A logical column \code{is_restored} is added (\code{FALSE}
#'   for original rows, \code{TRUE} for restored rows).
#'
#' @examples
#' \dontrun{
#' collapse <- detect_score_collapse(match_obj)
#' if (collapse$rule_detected) {
#'   match_obj <- restore_suppressed_candidates(match_obj, reference_df)
#' }
#' lik_result <- evaluate_likelihoods(match_obj, model_params = lik_model)
#' }
#'
#' @seealso [detect_score_collapse()], [evaluate_likelihoods()]
#' @importFrom dplyr bind_rows
#' @importFrom TaxaTools create_taxon_names extended_ranks
#' @export
restore_suppressed_candidates <- function(match_obj,
                                           reference_df,
                                           rank_system        = NULL,
                                           score_col          = "score_original",
                                           observation_id_col = "observation_id",
                                           score_rule         = "sub_max",
                                           perfect_only       = TRUE,
                                           perfect_threshold  = NULL,
                                           min_score          = NULL,
                                           max_per_obs        = 10L,
                                           verbose            = TRUE) {

  # ---- validate ---------------------------------------------------------------
  if (!is.data.frame(match_obj))
    stop("restore_suppressed_candidates: 'match_obj' must be a data frame.",
         call. = FALSE)
  if (!is.data.frame(reference_df))
    stop("restore_suppressed_candidates: 'reference_df' must be a data frame.",
         call. = FALSE)
  if (!score_col %in% names(match_obj))
    stop(sprintf("restore_suppressed_candidates: score column '%s' not found.",
                 score_col), call. = FALSE)
  if (!observation_id_col %in% names(match_obj))
    stop(sprintf("restore_suppressed_candidates: observation ID column '%s' not found.",
                 observation_id_col), call. = FALSE)
  if (!is.numeric(score_rule) && !identical(score_rule, "sub_max"))
    stop("restore_suppressed_candidates: 'score_rule' must be numeric or \"sub_max\".",
         call. = FALSE)
  if (!is.logical(perfect_only) || length(perfect_only) != 1L || is.na(perfect_only))
    stop("restore_suppressed_candidates: 'perfect_only' must be TRUE or FALSE.",
         call. = FALSE)

  max_per_obs <- as.integer(max_per_obs)

  # ---- auto-detect rank_system ------------------------------------------------
  if (is.null(rank_system)) {
    canonical   <- TaxaTools::extended_ranks
    df_lower    <- tolower(names(match_obj))
    found_lower <- intersect(canonical, df_lower)
    rank_system <- names(match_obj)[match(found_lower, df_lower)]
    if (length(rank_system) < 2L)
      stop("restore_suppressed_candidates: could not auto-detect rank_system. ",
           "Supply it explicitly, e.g. rank_system = c(\"family\",\"genus\",\"species\").",
           call. = FALSE)
    message(sprintf("restore_suppressed_candidates: detected rank_system: %s",
                    paste(rank_system, collapse = ", ")))
  } else {
    if (!is.character(rank_system) || length(rank_system) < 2L)
      stop("restore_suppressed_candidates: 'rank_system' must be a character vector ",
           "with at least 2 ranks.", call. = FALSE)
  }

  genus_col   <- rank_system[length(rank_system) - 1L]
  species_col <- rank_system[length(rank_system)]

  for (col in c(genus_col, species_col)) {
    if (!col %in% names(match_obj))
      stop(sprintf("restore_suppressed_candidates: column '%s' not found in match_obj.",
                   col), call. = FALSE)
    if (!col %in% names(reference_df))
      stop(sprintf("restore_suppressed_candidates: column '%s' not found in reference_df.",
                   col), call. = FALSE)
  }

  # ---- scale detection --------------------------------------------------------
  all_scores <- match_obj[[score_col]]
  max_score_global <- max(all_scores, na.rm = TRUE)
  score_delta <- if (max_score_global > 1) 1.0 else 0.01

  if (is.null(perfect_threshold))
    perfect_threshold <- if (max_score_global > 1) 100 else 1.0

  # ---- identify singleton observations ----------------------------------------
  obs_ids        <- match_obj[[observation_id_col]]
  n_per_obs      <- tapply(obs_ids, obs_ids, length)
  singleton_ids  <- names(n_per_obs)[n_per_obs == 1L]

  if (perfect_only) {
    # restrict to singletons where score >= perfect_threshold
    singleton_scores <- vapply(singleton_ids, function(id) {
      s <- match_obj[[score_col]][obs_ids == id]
      if (length(s) == 0L || all(is.na(s))) NA_real_ else max(s, na.rm = TRUE)
    }, numeric(1L))
    singleton_ids <- singleton_ids[!is.na(singleton_scores) &
                                     singleton_scores >= perfect_threshold]
  }

  if (length(singleton_ids) == 0L) {
    if (verbose)
      message("restore_suppressed_candidates: no qualifying singleton observations found; ",
              "nothing to restore.")
    match_obj$is_restored <- FALSE
    return(match_obj)
  }

  # ---- reference lookup: genus -> unique species rows -------------------------
  ref_by_genus <- split(reference_df, reference_df[[genus_col]])

  # ---- mark original hypothesis_type -----------------------------------------
  if (!"hypothesis_type" %in% names(match_obj))
    match_obj$hypothesis_type <- "specific_candidate"

  # ---- build restored rows ----------------------------------------------------
  restored_list  <- vector("list", length(singleton_ids))
  n_restored_obs  <- 0L
  n_restored_rows <- 0L

  for (i in seq_along(singleton_ids)) {
    obs_id   <- singleton_ids[i]
    h1_row   <- match_obj[obs_ids == obs_id, , drop = FALSE]
    h1_genus <- h1_row[[genus_col]]
    h1_score <- h1_row[[score_col]]

    if (is.na(h1_genus) || !h1_genus %in% names(ref_by_genus)) next

    # imputed score for all restored candidates from this observation
    imputed_score <- if (is.numeric(score_rule)) {
      score_rule
    } else {
      h1_score - score_delta
    }

    if (!is.null(min_score) && !is.na(imputed_score) && imputed_score < min_score) next

    ref_genus_rows <- ref_by_genus[[h1_genus]]
    h1_species     <- h1_row[[species_col]]
    other_species  <- unique(ref_genus_rows[[species_col]])
    other_species  <- other_species[!is.na(other_species) & other_species != h1_species]

    if (length(other_species) == 0L) next
    if (length(other_species) > max_per_obs)
      other_species <- other_species[seq_len(max_per_obs)]

    rows_for_obs <- vector("list", length(other_species))

    for (j in seq_along(other_species)) {
      sp      <- other_species[j]
      ref_row <- ref_genus_rows[ref_genus_rows[[species_col]] == sp, , drop = FALSE][1L, ]

      new_row <- h1_row

      # overwrite taxonomy columns from reference
      for (rc in rank_system) {
        if (rc %in% names(ref_row) && rc %in% names(new_row))
          new_row[[rc]] <- ref_row[[rc]]
      }

      # re-derive taxon_name / taxon_name_rank from updated taxonomy
      if ("taxon_name" %in% names(new_row)) {
        tax_cols_present <- intersect(rank_system, names(new_row))
        new_row <- TaxaTools::create_taxon_names(new_row, tax_cols_present)
      }

      # score
      new_row[[score_col]] <- imputed_score

      # accession
      if ("accession" %in% names(new_row)) {
        ref_acc <- if ("accession" %in% names(ref_row)) ref_row[["accession"]] else NA_character_
        new_row[["accession"]] <- paste0("RESTORED_", ref_acc)
      }

      # clear coverage (alignment quality is unknown for restored candidates)
      if ("coverage" %in% names(new_row)) new_row[["coverage"]] <- NA_real_

      # mark type
      new_row[["hypothesis_type"]] <- "suppressed_candidate"

      rows_for_obs[[j]] <- new_row
    }

    restored_list[[i]] <- dplyr::bind_rows(rows_for_obs)
    n_restored_obs  <- n_restored_obs  + 1L
    n_restored_rows <- n_restored_rows + length(other_species)
  }

  restored_df <- dplyr::bind_rows(restored_list)

  if (is.null(restored_df) || nrow(restored_df) == 0L) {
    if (verbose)
      message("restore_suppressed_candidates: no same-genus congeners found in ",
              "reference_df for any qualifying observation.")
    match_obj$is_restored <- FALSE
    return(match_obj)
  }

  match_obj$is_restored   <- FALSE
  restored_df$is_restored <- TRUE

  result <- dplyr::bind_rows(match_obj, restored_df)

  if (verbose)
    message(sprintf(
      "restore_suppressed_candidates: added %d candidate rows across %d observations (score_rule = %s).",
      n_restored_rows, n_restored_obs,
      if (is.numeric(score_rule)) as.character(score_rule) else score_rule
    ))

  result
}

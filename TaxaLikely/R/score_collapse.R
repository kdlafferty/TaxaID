# ==============================================================================
# detect_suppressed_candidates()  /  restore_suppressed_candidates()
# ==============================================================================
# Motivation: many pipelines suppress lower-scoring candidates from the match
# object, making referenced alternatives invisible to evaluate_likelihoods().
# Three pipeline rules are recognised and corrected:
#
#   Rule 1 -"perfect_only":  when >=1 candidate scores at or above
#     perfect_threshold, all sub-threshold candidates are dropped.  The
#     observation may have multiple rows (ties at the threshold) but never a
#     row below it.  (Example: Jonah Ventures 100% rule.)
#
#   Rule 2 -"max_score_ties": only tied-top candidates are returned; nothing
#     below the per-observation maximum is retained.  Multi-row observations
#     therefore show zero within-observation score variance.
#
#   Rule 3 -"best_only": each observation has exactly one row regardless of
#     score value.  Arises from top-1 classifiers, pre-computed consensus
#     assignments, or pipelines that report a single best match.
#
# detect_suppressed_candidates() diagnoses which (if any) rule is active.
# restore_suppressed_candidates() appends same-genus congeners from the
# reference database so that evaluate_likelihoods() (or assign_scores) can
# evaluate them as real alternatives.


#' Detect pipeline rules that suppress candidate rows in a match object
#'
#' Inspects a match object for evidence that an upstream tool suppressed
#' lower-scoring candidates.  Three patterns are recognised:
#'
#' \describe{
#'   \item{`"perfect_only"`}{Among observations where at least one candidate
#'     scores at or above \code{perfect_threshold}, none also contains a row
#'     below that threshold.  Typical cause: a 100-percent rule that drops all
#'     sub-perfect hits when a perfect match exists.}
#'   \item{`"max_score_ties"`}{Multi-row observations show zero within-
#'     observation score variance -only tied-top candidates were returned.}
#'   \item{`"best_only"`}{Essentially all observations have exactly one
#'     candidate row, indicating a top-1 pipeline, pre-computed consensus, or
#'     absence of a score column.}
#' }
#'
#' Detection is conservative: a rule is flagged only when the observed pattern
#' is present in at least \code{purity_threshold} of qualifying observations.
#'
#' @param match_obj Data frame. Standardised match object containing at least
#'   \code{observation_id_col}.  \code{score_col} is optional; Rules 1 and 2
#'   are skipped when it is absent.
#' @param score_col Character. Name of the score column (default
#'   \code{"score_original"}).
#' @param observation_id_col Character. Name of the observation ID column
#'   (default \code{"observation_id"}).
#' @param perfect_threshold Numeric. Score at or above which a candidate is
#'   considered a "perfect" match for Rule 1 detection (default \code{100}).
#'   Set to 95 for pipelines that enforce a 95-percent identity floor, for example.
#' @param purity_threshold Numeric in (0, 1]. Fraction of qualifying
#'   observations that must exhibit the pattern for the rule to be flagged
#'   (default \code{0.99}).  A high value reduces false positives from
#'   rounding artefacts.
#' @param singleton_threshold Numeric in (0, 1]. Fraction of all observations
#'   that must be singletons (1 row) for Rule 3 to be flagged (default
#'   \code{0.98}).
#'
#' @return A named list:
#' \describe{
#'   \item{`rule_detected`}{Logical. \code{TRUE} if any rule is flagged.}
#'   \item{`rules`}{Character vector of flagged rule names (may be empty).}
#'   \item{`perfect_only`}{Logical.}
#'   \item{`max_score_ties`}{Logical.}
#'   \item{`best_only`}{Logical.}
#'   \item{`has_score_col`}{Logical. Whether \code{score_col} was found.}
#'   \item{`n_total`}{Integer. Unique observations.}
#'   \item{`n_perfect_obs`}{Integer. Observations with >=1 score >=
#'     \code{perfect_threshold}.}
#'   \item{`purity_perfect`}{Numeric. Fraction of perfect-obs that are pure
#'     (no sub-threshold rows).}
#'   \item{`n_multi_obs`}{Integer. Observations with >1 row.}
#'   \item{`purity_ties`}{Numeric. Fraction of multi-row obs with uniform
#'     scores.}
#'   \item{`frac_singleton`}{Numeric. Fraction of obs that are singletons.}
#'   \item{`example_observations`}{Character. Up to 5 affected observation IDs.}
#' }
#'
#' @examples
#' m <- data.frame(
#'   observation_id = c("obs1", "obs1", "obs2"),
#'   score_original = c(100, 100, 99),
#'   taxon_name     = c("Sp_A", "Sp_B", "Sp_C")
#' )
#' detect_suppressed_candidates(m)
#'
#' @seealso [restore_suppressed_candidates()]
#' @importFrom utils head
#' @export
detect_suppressed_candidates <- function(match_obj,
                                          score_col           = "score_original",
                                          observation_id_col  = "observation_id",
                                          perfect_threshold   = 100,
                                          purity_threshold    = 0.99,
                                          singleton_threshold = 0.98) {

  if (!is.data.frame(match_obj))
    stop("detect_suppressed_candidates: 'match_obj' must be a data frame.",
         call. = FALSE)
  if (!observation_id_col %in% names(match_obj))
    stop(sprintf("detect_suppressed_candidates: column '%s' not found.",
                 observation_id_col), call. = FALSE)

  has_score <- score_col %in% names(match_obj)
  obs_ids   <- match_obj[[observation_id_col]]

  per_obs <- tapply(seq_len(nrow(match_obj)), obs_ids, function(idx) {
    n  <- length(idx)
    if (has_score) {
      s  <- match_obj[[score_col]][idx]
      s  <- s[!is.na(s)]
      mx <- if (length(s) > 0L) max(s) else NA_real_
      list(
        n             = n,
        max_score     = mx,
        has_perfect   = !is.na(mx) && mx >= perfect_threshold,
        is_pure_perfect = !is.na(mx) && mx >= perfect_threshold &&
                          (length(s) == 0L || min(s) >= perfect_threshold),
        all_same      = (n > 1L) && length(s) > 1L &&
                        length(unique(round(s, 8))) == 1L
      )
    } else {
      list(n = n, max_score = NA_real_, has_perfect = FALSE,
           is_pure_perfect = FALSE, all_same = FALSE)
    }
  }, simplify = FALSE)

  n_total <- length(per_obs)

  # ---- Rule 1: perfect_only ---------------------------------------------------
  n_perfect_obs  <- sum(vapply(per_obs, function(x) x$has_perfect, logical(1L)))
  n_pure_perfect <- sum(vapply(per_obs, function(x) x$is_pure_perfect, logical(1L)))
  purity_perfect <- if (n_perfect_obs > 0L) n_pure_perfect / n_perfect_obs else 0
  perfect_only   <- has_score && n_perfect_obs > 0L &&
                    purity_perfect >= purity_threshold

  # ---- Rule 2: max_score_ties -------------------------------------------------
  n_multi    <- sum(vapply(per_obs, function(x) x$n > 1L, logical(1L)))
  n_ties     <- sum(vapply(per_obs, function(x) x$all_same, logical(1L)))
  purity_ties <- if (n_multi > 0L) n_ties / n_multi else 0
  max_score_ties <- has_score && n_multi > 0L && purity_ties >= purity_threshold

  # ---- Rule 3: best_only ------------------------------------------------------
  n_singletons   <- sum(vapply(per_obs, function(x) x$n == 1L, logical(1L)))
  frac_singleton <- n_singletons / n_total
  best_only      <- frac_singleton >= singleton_threshold

  # ---- collect examples -------------------------------------------------------
  affected_ids <- character(0L)
  if (perfect_only)
    affected_ids <- c(affected_ids,
                      names(which(vapply(per_obs,
                                         function(x) x$is_pure_perfect, logical(1L)))))
  if (max_score_ties)
    affected_ids <- c(affected_ids,
                      names(which(vapply(per_obs,
                                         function(x) x$all_same, logical(1L)))))
  if (best_only)
    affected_ids <- c(affected_ids, names(per_obs))
  affected_ids <- unique(affected_ids)

  rules <- character(0L)
  if (perfect_only)    rules <- c(rules, "perfect_only")
  if (max_score_ties)  rules <- c(rules, "max_score_ties")
  if (best_only)       rules <- c(rules, "best_only")

  list(
    rule_detected   = length(rules) > 0L,
    rules           = rules,
    perfect_only    = perfect_only,
    max_score_ties  = max_score_ties,
    best_only       = best_only,
    has_score_col   = has_score,
    n_total         = n_total,
    n_perfect_obs   = n_perfect_obs,
    purity_perfect  = round(purity_perfect,  4),
    n_multi_obs     = n_multi,
    purity_ties     = round(purity_ties, 4),
    frac_singleton  = round(frac_singleton, 4),
    example_observations = head(affected_ids, 5L)
  )
}


#' Restore candidates suppressed by top-hit pipeline rules
#'
#' For observations affected by a score-suppression pipeline rule (detected by
#' [detect_suppressed_candidates()]), finds same-genus congeners in
#' \code{reference_df} and appends them as \code{hypothesis_type =
#' "suppressed_candidate"} rows so that [evaluate_likelihoods()] or
#' [assign_scores()] can evaluate them as real alternatives.
#'
#' \strong{Which observations are targeted:}
#' \itemize{
#'   \item \strong{Rule 1 (perfect_only) only}: observations where all scores
#'     >= \code{perfect_threshold}.
#'   \item \strong{Rule 2 (max_score_ties) or Rule 3 (best_only)}: all
#'     observations, since even singletons may have had candidates suppressed.
#' }
#'
#' \strong{Score imputation:}
#' \itemize{
#'   \item When a score column is present: restored rows receive
#'     \code{max_score_in_obs - delta} (auto-scaled: \code{delta} on the
#'     0-100 scale, \code{delta / 100} on the 0-1 scale).
#'   \item When no score column exists (Rule 3, no-score pathway): a synthetic
#'     \code{score_original} column is created.  Original rows receive
#'     \code{1.0}; restored rows receive \code{1.0 - delta / 100}.  Pass the
#'     result to \code{assign_scores(score_type = "direct")} rather than the
#'     bivariate-normal pipeline.
#' }
#'
#' @param match_obj Data frame. Standardised match object.
#' @param reference_df Data frame. Reference database (output of
#'   [fetch_reference_sequences()], [read_reference_fasta()], or
#'   [read_crabs_output()]).  Must contain the same genus/species columns as
#'   \code{match_obj}.
#' @param detected List or \code{NULL}. Output of
#'   [detect_suppressed_candidates()].  When \code{NULL} (default),
#'   detection is run internally using \code{perfect_threshold},
#'   \code{purity_threshold}, and \code{singleton_threshold}.
#' @param rank_system Character vector or \code{NULL}. Rank columns
#'   coarse-to-fine (e.g. \code{c("family","genus","species")}).
#'   Auto-detected when \code{NULL}.
#' @param score_col Character. Score column name (default
#'   \code{"score_original"}).
#' @param observation_id_col Character. Observation ID column name (default
#'   \code{"observation_id"}).
#' @param perfect_threshold Numeric. Passed to [detect_suppressed_candidates()]
#'   when \code{detected = NULL} (default \code{100}).
#' @param purity_threshold Numeric. Passed to detection when \code{detected =
#'   NULL} (default \code{0.99}).
#' @param singleton_threshold Numeric. Passed to detection when \code{detected
#'   = NULL} (default \code{0.98}).
#' @param delta Numeric. Score gap between H1 score and imputed score for
#'   restored candidates (default \code{0.5}, on the 0-100 scale).
#'   Auto-scaled to 0-1 when scores are on the 0-1 scale.  Also used as
#'   \code{delta / 100} for the synthetic score in the no-score pathway.
#' @param max_per_obs Integer. Maximum restored candidates per observation
#'   (default \code{10L}).
#' @param verbose Logical. Emit summary messages (default \code{TRUE}).
#'
#' @return \code{match_obj} with additional rows for suppressed congeners.
#'   New columns added:
#'   \describe{
#'     \item{`is_restored`}{\code{FALSE} for original rows, \code{TRUE} for
#'       restored rows.}
#'     \item{`score_original`}{Created (synthetic) when the no-score pathway
#'       is triggered and the column was absent.}
#'   }
#'
#' @examples
#' \dontrun{
#' detected <- detect_suppressed_candidates(match_obj)
#' if (detected$rule_detected) {
#'   match_obj <- restore_suppressed_candidates(match_obj, reference_df,
#'                                               detected = detected)
#' }
#' # With scores: continue to evaluate_likelihoods()
#' # No-score:    continue to assign_scores(score_type = "direct")
#' }
#'
#' @seealso [detect_suppressed_candidates()], [evaluate_likelihoods()],
#'   [assign_scores()]
#' @importFrom dplyr bind_rows
#' @importFrom TaxaTools create_taxon_names extended_ranks
#' @export
restore_suppressed_candidates <- function(match_obj,
                                           reference_df,
                                           detected            = NULL,
                                           rank_system         = NULL,
                                           score_col           = "score_original",
                                           observation_id_col  = "observation_id",
                                           perfect_threshold   = 100,
                                           purity_threshold    = 0.99,
                                           singleton_threshold = 0.98,
                                           delta               = 0.5,
                                           max_per_obs         = 10L,
                                           verbose             = TRUE) {

  # ---- validate ---------------------------------------------------------------
  if (!is.data.frame(match_obj))
    stop("restore_suppressed_candidates: 'match_obj' must be a data frame.",
         call. = FALSE)
  if (!is.data.frame(reference_df))
    stop("restore_suppressed_candidates: 'reference_df' must be a data frame.",
         call. = FALSE)
  if (!observation_id_col %in% names(match_obj))
    stop(sprintf("restore_suppressed_candidates: column '%s' not found.",
                 observation_id_col), call. = FALSE)

  max_per_obs <- as.integer(max_per_obs)

  # ---- run detection if not supplied ------------------------------------------
  if (is.null(detected)) {
    detected <- detect_suppressed_candidates(
      match_obj,
      score_col           = score_col,
      observation_id_col  = observation_id_col,
      perfect_threshold   = perfect_threshold,
      purity_threshold    = purity_threshold,
      singleton_threshold = singleton_threshold
    )
  }

  if (!detected$rule_detected) {
    if (verbose)
      message("restore_suppressed_candidates: no suppression rules detected; ",
              "nothing to restore.")
    match_obj$is_restored <- FALSE
    return(match_obj)
  }

  if (verbose)
    message(sprintf("restore_suppressed_candidates: rule(s) detected: %s.",
                    paste(detected$rules, collapse = ", ")))

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
  }

  genus_col   <- rank_system[length(rank_system) - 1L]
  species_col <- rank_system[length(rank_system)]

  for (col in c(genus_col, species_col)) {
    if (!col %in% names(match_obj))
      stop(sprintf("restore_suppressed_candidates: column '%s' not found in match_obj.", col),
           call. = FALSE)
    if (!col %in% names(reference_df))
      stop(sprintf("restore_suppressed_candidates: column '%s' not found in reference_df.", col),
           call. = FALSE)
  }

  # ---- score column handling --------------------------------------------------
  has_score  <- score_col %in% names(match_obj)
  no_score_path <- FALSE

  if (!has_score || all(is.na(match_obj[[score_col]]))) {
    # No-score pathway: create synthetic score column
    no_score_path <- TRUE
    delta_01 <- delta / 100   # e.g. 0.5 -> 0.005
    if (!has_score) match_obj[[score_col]] <- NA_real_
    # Mark original rows with synthetic H1 score = 1.0
    match_obj[[score_col]] <- 1.0
    if (verbose)
      message(sprintf(
        "restore_suppressed_candidates: no score column -creating synthetic scores ",
        "(H1 = 1.0, restored = %.4f). Use assign_scores(score_type = \"direct\") downstream.",
        1.0 - delta_01
      ))
    score_delta <- delta_01
  } else {
    # Scale-detect: 0-100 vs 0-1
    max_score_global <- max(match_obj[[score_col]], na.rm = TRUE)
    score_delta <- if (max_score_global > 1) delta else delta / 100
  }

  # ---- determine which observations to target ---------------------------------
  obs_ids    <- match_obj[[observation_id_col]]
  all_obs    <- unique(obs_ids)
  n_per_obs  <- table(obs_ids)

  if (detected$best_only || detected$max_score_ties) {
    # Rules 2 & 3: all observations get restored candidates
    target_obs <- all_obs
  } else {
    # Rule 1 only: target observations where ALL scores >= perfect_threshold
    target_obs <- vapply(all_obs, function(id) {
      idx <- which(obs_ids == id)
      s   <- match_obj[[score_col]][idx]
      s   <- s[!is.na(s)]
      length(s) > 0L && min(s) >= perfect_threshold
    }, logical(1L))
    target_obs <- all_obs[target_obs]
  }

  if (length(target_obs) == 0L) {
    if (verbose)
      message("restore_suppressed_candidates: no qualifying observations found.")
    match_obj$is_restored <- FALSE
    return(match_obj)
  }

  # ---- mark hypothesis_type for original rows ---------------------------------
  if (!"hypothesis_type" %in% names(match_obj))
    match_obj$hypothesis_type <- "specific_candidate"

  # ---- reference lookup: genus -> unique species rows -------------------------
  ref_by_genus <- split(reference_df, reference_df[[genus_col]])

  # ---- build restored rows ----------------------------------------------------
  restored_list   <- vector("list", length(target_obs))
  n_restored_obs  <- 0L
  n_restored_rows <- 0L

  for (i in seq_along(target_obs)) {
    obs_id   <- target_obs[i]
    obs_mask <- obs_ids == obs_id
    obs_rows <- match_obj[obs_mask, , drop = FALSE]

    # Genus of anchor (best-scoring or first row)
    sc_vec    <- obs_rows[[score_col]]
    anchor_idx <- if (any(!is.na(sc_vec))) which.max(sc_vec) else 1L
    anchor_row <- obs_rows[anchor_idx, , drop = FALSE]
    h1_genus   <- anchor_row[[genus_col]]
    h1_score   <- anchor_row[[score_col]]

    if (is.na(h1_genus) || !h1_genus %in% names(ref_by_genus)) next

    # Imputed score for restored candidates
    imputed_score <- if (no_score_path) {
      1.0 - delta_01
    } else {
      max_obs_score <- if (!is.na(h1_score)) h1_score else
                       max(sc_vec, na.rm = TRUE)
      max_obs_score - score_delta
    }

    # Species in genus, excluding those already in this observation
    ref_genus_rows  <- ref_by_genus[[h1_genus]]
    present_species <- unique(obs_rows[[species_col]])
    other_species   <- unique(ref_genus_rows[[species_col]])
    other_species   <- other_species[!is.na(other_species) &
                                       !other_species %in% present_species]

    if (length(other_species) == 0L) next
    if (length(other_species) > max_per_obs)
      other_species <- other_species[seq_len(max_per_obs)]

    rows_for_obs <- vector("list", length(other_species))
    for (j in seq_along(other_species)) {
      sp      <- other_species[j]
      ref_row <- ref_genus_rows[ref_genus_rows[[species_col]] == sp, ,
                                drop = FALSE][1L, ]
      new_row <- anchor_row

      for (rc in rank_system) {
        if (rc %in% names(ref_row) && rc %in% names(new_row))
          new_row[[rc]] <- ref_row[[rc]]
      }

      if ("taxon_name" %in% names(new_row)) {
        tax_present <- intersect(rank_system, names(new_row))
        new_row <- TaxaTools::create_taxon_names(new_row, tax_present)
      }

      new_row[[score_col]] <- imputed_score

      if ("accession" %in% names(new_row)) {
        ref_acc <- if ("accession" %in% names(ref_row))
          ref_row[["accession"]] else NA_character_
        new_row[["accession"]] <- paste0("RESTORED_", ref_acc)
      }

      if ("coverage" %in% names(new_row)) new_row[["coverage"]] <- NA_real_

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
      "restore_suppressed_candidates: added %d candidate rows across %d observations.",
      n_restored_rows, n_restored_obs
    ))

  result
}

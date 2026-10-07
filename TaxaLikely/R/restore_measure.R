# Scoring a restored congener: measured first, imputed as the fallback.
#
# restore_suppressed_candidates() used to score every restored congener from
# the reference hierarchy (.resolve_hierarchy_score(), Levels 1-4). Every level
# there is REFERENCE-vs-REFERENCE identity: Levels 1-3 read seq_matrix p_match
# between the anchor's and the candidate's references, and Level 4's pid
# (.check_regional_overlap(return_detail = TRUE)) aligns the candidate's
# reference to the ANCHOR's reference -- the query only locates the anchor
# range. Used as the QUERY's score, that is a fair proxy only when the query
# sits on its anchor. On CalIntertidal it put restored rows up to 31 points
# above every real hit and moved whole observations: an inflated row becomes the
# observation's best score, so it shifts the gap feature and the H2/H3 anchor of
# every other candidate.
#
# So when the query sequence is available the restored score is MEASURED: the
# query aligned to the candidate's own references. The imputation remains only
# as the fallback, and only there does the ceiling apply: a measured congener
# may legitimately beat the best hit in the match data (a newer deposit missing
# from the provider's BLAST database -- on CalIntertidal 18S, 58% of restored
# pairs did), while an imputed one has no evidence of its own to stand on.

#' Measure the query's identity to a candidate species' references
#'
#' Local alignment of the query to each reference (the same aligner and scoring
#' as Level 4's `.check_regional_overlap()`), identity as `pwalign::pid()`
#' (PID1), best over references whose alignment covers at least
#' `min_query_coverage` of the query -- the share BLAST's query-coverage filter
#' asks of the match data's own scores, so the two are on one scale.
#'
#' @param query_sequence Character(1). The observation's query sequence.
#' @param cand_sequences Character. The candidate species' reference
#'   sequences.
#' @param min_query_coverage Numeric(1). Minimum aligned share of the query.
#' @return Numeric(1): best percent identity (0-100) among references that
#'   clear the coverage rule, or `NA_real_` when none does (including invalid
#'   or missing sequences).
#' @noRd
.measure_query_identity <- function(query_sequence, cand_sequences, min_query_coverage = 0.8) {
  if (is.null(query_sequence) || length(query_sequence) != 1L || is.na(query_sequence) ||
    !nzchar(query_sequence)) {
    return(NA_real_)
  }
  q_chr <- toupper(query_sequence)
  if (!grepl("^[ACGTRYSWKMBDHVN]+$", q_chr)) return(NA_real_)
  r_chr <- toupper(cand_sequences[!is.na(cand_sequences) & nzchar(cand_sequences)])
  r_chr <- r_chr[grepl("^[ACGTRYSWKMBDHVN]+$", r_chr)]
  if (!length(r_chr)) return(NA_real_)
  q <- Biostrings::DNAString(q_chr)
  aln <- pwalign::pairwiseAlignment(Biostrings::DNAStringSet(r_chr), q, type = "local")
  cov <- (Biostrings::end(pwalign::subject(aln)) - Biostrings::start(pwalign::subject(aln)) + 1) /
    length(q)
  ok <- cov >= min_query_coverage
  if (!any(ok)) return(NA_real_)
  max(pwalign::pid(aln)[ok])
}

#' Offset between measured identity and the observed scores' scale
#'
#' Aligns each observation's query to its own best hit's reference (when
#' `reference_df` holds that accession) by the measurement rule and returns
#' the median of (measured identity - observed score), in percentage points.
#' Observations are taken evenly spaced over the sorted ids (no RNG), at most
#' `max_obs` of them. Fewer than `min_obs` usable pairs gives offset 0 with
#' `thin = TRUE`: an offset estimated from a handful of pairs would move every
#' measured score on little evidence.
#'
#' @return List: `offset`, `n` (pairs used), `iqr` (length-2), `thin`.
#' @noRd
.calibrate_measured_offset <- function(match_obj, reference_df, observation_id_col, score_col,
                                       accession_col, sequence_col, scale_100,
                                       min_query_coverage = 0.8, max_obs = 2000L,
                                       min_obs = 30L) {
  out <- list(offset = 0, n = 0L, iqr = c(NA_real_, NA_real_), thin = TRUE)
  if (!all(c(accession_col, sequence_col, score_col) %in% names(match_obj)) ||
    !"composite_id" %in% names(reference_df)) {
    return(out)
  }
  sc <- match_obj[[score_col]]
  ok <- !is.na(sc) & !is.na(match_obj[[sequence_col]]) &
    as.character(match_obj[[accession_col]]) %in% as.character(reference_df$composite_id)
  if (!any(ok)) return(out)
  mo <- match_obj[ok, , drop = FALSE]
  # each observation's best hit
  mo <- mo[order(mo[[observation_id_col]], -mo[[score_col]]), , drop = FALSE]
  mo <- mo[!duplicated(mo[[observation_id_col]]), , drop = FALSE]
  if (nrow(mo) > max_obs) {
    mo <- mo[unique(round(seq(1, nrow(mo), length.out = max_obs))), , drop = FALSE]
  }
  ref_seq <- stats::setNames(reference_df$sequence, as.character(reference_df$composite_id))
  meas <- vapply(seq_len(nrow(mo)), function(i) {
    .measure_query_identity(mo[[sequence_col]][i], ref_seq[[as.character(mo[[accession_col]][i])]],
      min_query_coverage = min_query_coverage
    )
  }, numeric(1))
  obs <- if (isTRUE(scale_100)) mo[[score_col]] else mo[[score_col]] * 100
  d <- (meas - obs)[!is.na(meas)]
  out$n <- length(d)
  if (out$n < min_obs) return(out)
  out$offset <- stats::median(d)
  out$iqr <- unname(stats::quantile(d, c(0.25, 0.75)))
  out$thin <- FALSE
  out
}

#' Impute a restored congener's score from the anchor and the reference hierarchy
#'
#' The fallback when the query cannot be measured against the candidate:
#' `anchor - (top - ref_ref)`, where `ref_ref` is the hierarchy's
#' reference-to-reference identity and `top` is 100 (or 1 on a 0-1 scale). A
#' conservative, data-derived LOWER estimate -- not a proven bound, since the
#' identities involved are measured over different overlap regions -- and equal
#' to `ref_ref` when the anchor is a perfect match. It replaces using `ref_ref`
#' directly (a property of the two reference sets alone), not a flat
#' `anchor - delta`, which the hierarchy was built to avoid.
#'
#' Ceiling, asserted here and only here: an IMPUTED score may never exceed the
#' anchor, the observation's best observed score. Measured scores are not
#' subject to it.
#'
#' @param anchor_score Numeric(1). The observation's best observed score.
#' @param ref_ref Numeric(1). Hierarchy identity, on the same scale.
#' @param scale_100 Logical(1). Scores on 0-100 (TRUE) or 0-1 (FALSE).
#' @return Numeric(1).
#' @noRd
.impute_restored_score <- function(anchor_score, ref_ref, scale_100) {
  top <- if (isTRUE(scale_100)) 100 else 1
  imputed <- anchor_score - (top - ref_ref)
  .assert_imputed_ceiling(imputed, anchor_score)
  imputed
}

#' Fail loudly if an imputed restored score beats the observation's best hit
#'
#' @noRd
.assert_imputed_ceiling <- function(imputed, anchor_score) {
  if (!is.na(imputed) && !is.na(anchor_score) && imputed > anchor_score + 1e-9) {
    stop(sprintf(
      paste0(
        "restore_suppressed_candidates: internal error -- an imputed restored score (%.4f) ",
        "exceeds the observation's best observed score (%.4f). Imputed scores must never ",
        "beat the best real hit."
      ),
      imputed, anchor_score
    ), call. = FALSE)
  }
  invisible(TRUE)
}

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

#' Measure the query's identity to candidate species' references
#'
#' Local alignment of the query to each reference (the same aligner and scoring
#' as Level 4's `.check_regional_overlap()`), identity as `pwalign::pid()`
#' (PID1), best over references whose alignment covers at least
#' `min_query_coverage` of the query -- the share BLAST's query-coverage filter
#' asks of the match data's own scores, so the two are on one scale.
#'
#' All references go through ONE `pairwiseAlignment()` call: each
#' pattern-subject pair is aligned independently, so the result is the same as
#' one call per reference, but `pwalign` rebuilds its quality-substitution
#' array on every call (~60 ms), which dominated the cost when called per
#' candidate.
#'
#' @param query_sequence Character(1). The observation's query sequence.
#' @param cand_sequences Character. Reference sequences.
#' @param species Character, parallel to `cand_sequences`, or `NULL` (all one
#'   candidate).
#' @param min_query_coverage Numeric(1). Minimum aligned share of the query.
#' @return Without `species`, numeric(1); with it, a numeric vector named by
#'   species. Best percent identity (0-100) among references that clear the
#'   coverage rule, `NA_real_` where none does (including invalid or missing
#'   sequences).
#' @noRd
.measure_query_identity <- function(query_sequence, cand_sequences, min_query_coverage = 0.8,
                                    species = NULL) {
  grp <- if (is.null(species)) rep("..one", length(cand_sequences)) else as.character(species)
  ugrp <- unique(grp)
  out <- stats::setNames(rep(NA_real_, length(ugrp)), ugrp)
  ret <- function(o) if (is.null(species)) unname(o[1L]) %||% NA_real_ else o
  if (is.null(query_sequence) || length(query_sequence) != 1L || is.na(query_sequence) ||
    !nzchar(query_sequence)) {
    return(ret(out))
  }
  q_chr <- toupper(query_sequence)
  if (!grepl("^[ACGTRYSWKMBDHVN]+$", q_chr)) return(ret(out))
  r_chr <- toupper(cand_sequences)
  ok_seq <- !is.na(r_chr) & nzchar(r_chr) & grepl("^[ACGTRYSWKMBDHVN]+$", r_chr)
  if (!any(ok_seq)) return(ret(out))
  d <- unique(data.frame(g = grp[ok_seq], s = r_chr[ok_seq], stringsAsFactors = FALSE))
  us <- unique(d$s)
  q <- Biostrings::DNAString(q_chr)
  aln <- pwalign::pairwiseAlignment(Biostrings::DNAStringSet(us), q, type = "local")
  cov <- (Biostrings::end(pwalign::subject(aln)) - Biostrings::start(pwalign::subject(aln)) + 1) /
    length(q)
  pid <- pwalign::pid(aln)
  pid[cov < min_query_coverage] <- NA_real_
  d$pid <- pid[match(d$s, us)]
  best <- tapply(d$pid, d$g, function(v) if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE))
  out[names(best)] <- as.numeric(best)
  ret(out)
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
  ref_seq <- stats::setNames(toupper(reference_df$sequence), as.character(reference_df$composite_id))
  qs <- toupper(mo[[sequence_col]])
  rs <- unname(ref_seq[as.character(mo[[accession_col]])])
  valid <- !is.na(qs) & !is.na(rs) & grepl("^[ACGTRYSWKMBDHVN]+$", qs) & grepl("^[ACGTRYSWKMBDHVN]+$", rs)
  meas <- rep(NA_real_, nrow(mo))
  if (any(valid)) {
    # One elementwise call (pattern i against subject i), same scoring as
    # .measure_query_identity().
    qq <- Biostrings::DNAStringSet(qs[valid])
    aln <- pwalign::pairwiseAlignment(Biostrings::DNAStringSet(rs[valid]), qq, type = "local")
    cov <- (Biostrings::end(pwalign::subject(aln)) - Biostrings::start(pwalign::subject(aln)) + 1) /
      Biostrings::width(qq)
    m <- pwalign::pid(aln)
    m[cov < min_query_coverage] <- NA_real_
    meas[valid] <- m
  }
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
#' `min(ref_ref, anchor)`, where `ref_ref` is the hierarchy's
#' reference-to-reference identity. `ref_ref` alone matched the measured
#' identity closely where it did not exceed the anchor (CalIntertidal MAE
#' 0.94-1.27); the inflation came from rows above the anchor, which an imputed
#' score has no evidence of its own to justify. `anchor - (top - ref_ref)` was
#' measured and rejected: worse than the defect on the defect's own rows (COI
#' MAE 7.02 against 5.08).
#'
#' Ceiling, asserted here and only here: an IMPUTED score may never exceed the
#' anchor, the observation's best observed score. Measured scores are not
#' subject to it.
#'
#' @param anchor_score Numeric(1). The observation's best observed score.
#' @param ref_ref Numeric(1). Hierarchy identity, on the same scale.
#' @param scale_100 Logical(1). Unused by the rule; kept so the call site
#'   states its scale.
#' @return Numeric(1).
#' @noRd
.impute_restored_score <- function(anchor_score, ref_ref, scale_100) {
  imputed <- min(ref_ref, anchor_score)
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

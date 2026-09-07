# ==============================================================================
# .check_regional_overlap()
# ==============================================================================
# Internal helper for restore_suppressed_candidates()'s regional-overlap check
# (Session 159): decides whether a same-genus congener actually has reference
# evidence covering the SAME genomic window as a query's own top-hit
# ("anchor") reference, rather than assuming any same-genus reference is a
# valid competitor regardless of where in the marker it sits. Motivating real
# case: a Fundulus 12S query whose only BLAST hit is a congener's complete
# mitogenome (covering a genomic position outside the standard MiFish
# amplicon) was silently restoring an unrelated congener as a fabricated
# specific_candidate, even though that congener's own reference sequence
# doesn't overlap the query's actual position at all.
#
# Three ways to reach a verdict, cheapest/most-certain first, short-
# circuiting on the first qualifying result. Tiers 2a/2b both need to know
# WHERE within the anchor sequence the query itself aligned -- see the
# Tier 1 entry for why "any overlap anywhere in the anchor" is unsafe once
# the anchor may be a whole genome; Tier 1 alone (no position information at
# all) is the safe default when neither 2a nor 2b's inputs are supplied.
#
#   Tier 1 (free, always tried first): look up seq_matrix (already computed
#     once per genus by build_sequence_matrix() at training time, not per
#     query) for an existing pairwise coverage value between the anchor
#     accession and any of the candidate's accessions. Safe to treat "any
#     overlap" as sufficient here (no position check needed) because
#     build_sequence_matrix() only ever includes properly-sized, barcode-
#     length sequences -- never a full genome.
#   Tier 2a (reference-vs-reference, needs anchor_subject_range): when the
#     caller already knows where the query's own alignment fell within the
#     anchor (e.g. TaxaMatch::blast_sequences()'s subject_start/subject_end
#     columns, cheapest since no extra alignment is needed to establish it),
#     a fresh local pairwise alignment of each candidate against the
#     anchor's own sequence content (from reference_df, including out-of-
#     range sequences retained via
#     fetch_ncbi_reference_sequences(keep_out_of_range = TRUE)) is checked
#     for overlap against that range.
#   Tier 2b (query-vs-reference, needs query_sequence): for match objects
#     with no live BLAST step at all (e.g. built from an externally pre-
#     computed match table with percent-identity/accession columns but no
#     BLAST alignment coordinates -- confirmed real for this ecosystem's
#     PtConception 12S/18S workflows), anchor_subject_range is derived
#     on-the-fly instead: align the query's own raw sequence against the
#     anchor's reference sequence (both already in memory -- no NCBI call
#     needed) to find where the query itself falls within the anchor, then
#     proceed exactly as Tier 2a. Deliberately checked only when Tier 2a's
#     input is absent -- 2a is strictly cheaper when both happen to be
#     available.
#
# Real design flaw caught before landing (Session 159): an early version of
# Tier 2a checked only "does the candidate align anywhere in the anchor's
# full sequence," which is nearly always true once the anchor is a whole
# genome (it necessarily contains every sub-region of the gene). Confirmed
# empirically on the real Fundulus case: F. parvipinnis's own real 12S
# reference aligns to F. lima's mitogenome at position 319-486, which does
# NOT overlap the real query's actual hit position (515-613) at all -- the
# naive "any overlap" check got this wrong.
#
# Returns NA (not FALSE) whenever no tier can produce any evidence at all
# (e.g. the anchor's own sequence isn't available anywhere, or neither
# anchor_subject_range nor query_sequence was supplied) -- callers should
# treat NA conservatively, the same as a confirmed non-overlap, since there
# is no basis to assume the congener DOES overlap either. This makes Tier 1
# alone the graceful, safe default: supplying neither anchor_subject_range
# nor query_sequence simply means Tier 2 is never reached.
#
# Performance (Session 159, continued further): Tier 2's per-candidate
# pairwise alignment (candidate sequence vs. the anchor's own, potentially a
# ~16-20kb mitogenome) depends only on (anchor_accession, candidate
# accession) -- NOT on anchor_subject_range or which observation is asking.
# Once restore_suppressed_candidates()'s gating fix let this run across every
# observation (not just ones matching a globally-detected suppression rule),
# a real Mugu dataset surfaced a genuine cost problem: 401 observations
# reduce to only 71 distinct anchor accessions (one anchor alone was reused
# by 113 observations), so recomputing the SAME alignment once per
# observation instead of once per (anchor, candidate) pair wasted well over
# 90% of the work -- confirmed live, a single-marker run exceeded 15 minutes
# and was still running. The optional align_cache parameter (a mutable
# environment, created once per restore_suppressed_candidates() call and
# threaded through every .check_regional_overlap() call in its loop) fixes
# this: the expensive alignment result is computed at most once per distinct
# (anchor, candidate) pair, however many observations share that anchor. The
# position-overlap decision itself (comparing the candidate's cached aligned
# range against THIS observation's own anchor_subject_range) stays a cheap,
# per-observation O(1) comparison, so nothing about the check's correctness
# changes -- this is a memoization of the alignment step only.
#
# Performance (Session 159, PtConception rollout): Tier 2b's OWN alignment
# (the query's raw sequence vs. the anchor, needed to derive
# anchor_subject_range when no live BLAST step supplied it) has an identical
# caching gap, one level up: it depends only on (anchor_accession,
# query_sequence), not on which candidate species is being checked, but the
# caller invokes this function once PER CANDIDATE SPECIES for a given
# observation (see restore_suppressed_candidates()'s vapply loop) --
# confirmed via real PtConception 12S timing that an observation with several
# congener candidates was re-running the identical query-vs-anchor alignment
# once per candidate. Cached the same way, keyed on
# (anchor_accession, query_sequence).
#
# return_detail (SPEC_restore_suppressed_candidates_redesign.md Section 3a,
# Level 4): the plain logical/NA return above is the original, unchanged
# contract every existing caller relies on. When TRUE, the function instead
# returns a list(overlap = TRUE/FALSE/NA, pid = <median percent identity
# across every candidate accession that passed the position-overlap check, or
# NA_real_ if none did>) -- this is Level 4's score-sourcing output for a
# restored candidate, aggregated the same median-not-max way as every other
# hierarchy level (Section 4). `pid` comes from `pwalign::pid(aln)` (default
# `PID1`, confirmed correct against the real F. parvipinnis/F. lima case --
# see the spec's Level 4 entry) -- a free read of the alignment object Tier 2
# already builds for the position check, no extra alignment work. Unlike the
# logical-return mode, `return_detail = TRUE` does NOT short-circuit on the
# first accepted candidate accession -- it must see every accepted pair to
# compute a real median, so all of `cand_idx` is walked regardless.
#' @noRd
.check_regional_overlap <- function(anchor_accession, candidate_accessions,
                                    reference_df, seq_matrix = NULL,
                                    anchor_subject_range = NULL,
                                    query_sequence = NULL,
                                    min_coverage = 0.5,
                                    align_cache = NULL,
                                    return_detail = FALSE) {
  .no_evidence <- if (return_detail) list(overlap = NA, pid = NA_real_) else NA

  # align_cache (when supplied) is one environment per restore_suppressed_
  # candidates() call, so reference_df/seq_matrix are the SAME objects across
  # every .check_regional_overlap() call sharing it -- fixed cache keys below
  # (not scoped to any accession) are therefore safe, not just an
  # accidental reuse of stale data from a different reference_df/seq_matrix.
  use_cache <- !is.null(align_cache) && is.environment(align_cache)

  anchor_accession <- sub("\\.[0-9]+$", "", anchor_accession)
  candidate_accessions <- sub("\\.[0-9]+$", "", candidate_accessions)
  candidate_accessions <- unique(candidate_accessions[!is.na(candidate_accessions)])

  if (is.na(anchor_accession) || length(candidate_accessions) == 0L) {
    return(.no_evidence)
  }

  # ---- Tier 1: seq_matrix lookup (free, already computed) --------------------
  # Performance (Session 159, PtConception rollout): stripping id_x/id_y's
  # version suffixes is, on its own, an O(nrow(seq_matrix)) regex pass --
  # cheap once, but seq_matrix is unchanged across every call in
  # restore_suppressed_candidates()'s loop (one call per candidate species per
  # observation), so recomputing it every call turned "Tier 1, free" into the
  # dominant real cost on real PtConception data (seq_matrix here has ~3M
  # rows; profiling showed >90% of total wall time in sub() alone, an order
  # of magnitude more than the Tier 2 alignment work this session's other
  # caching fixes target). Cached the same way anchor_seq/(anchor, candidate)
  # pairs already are, under a fixed key (safe -- see note above).
  if (!is.null(seq_matrix) && is.data.frame(seq_matrix) && nrow(seq_matrix) > 0L &&
    all(c("id_x", "id_y", "coverage") %in% names(seq_matrix))) {
    if (use_cache && exists("seq_matrix_ids", envir = align_cache, inherits = FALSE)) {
      sm_ids <- get("seq_matrix_ids", envir = align_cache, inherits = FALSE)
      id_x <- sm_ids$id_x
      id_y <- sm_ids$id_y
    } else {
      id_x <- sub("\\.[0-9]+$", "", seq_matrix$id_x)
      id_y <- sub("\\.[0-9]+$", "", seq_matrix$id_y)
      if (use_cache) assign("seq_matrix_ids", list(id_x = id_x, id_y = id_y), envir = align_cache)
    }
    hit_mask <- (id_x == anchor_accession & id_y %in% candidate_accessions) |
      (id_y == anchor_accession & id_x %in% candidate_accessions)
    if (any(hit_mask)) {
      cov <- seq_matrix$coverage[hit_mask]
      cov <- cov[!is.na(cov)]
      if (length(cov) > 0L && max(cov) >= min_coverage) {
        # Tier 1 has no pwalign alignment object to read a pid from -- a
        # seq_matrix coverage hit means Levels 1-3 of the score-sourcing
        # hierarchy (SPEC_restore_suppressed_candidates_redesign.md Section
        # 3a) would already have resolved this candidate's score directly
        # from seq_matrix's own p_match column, so this branch is not
        # actually reachable from that hierarchy's Level 4 call (which is
        # only ever attempted after Level 0 already confirmed the anchor has
        # NO seq_matrix presence at all). Handled defensively regardless.
        return(if (return_detail) list(overlap = TRUE, pid = NA_real_) else TRUE)
      }
    }
  }

  # ---- Tiers 2a/2b need Biostrings/pwalign + reference_df's own sequences ----
  if (!requireNamespace("Biostrings", quietly = TRUE) ||
    !requireNamespace("pwalign", quietly = TRUE)) {
    return(.no_evidence) # can't run either Tier 2 without these; conservative fallback
  }
  if (!is.data.frame(reference_df) ||
    !all(c("composite_id", "sequence") %in% names(reference_df))) {
    return(.no_evidence)
  }

  # Same fixed-key caching, same reasoning, for reference_df's own composite_id
  # stripping (much smaller than seq_matrix in practice, but still
  # O(nrow(reference_df)) recomputed on every call without this).
  if (use_cache && exists("ref_ids", envir = align_cache, inherits = FALSE)) {
    ref_ids <- get("ref_ids", envir = align_cache, inherits = FALSE)
  } else {
    ref_ids <- sub("\\.[0-9]+$", "", reference_df$composite_id)
    if (use_cache) assign("ref_ids", ref_ids, envir = align_cache)
  }

  anchor_key <- paste0("anchor::", anchor_accession)
  if (use_cache && exists(anchor_key, envir = align_cache, inherits = FALSE)) {
    anchor_seq <- get(anchor_key, envir = align_cache, inherits = FALSE)
    if (is.null(anchor_seq)) {
      return(.no_evidence)
    } # cached failure -- anchor unusable
  } else {
    anchor_seq_chr <- reference_df$sequence[ref_ids == anchor_accession]
    anchor_seq_chr <- anchor_seq_chr[!is.na(anchor_seq_chr) & nzchar(anchor_seq_chr)]
    anchor_seq <- if (length(anchor_seq_chr) == 0L) {
      NULL # anchor's own sequence unavailable
    } else {
      tryCatch(Biostrings::DNAString(anchor_seq_chr[1L]), error = function(e) NULL)
    }
    if (use_cache) assign(anchor_key, anchor_seq, envir = align_cache)
    if (is.null(anchor_seq)) {
      return(.no_evidence)
    }
  }

  # ---- Resolve anchor_subject_range: Tier 2a (supplied) or Tier 2b (derived) -
  has_range <- !is.null(anchor_subject_range) && length(anchor_subject_range) == 2L &&
    !anyNA(anchor_subject_range)

  # Tier 2b's query-vs-anchor alignment depends only on (anchor_accession,
  # query_sequence) -- NOT on which candidate is being checked -- but the
  # caller (restore_suppressed_candidates()'s vapply loop) invokes this
  # function once per candidate species for a given observation. Without
  # caching, an observation with N congener candidates redundantly re-runs
  # the identical query-vs-anchor alignment N times. Cached the same way
  # anchor_seq/the (anchor, candidate) pairs already are, keyed on
  # (anchor_accession, query_sequence) -- confirmed a real, not just
  # theoretical, cost on real PtConception data (Session 159 continuation).
  if (!has_range && !is.null(query_sequence) && !is.na(query_sequence) &&
    nzchar(query_sequence)) {
    query_key <- if (use_cache) paste0("query::", anchor_accession, "::", query_sequence) else NULL
    if (use_cache && exists(query_key, envir = align_cache, inherits = FALSE)) {
      derived_range <- get(query_key, envir = align_cache, inherits = FALSE)
    } else {
      derived_range <- NULL
      query_seq <- tryCatch(Biostrings::DNAString(query_sequence), error = function(e) NULL)
      if (!is.null(query_seq)) {
        q_aln <- tryCatch(
          pwalign::pairwiseAlignment(query_seq, anchor_seq, type = "local"),
          error = function(e) NULL
        )
        if (!is.null(q_aln)) {
          derived_range <- c(
            Biostrings::start(pwalign::subject(q_aln)),
            Biostrings::end(pwalign::subject(q_aln))
          )
        }
      }
      if (use_cache) assign(query_key, derived_range, envir = align_cache)
    }
    if (!is.null(derived_range) && length(derived_range) == 2L && !anyNA(derived_range)) {
      anchor_subject_range <- derived_range
      has_range <- TRUE
    }
  }

  if (!has_range) {
    return(.no_evidence)
  } # Tier 1 already tried; nothing else available

  q_lo <- min(anchor_subject_range)
  q_hi <- max(anchor_subject_range)

  cand_idx <- which(ref_ids %in% candidate_accessions)
  if (length(cand_idx) == 0L) {
    return(.no_evidence)
  } # no candidate sequence available to check at all

  accepted_pids <- numeric(0L) # only accumulated when return_detail = TRUE

  for (k in cand_idx) {
    cand_accession <- ref_ids[k]
    pair_key <- paste("pair", anchor_accession, cand_accession, sep = "::")

    if (use_cache && exists(pair_key, envir = align_cache, inherits = FALSE)) {
      cached <- get(pair_key, envir = align_cache, inherits = FALSE)
    } else {
      cached <- NULL
      cand_chr <- reference_df$sequence[k]
      if (!is.na(cand_chr) && nzchar(cand_chr)) {
        cand_seq <- tryCatch(Biostrings::DNAString(cand_chr), error = function(e) NULL)
        if (!is.null(cand_seq)) {
          aln <- tryCatch(
            pwalign::pairwiseAlignment(cand_seq, anchor_seq, type = "local"),
            error = function(e) NULL
          )
          if (!is.null(aln)) {
            # Candidate's own aligned position WITHIN the anchor sequence --
            # a candidate that aligns well to the anchor SOMEWHERE, but not
            # at the query's own position, must not count as overlapping.
            # This whole result depends only on (anchor, candidate), not on
            # any one observation's own anchor_subject_range -- see the
            # Performance note above for why it's cached across the loop.
            overlap_width <- Biostrings::nchar(aln)
            min_len <- min(length(cand_seq), length(anchor_seq))
            cached <- list(
              subj_start = Biostrings::start(pwalign::subject(aln)),
              subj_end   = Biostrings::end(pwalign::subject(aln)),
              coverage   = if (min_len > 0L) overlap_width / min_len else 0,
              # Level 4 score source (SPEC_restore_suppressed_candidates_
              # redesign.md Section 3a): free read of a property `aln`
              # already has, on the same 0-100 scale seq_matrix's p_match
              # uses (after /100). Default PID1 -- confirmed correct against
              # the real F. parvipinnis/F. lima case (96.43% at the
              # documented 319-486 position); PID4 (normalizes by the
              # anchor's full length rather than the aligned region) gave a
              # meaningless 1.9% for the same pair and would have been wrong.
              pid        = pwalign::pid(aln)
            )
          }
        }
      }
      if (use_cache) assign(pair_key, cached, envir = align_cache)
    }

    if (is.null(cached)) next # alignment unavailable/failed for this pair

    position_overlaps <- cached$subj_start <= q_hi && cached$subj_end >= q_lo
    if (!position_overlaps) next

    if (!is.na(cached$coverage) && cached$coverage >= min_coverage) {
      if (!return_detail) {
        return(TRUE)
      } # short-circuit -- caller only wants a verdict
      # return_detail = TRUE needs every accepted candidate's pid to compute
      # a real median (Section 4), so no short-circuit here.
      pid_val <- cached$pid %||% NA_real_
      if (!is.na(pid_val)) accepted_pids <- c(accepted_pids, pid_val)
    }
  }

  if (return_detail) {
    if (length(accepted_pids) > 0L) {
      return(list(overlap = TRUE, pid = stats::median(accepted_pids)))
    }
    return(list(overlap = FALSE, pid = NA_real_))
  }

  FALSE
}

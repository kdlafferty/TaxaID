utils::globalVariables(c("score_val"))

# score_consensus.R
# TaxaAssign package
#
# Conventional score-based consensus taxonomy.  Works directly from raw match
# scores (percent identity, similarity, etc.) without Bayesian machinery.
#
# Purpose (clarified Session 149): this exists to REPRODUCE the fixed-
# threshold consensus logic of conventional non-Bayesian pipelines (e.g.
# GITA, Jonah Ventures-style workflows), so a user can compare TaxaID's own
# Bayesian pathway (TaxaLikely -> compute_posterior() -> posterior_consensus())
# against what a conventional pipeline would have called on the same data.
# It is a mimicry/benchmarking tool, not TaxaID's own species-level
# discriminator -- see the roxygen "Purpose" note below.
#
# Exported functions:
#   score_consensus()        Score-based LCA consensus from a match dataframe
#
# Internal helpers:
#   .score_consensus_one()   Per-observation consensus
#   .cap_rank_by_threshold() Apply rank-specific score thresholds
#   .uprank_to_whitelist()   Uprank consensus to nearest whitelisted rank


# ==============================================================================
# Main exported function
# ==============================================================================

#' Derive Consensus Taxonomy from Raw Match Scores
#'
#' For each `observation_id`, applies conventional score-based filtering to derive a
#' consensus taxonomic assignment.  The algorithm:
#'
#' 1. **Score filter:** discard hits below `min_score`.
#' 2. **Gap filter:** among remaining hits, keep only those within `max_gap` of
#'    the top score (per sample).
#' 3. **LCA:** compute the lowest common ancestor (LCA) of the retained hits.
#' 4. **Rank threshold cap:** if `rank_thresholds` is supplied, cap the
#'    consensus at the finest rank whose minimum score the top hit meets.
#' 5. **Whitelist upranking:** if `whitelist` is supplied, verify the consensus
#'    taxon appears in the whitelist.  If not, uprank to the coarsest rank
#'    where at least one whitelist member agrees with the retained candidates.
#'
#' This function does not require a trained likelihood model or priors.  It is
#' the conventional approach used in most metabarcoding and BLAST-based
#' pipelines.
#'
#' @section Purpose -- why this function exists alongside the Bayesian pathway:
#' `score_consensus()` is deliberately a **reproduction of a conventional,
#' non-Bayesian pipeline's decision rule** (fixed percent-identity thresholds
#' per rank, e.g. the GITA / Jonah Ventures convention), not TaxaID's own
#' species-level discriminator. Its purpose is to let a user run the exact
#' same match data through both approaches and compare: what would a
#' conventional fixed-threshold workflow have called here, versus what does
#' TaxaID's Bayesian pathway (`TaxaLikely`'s bivariate-normal likelihoods ->
#' [compute_posterior()] -> [posterior_consensus()]) call? This is the
#' intended, load-bearing use case -- mirroring another pipeline's process so
#' its output can be directly compared against TaxaID's.
#'
#' Because of this, `rank_thresholds`' known inability to reliably separate a
#' true species from its closest congener (percent-identity alone cannot do
#' this at almost any real-world threshold -- see Details) is **not a defect
#' to fix in this function**: it is a faithful reproduction of the same
#' limitation those conventional pipelines actually have. "Fixing" it (e.g. by
#' gating on reference completeness, or routing through the bivariate-normal
#' model) would defeat the comparison this function exists to provide. If you
#' need real species-vs-congener discrimination for an actual assignment,
#' use [posterior_consensus()], not this function.
#'
#' @param match_df Data frame.
#'   One row per `observation_id` x reference hit.  Required columns: `observation_id`,
#'   `taxon_name`, `taxon_name_rank`, and the column named by `score_col`.
#'   Taxonomy columns (e.g. `family`, `genus`, `species`) are used for LCA
#'   resolution when present; genus is always derivable from species binomials.
#' @param min_score Numeric.  Minimum score to retain a hit.  Hits below this
#'   value are discarded before any other filtering.  Scale must match the
#'   `score_col` values (e.g. 97 for percent identity, 0.97 for proportion).
#'   Default `0` (no filtering). Note: an ROC-style sweep against real 12S
#'   reference data (`diagnostics/score_floor_roc_sweep.R`, 2026-07-09) found
#'   that `min_score`/raw percent-identity alone cannot discriminate a true
#'   species from its closest congener at almost any real-world threshold
#'   (true-positive and congeneric-false-positive rates track each other
#'   almost exactly up to ~97). `min_score`'s real value is excluding
#'   obviously-wrong cross-family hits, not fine species-level discrimination
#'   -- that discrimination is `rank_thresholds`' job (see below).
#' @param max_gap Numeric.  Maximum score difference from the top hit (per
#'   sample).  All hits within `max_gap` of the best score contribute to the
#'   LCA.  For example, `max_gap = 1` keeps all hits within 1 unit of the top
#'   score.  Default `Inf` (all hits above `min_score` contribute).
#' @param rank_thresholds Named numeric vector, or `NULL`.  Maps rank names to
#'   minimum scores, e.g. `c(species = 97, genus = 95, family = 90)`.  After
#'   the LCA is computed, the consensus is capped at the finest rank whose
#'   threshold the top score meets.  If the top score fails all thresholds, the
#'   sample is unresolvable.  Applied independently of the LCA — so even if all
#'   hits agree on species, the consensus is demoted to genus if the top score
#'   is below the species threshold.
#'   **No default -- errors if omitted (2026-07-23).** This function has no
#'   way to know the marker or even whether `score_col` holds a DNA/image/
#'   acoustic score, so no single fixed threshold set is safe to assume for
#'   every caller (see Details for why the earlier GITA/Jonah Ventures
#'   default, `c(species = 98, genus = 95, family = 90, phylum = 85)`, was
#'   removed rather than kept as a default). Supply one of:
#'   (1) your own thresholds, on whichever scale `score_col` uses (percent
#'   identity or 0-1 proportion -- see the auto-rescale note below), or
#'   (2) marker-specific thresholds derived from your own reference data via
#'   `TaxaLikely::compute_rank_thresholds()` (per-rank Youden's J on a
#'   `build_sequence_matrix()`-style pairwise distance matrix). Pass
#'   `rank_thresholds = NULL` explicitly to disable rank capping entirely.
#'   If `score_col`'s values look like a 0-1 proportion scale (max <= 1)
#'   rather than 0-100 percent-identity, a supplied 0-100-scale
#'   `rank_thresholds` is automatically rescaled by /100 (with an
#'   informational message) -- pass your own already-scaled
#'   `rank_thresholds` to silence this.
#' @param whitelist Character vector or `NULL`.  Plausible taxon names (any
#'   rank).  When supplied, the consensus taxon must appear in this list;
#'   otherwise the consensus is upranked to the coarsest rank where a
#'   whitelist member agrees with the retained candidates.  Default `NULL`
#'   (no whitelist filtering).
#' @param score_col Character.  Column name containing match scores.
#'   Default `"score_original"`.
#' @param rank_system Character vector of taxonomy column names, coarse to
#'   fine (e.g. `c("family", "genus", "species")`).  If `NULL` (default),
#'   standard columns present in `match_df` are detected automatically.
#'
#' @details
#' \strong{Why `rank_thresholds` has no default (2026-07-23, supersedes the
#' 2026-07-09 GITA/Jonah Ventures default):}
#' `min_score` and `max_gap` alone provide essentially no protection against
#' confusing a species with its closest congener -- an ROC-style sweep against
#' real 12S reference data found true-positive (within-species) and
#' false-positive (congeneric) rates track almost identically up to a ~97
#' percent-identity threshold (see `diagnostics/score_floor_roc_sweep.R`).
#' This is a real limitation of percent-identity thresholds generally --
#' `rank_thresholds` is what does the real species-level discrimination this
#' function offers, which is exactly why a caller getting NO thresholds at
#' all (the pre-2026-07-09 `NULL` default) was a real gap.
#'
#' The 2026-07-09 fix picked ONE fixed threshold set (the conventional
#' GITA/Jonah Ventures percent-identity convention) as the default. That
#' default was itself later found unsafe to assume universally: this
#' function has no way to know what marker `score_col` was scored against,
#' or even whether the data is DNA, image, or acoustic evidence at all --
#' the real, calibrated threshold for "98% identity means species-level
#' confidence" is a property of the SPECIFIC marker and reference database,
#' not a universal constant (mirrors `TaxaAssign::join_priors()`'s
#' `backbone_id` precedent: no safe default exists when the correct value
#' depends on data the function itself cannot see). Rather than continue
#' shipping a plausible-looking but potentially-wrong default, the function
#' now requires the caller to make this choice explicitly -- either supplying
#' real thresholds directly, or deriving marker-specific ones from real
#' reference data via `TaxaLikely::compute_rank_thresholds()` (which uses
#' the identical genus-/family-equal-weighted, Empirical-Bayes-shrunk
#' per-rank Youden's J logic `diagnostics/score_floor_roc_sweep.R`
#' prototyped). Pass `rank_thresholds = NULL` explicitly only if the specific
#' pipeline you're mirroring genuinely has no rank-threshold step (rare).
#'
#' @return A data frame with one row per `observation_id`:
#'   \describe{
#'     \item{`observation_id`}{Sample identifier.}
#'     \item{`consensus_taxon`}{LCA taxon name, or `NA` if unresolvable.}
#'     \item{`consensus_rank`}{Rank of the LCA (e.g. `"genus"`), or `NA`.}
#'     \item{`consensus_reason`}{How the consensus was reached:
#'       `"unanimous"` (all retained taxa agree at the finest rank),
#'       `"single"` (only one taxon retained after filtering),
#'       `"lca"` (upranked because retained taxa disagree at finer ranks),
#'       `"threshold"` (rank-capped by `rank_thresholds`), or `NA`
#'       (unresolvable).}
#'     \item{`is_resolved`}{`TRUE` when the consensus is at the finest rank in
#'       `rank_system`.}
#'     \item{`top_score`}{Highest score among retained hits for this sample.}
#'     \item{`n_retained`}{Number of hits retained after score + gap filtering
#'       (before rank threshold and whitelist steps).}
#'     \item{`n_taxa`}{Number of distinct `taxon_name` values among retained
#'       hits.}
#'     \item{`retained_taxa`}{List column: character vector of distinct taxon
#'       names among retained hits, sorted by descending score.}
#'     \item{`rank_capped`}{Logical.  `TRUE` when the consensus rank was
#'       demoted by `rank_thresholds`.  Only present when `rank_thresholds`
#'       is non-`NULL`.}
#'     \item{`whitelist_capped`}{Logical.  `TRUE` when the consensus was
#'       upranked because the original taxon was absent from `whitelist`.
#'       Only present when `whitelist` is non-`NULL`.}
#'   }
#'
#' @seealso [posterior_consensus()] for the Bayesian posterior-based approach.
#'
#' @examples
#' match_df <- data.frame(
#'   observation_id  = c("S1", "S1", "S1"),
#'   taxon_name      = c("Gadus morhua", "Gadus chalcogrammus", "Gadus"),
#'   taxon_name_rank = c("species", "species", "genus"),
#'   score_original  = c(99, 98.5, 90),
#'   genus           = "Gadus",
#'   family          = "Gadidae"
#' )
#' sc <- score_consensus(
#'   match_df,
#'   min_score       = 97,
#'   rank_thresholds = c(species = 98, genus = 95, family = 90)
#' )
#' sc[, c("observation_id", "consensus_taxon", "consensus_rank", "is_resolved")]
#'
#' @importFrom cli cli_abort cli_inform
#' @importFrom dplyr bind_rows
#'
#' @export
score_consensus <- function(match_df,
                            min_score = 0,
                            max_gap = Inf,
                            whitelist = NULL,
                            score_col = "score_original",
                            rank_system = NULL,
                            rank_thresholds) {
  # --- Input validation -------------------------------------------------------
  if (missing(rank_thresholds)) {
    cli::cli_abort(c(
      "{.arg rank_thresholds} must be specified explicitly.",
      "i" = "There is no safe default: this function has no way to know the \\
      marker or data type {.field score_col} was scored against, so no \\
      single fixed threshold set is safe to assume. Either supply your own \\
      named vector (e.g. {.code c(species = 98, genus = 95, family = 90)}), \\
      derive marker-specific thresholds from your own reference data via \\
      {.fn TaxaLikely::compute_rank_thresholds}, or pass \\
      {.code rank_thresholds = NULL} explicitly to disable rank-based \\
      capping entirely."
    ))
  }
  required <- c("observation_id", "taxon_name", "taxon_name_rank", score_col)
  missing_cols <- setdiff(required, names(match_df))
  if (length(missing_cols) > 0) {
    cli::cli_abort("match_df missing required column(s): {.field {missing_cols}}")
  }
  if (!is.numeric(match_df[[score_col]])) {
    cli::cli_abort("Column {.field {score_col}} must be numeric.")
  }
  if (!is.numeric(min_score) || length(min_score) != 1L) {
    cli::cli_abort("{.arg min_score} must be a single numeric value.")
  }
  if (!is.numeric(max_gap) || length(max_gap) != 1L || max_gap < 0) {
    cli::cli_abort("{.arg max_gap} must be a single non-negative numeric value.")
  }
  if (!is.null(rank_thresholds)) {
    if (!is.numeric(rank_thresholds) || is.null(names(rank_thresholds))) {
      cli::cli_abort("{.arg rank_thresholds} must be a named numeric vector.")
    }
  }
  if (!is.null(whitelist)) {
    if (!is.character(whitelist)) {
      cli::cli_abort("{.arg whitelist} must be a character vector.")
    }
  }

  # --- Auto-scale rank_thresholds if score_col looks like a 0-1 proportion --
  # A caller-supplied rank_thresholds is commonly written on the 0-100
  # percent-identity scale (e.g. the conventional GITA/Jonah Ventures
  # thresholds species=98, genus=95, family=90, phylum=85; see
  # TaxaAssign/CLAUDE.md). score_consensus() itself is scale-agnostic
  # (min_score's own doc: "97 for percent identity, 0.97 for proportion"), so
  # applying 0-100-scale thresholds blindly to 0-1-scale data would silently
  # make every observation unresolvable (no score could ever clear a
  # threshold of 85+). Detect and rescale, following the same
  # `if (max(x) > 1) treat-as-percent else treat-as-proportion` convention
  # used elsewhere in the ecosystem (TaxaLikely::.normalize_scores(),
  # assign_scores(), restore_suppressed_candidates()$delta).
  if (!is.null(rank_thresholds) && any(rank_thresholds > 1)) {
    max_score <- suppressWarnings(max(match_df[[score_col]], na.rm = TRUE))
    if (is.finite(max_score) && max_score <= 1) {
      rank_thresholds <- rank_thresholds / 100
      cli::cli_inform(
        "score_consensus: {.field {score_col}} values look like a 0-1 \\
        proportion scale (max = {round(max_score, 3)}); rescaling \\
        {.arg rank_thresholds} by /100 to match. Pass {.arg rank_thresholds} \\
        explicitly (already on your data's scale) to silence this."
      )
    }
  }

  # --- Resolve rank system ----------------------------------------------------
  if (is.null(rank_system)) {
    rank_system <- TaxaTools::detect_ranks(match_df)
  } else {
    # .find_lca() infers coarsest/finest from POSITION -- warn if a
    # user-supplied vector disagrees in order with the standard Linnaean
    # ranking, since that would silently swap "coarsest" and "finest".
    .check_rank_system_order(rank_system, "score_consensus")
  }

  # --- Process each sample ----------------------------------------------------
  observation_ids <- unique(match_df$observation_id)
  cli::cli_inform(
    "Computing score-based consensus for {length(observation_ids)} observation(s)..."
  )

  results <- lapply(observation_ids, function(sid) {
    chunk <- match_df[match_df$observation_id == sid, ]
    .score_consensus_one(
      chunk, sid, score_col, min_score, max_gap,
      rank_thresholds, whitelist, rank_system
    )
  })

  out <- dplyr::bind_rows(results)

  attr(out, "report_params") <- list(
    min_score       = min_score,
    max_gap         = max_gap,
    rank_thresholds = rank_thresholds,
    has_whitelist   = !is.null(whitelist)
  )

  out
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Compute score-based consensus for one observation
#' @noRd
.score_consensus_one <- function(chunk, sid, score_col, min_score, max_gap,
                                 rank_thresholds, whitelist, rank_system) {
  finest_rank <- rank_system[length(rank_system)]

  .empty_score_row <- function() {
    out <- data.frame(
      observation_id = sid,
      consensus_taxon = NA_character_,
      consensus_rank = NA_character_,
      consensus_reason = NA_character_,
      is_resolved = FALSE,
      top_score = NA_real_,
      n_retained = 0L,
      n_taxa = 0L,
      retained_taxa = I(list(character(0))),
      stringsAsFactors = FALSE
    )
    if (!is.null(rank_thresholds)) out$rank_capped <- FALSE
    if (!is.null(whitelist)) out$whitelist_capped <- FALSE
    out
  }

  # Step 1: minimum score filter
  scores <- chunk[[score_col]]
  keep1 <- !is.na(scores) & scores >= min_score
  if (!any(keep1)) {
    return(.empty_score_row())
  }

  # Step 2: gap filter (within max_gap of top score among step-1-retained
  # scores). Combined with keep1 into one mask so chunk is only ever
  # subsetted once, at the end, instead of being reassigned mid-filter.
  top_score <- max(scores[keep1], na.rm = TRUE)
  keep2 <- keep1 & scores >= (top_score - max_gap)
  if (!any(keep2)) {
    return(.empty_score_row())
  }

  chunk <- chunk[keep2, ]

  # Sort by score descending for retained_taxa ordering
  chunk <- chunk[order(chunk[[score_col]], decreasing = TRUE), ]

  # Deduplicate to unique taxon names (keep best score per taxon)
  taxa_unique <- chunk[!duplicated(chunk$taxon_name), ]

  n_retained <- nrow(chunk)
  n_taxa <- nrow(taxa_unique)

  # Step 3: LCA among retained hits
  # Reuse the .find_lca() and .extract_rank_values() helpers from

  # posterior_consensus.R (they are internal to TaxaAssign, so accessible here).
  lca <- .find_lca(taxa_unique, rank_system)
  is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  consensus_reason <- lca$consensus_reason

  rank_capped <- FALSE
  whitelist_capped <- FALSE

  # Step 4: rank threshold capping
  if (!is.null(rank_thresholds) && !is.na(lca$rank)) {
    cap_result <- .cap_rank_by_threshold(
      lca, top_score, rank_thresholds,
      rank_system, taxa_unique
    )
    if (!is.na(cap_result$rank) && cap_result$rank != lca$rank) {
      rank_capped <- TRUE
      consensus_reason <- "threshold"
    }
    lca <- cap_result
    is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  }

  # Step 5: whitelist upranking
  if (!is.null(whitelist) && !is.na(lca$taxon)) {
    uprank_result <- .uprank_to_whitelist(
      lca, whitelist, taxa_unique,
      rank_system
    )
    if (!is.na(uprank_result$rank) && uprank_result$rank != lca$rank) {
      whitelist_capped <- TRUE
    }
    # If upranking failed entirely (no whitelist match at any rank),
    # mark as unresolvable
    if (is.na(uprank_result$taxon)) {
      whitelist_capped <- TRUE
    }
    lca <- uprank_result
    is_resolved <- !is.na(lca$rank) && lca$rank == finest_rank
  }

  out <- data.frame(
    observation_id = sid,
    consensus_taxon = lca$taxon,
    consensus_rank = lca$rank,
    consensus_reason = consensus_reason,
    is_resolved = is_resolved,
    top_score = top_score,
    n_retained = n_retained,
    n_taxa = n_taxa,
    retained_taxa = I(list(taxa_unique$taxon_name)),
    stringsAsFactors = FALSE
  )
  if (!is.null(rank_thresholds)) out$rank_capped <- rank_capped
  if (!is.null(whitelist)) out$whitelist_capped <- whitelist_capped
  out
}


#' Cap consensus rank based on score thresholds
#'
#' If the top score does not meet the threshold for the current consensus rank,
#' demotes to the coarsest rank whose threshold IS met.  If no threshold is met,
#' returns NA (unresolvable).
#'
#' Also re-derives the consensus taxon at the demoted rank from the retained
#' hits (all retained hits must agree at the new rank).
#' @noRd
.cap_rank_by_threshold <- function(lca, top_score, rank_thresholds,
                                   rank_system, taxa_df) {
  # Find the finest rank whose threshold the top score meets (vectorized:
  # threshold_ranks is already ordered finest-to-coarsest, so the first TRUE
  # is the answer).
  threshold_ranks <- intersect(rev(rank_system), names(rank_thresholds))
  meets_threshold <- top_score >= unlist(rank_thresholds[threshold_ranks], use.names = FALSE)
  first_met <- which(meets_threshold)[1L]
  allowed_rank <- if (is.na(first_met)) NA_character_ else threshold_ranks[[first_met]]

  if (is.na(allowed_rank)) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  # If current LCA rank is already at or coarser than allowed_rank, no change
  lca_idx <- match(lca$rank, rank_system)
  allowed_idx <- match(allowed_rank, rank_system)
  if (!is.na(lca_idx) && lca_idx <= allowed_idx) {
    return(lca)
  }

  # Demote: find the LCA at the allowed rank
  vals <- .extract_rank_values(taxa_df, allowed_rank)
  vals <- vals[!is.na(vals)]
  if (length(vals) == 0L) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  if (length(unique(vals)) == 1L) {
    return(list(taxon = vals[[1L]], rank = allowed_rank))
  }

  # Multiple values at allowed_rank — walk coarser to find agreement
  allowed_idx_in_sys <- match(allowed_rank, rank_system)
  if (is.na(allowed_idx_in_sys) || allowed_idx_in_sys <= 1L) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  for (i in seq(allowed_idx_in_sys - 1L, 1L)) {
    rk <- rank_system[i]
    vals <- .extract_rank_values(taxa_df, rk)
    vals <- vals[!is.na(vals)]
    if (length(vals) > 0 && length(unique(vals)) == 1L) {
      return(list(taxon = vals[[1L]], rank = rk))
    }
  }

  list(taxon = NA_character_, rank = NA_character_)
}


#' Uprank consensus to the nearest whitelisted rank
#'
#' If the consensus taxon is in the whitelist, returns it unchanged.
#' Otherwise, walks from the current rank toward coarser ranks, checking at
#' each rank whether all retained candidates agree on a value that appears
#' in the whitelist.
#' @noRd
.uprank_to_whitelist <- function(lca, whitelist, taxa_df, rank_system) {
  if (is.na(lca$taxon)) {
    return(lca)
  }

  # Check if current consensus is in whitelist

  if (lca$taxon %in% whitelist) {
    return(lca)
  }

  # Walk coarser from the current rank
  cur_idx <- match(lca$rank, rank_system)
  if (is.na(cur_idx)) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  if (cur_idx <= 1L) {
    return(list(taxon = NA_character_, rank = NA_character_))
  }

  for (i in seq(cur_idx - 1L, 1L)) {
    rk <- rank_system[i]
    vals <- .extract_rank_values(taxa_df, rk)
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0L) next
    if (length(unique(vals)) == 1L && vals[[1L]] %in% whitelist) {
      return(list(taxon = vals[[1L]], rank = rk))
    }
  }

  list(taxon = NA_character_, rank = NA_character_)
}

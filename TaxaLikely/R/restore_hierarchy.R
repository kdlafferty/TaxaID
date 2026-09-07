# ==============================================================================
# Score-sourcing hierarchy for restore_suppressed_candidates()
# ==============================================================================
# Implements SPEC_restore_suppressed_candidates_redesign.md Section 3a: a
# cheap-to-expensive hierarchy that replaces the old flat `anchor_score -
# delta` imputation with a real, evidence-grounded score for a restored
# candidate. Levels 1-3 are free (already-computed seq_matrix/model lookups);
# Level 4 (live Tier 2 pairwise alignment, via .check_regional_overlap()'s
# return_detail = TRUE mode) is the only expensive step, gated by the caller
# via check_regional_overlap/the compute-budget mechanism in
# .compute_budget_ratio() below. All levels return a raw match proportion on
# the SAME (0,1] scale build_sequence_matrix()'s p_match already uses, so
# restore_suppressed_candidates() only has to rescale once (to match_obj's
# own 0-100 vs 0-1 score scale) regardless of which level resolved a
# candidate.
#
# Aggregation is median, never max or a random pick, at every level that can
# see more than one qualifying value (Section 4) -- max is an upward-biased
# order statistic (a well-referenced species draws more pairs from the same
# underlying similarity distribution, inflating its expected max for reasons
# unrelated to true similarity), confirmed on real 12S data (Sections 4-5a).

#' Strip version suffixes from a vector of accessions, cached per align_cache
#' @noRd
.stripped_seq_matrix_ids <- function(seq_matrix, align_cache) {
  use_cache <- !is.null(align_cache) && is.environment(align_cache)
  if (use_cache && exists("seq_matrix_ids", envir = align_cache, inherits = FALSE)) {
    return(get("seq_matrix_ids", envir = align_cache, inherits = FALSE))
  }
  ids <- list(
    id_x = sub("\\.[0-9]+$", "", seq_matrix$id_x),
    id_y = sub("\\.[0-9]+$", "", seq_matrix$id_y)
  )
  if (use_cache) assign("seq_matrix_ids", ids, envir = align_cache)
  ids
}

#' Build (once per align_cache) an accession-indexed lookup of seq_matrix
#' pairs.
#'
#' Found necessary 2026-07-19, live-testing the redesign against the real
#' PtConception 12S dataset (13,442 observations, 226 genera present, some
#' (e.g. Sebastes) with 100+ reference species, seq_matrix ~3M rows): every
#' naive per-candidate lookup (`id_x == acc & id_y %in% ...`) is an
#' O(nrow(seq_matrix)) scan, and R's `%in%`/`match()` rebuilds its internal
#' hash table over the right-hand side on EVERY call -- it does not cache
#' across repeated calls against the same (unchanging) seq_matrix. Under
#' Purpose A's unconditional genus-wide sweep this scan runs once per
#' candidate species, for every observation, with zero memoization (unlike
#' Level 4's align_cache). Measured real cost: one real Sebastes anchor
#' against its 106 congeners took 19.06s (73.7% in `%in%`), and a SECOND,
#' identical anchor (simulating a repeat observation) took 17.64s again --
#' confirming no caching benefit at all, and explaining a 70+-minute real
#' run on this dataset (Mugu's largest genus, Fundulus, only had 20 species
#' and a ~1.36M-row seq_matrix, never exposing this).
#'
#' This builds a real index once per call instead: `split()` groups every
#' pair's partner accession + p_match by BOTH sides' own accession (each
#' pair contributes to two groups, one per side), so a subsequent lookup for
#' any one accession is a single list/hash access, not a linear scan. Cached
#' the same way every other align_cache-keyed structure here is.
#' @noRd
.seq_matrix_partner_index <- function(seq_matrix, align_cache) {
  use_cache <- !is.null(align_cache) && is.environment(align_cache)
  key <- "seq_matrix_partner_index"
  if (use_cache && exists(key, envir = align_cache, inherits = FALSE)) {
    return(get(key, envir = align_cache, inherits = FALSE))
  }

  ids <- .stripped_seq_matrix_ids(seq_matrix, align_cache)
  combined_acc <- c(ids$id_x, ids$id_y)
  combined_partner <- c(ids$id_y, ids$id_x)
  combined_pmatch <- rep(seq_matrix$p_match, 2L)

  index <- list(
    partners = split(combined_partner, combined_acc),
    pmatch   = split(combined_pmatch, combined_acc)
  )
  if (use_cache) assign(key, index, envir = align_cache)
  index
}

#' O(1) lookup: every partner accession + p_match for pairs involving `acc`.
#' Returns `list(partner = character(0), p_match = numeric(0))` when `acc`
#' has no seq_matrix presence at all (rather than NULL), so callers can
#' `c()`/index into the result unconditionally.
#' @noRd
.seq_matrix_lookup <- function(acc, index) {
  p <- index$partners[[acc]]
  m <- index$pmatch[[acc]]
  if (is.null(p)) {
    list(partner = character(0L), p_match = numeric(0L))
  } else {
    list(partner = p, p_match = m)
  }
}

#' Level 0 precheck: does this SPECIES (any of its own reference accessions)
#' have ANY seq_matrix representation at all (as id_x or id_y, against
#' anything, not just the current genus)?
#'
#' Species-level, not accession-level, per the design spec: a species with
#' several reference accessions, only one of which happens to be the
#' anchor's own accession, can still have real seq_matrix presence via its
#' OTHER accessions (exactly the Level 2 rescue case) -- checking only the
#' single anchor accession would wrongly route straight to Level 4 for that
#' case instead of letting Level 2 try. When NO accession of the species
#' appears anywhere (e.g. its only references are out-of-range mitogenomes
#' that never entered build_sequence_matrix()'s alignment -- the real
#' F. lima case), Levels 1-3 are all provably futile, not just unlucky, so
#' the caller should route straight to Level 4. Cached per accession set per
#' align_cache since the same anchor species is often shared across many
#' observations (Session 159's own align_cache precedent).
#' @noRd
.has_seq_matrix_presence <- function(accessions, seq_matrix, align_cache) {
  accessions <- accessions[!is.na(accessions)]
  if (is.null(seq_matrix) || !is.data.frame(seq_matrix) || nrow(seq_matrix) == 0L ||
    !all(c("id_x", "id_y") %in% names(seq_matrix)) || length(accessions) == 0L) {
    return(FALSE)
  }

  use_cache <- !is.null(align_cache) && is.environment(align_cache)
  key <- paste0("l0_presence::", paste(sort(accessions), collapse = ","))
  if (use_cache && exists(key, envir = align_cache, inherits = FALSE)) {
    return(get(key, envir = align_cache, inherits = FALSE))
  }

  index <- .seq_matrix_partner_index(seq_matrix, align_cache)
  present <- any(accessions %in% names(index$partners))
  if (use_cache) assign(key, present, envir = align_cache)
  present
}

#' Resolve a restored candidate's imputed score via the Section 3a hierarchy
#'
#' Tries, in order, Level 1 (direct accession-pair `p_match`), Level 2
#' (any-accession species-pair `p_match`), Level 3 (genus-level typical
#' divergence -- `model_params$H2_Lookup$delta_shrunk` preferred, raw
#' within-genus cross-species median `p_match` as a no-model fallback).
#' Levels 1-3 are only attempted when the anchor's SPECIES (any of its own
#' reference accessions) has SOME seq_matrix presence at all (the Level 0
#' precheck) -- when it doesn't, this
#' function returns immediately with `level = NA_integer_`, signalling the
#' caller to try Level 4 (`.check_regional_overlap(..., return_detail =
#' TRUE)`) instead, which this function deliberately does not attempt itself
#' (Level 4 is expensive and budget-gated by the caller).
#'
#' @return A list `(p_match, level, source, source_accession)`. `p_match` is
#'   `NA_real_` and `level`/`source` are `NA` when nothing resolved.
#'   `source_accession` is a real, single NCBI accession ONLY for a Level 1
#'   resolution backed by exactly one distinct candidate accession -- `NA`
#'   for every other case (Levels 2-4 all aggregate across more than one
#'   accession by construction, so no single accession can be honestly
#'   named as "the" source). See `restore_suppressed_candidates()`'s own
#'   `restoration_level`/`restoration_source_accession` output columns,
#'   which surface this field for external screening (e.g.
#'   `TaxaMatch::evaluate_reference_accessions()`) of restored rows.
#' @noRd
.resolve_hierarchy_score <- function(anchor_accession, anchor_species, candidate_species,
                                     genus, ref_genus_rows, species_col,
                                     seq_matrix, model_params, score_transform,
                                     align_cache) {
  unresolved <- list(
    p_match = NA_real_, level = NA_integer_, source = NA_character_,
    source_accession = NA_character_
  )

  anchor_accession <- sub("\\.[0-9]+$", "", anchor_accession)
  has_sm <- !is.null(seq_matrix) && is.data.frame(seq_matrix) && nrow(seq_matrix) > 0L &&
    all(c("id_x", "id_y", "p_match") %in% names(seq_matrix))

  anchor_accessions <- unique(sub(
    "\\.[0-9]+$", "",
    ref_genus_rows$composite_id[ref_genus_rows[[species_col]] == anchor_species]
  ))
  anchor_accessions <- anchor_accessions[!is.na(anchor_accessions)]

  if (!has_sm || !.has_seq_matrix_presence(anchor_accessions, seq_matrix, align_cache)) {
    return(unresolved)
  } # Level 0 precheck failed (or no seq_matrix at all) -- route to Level 4

  index <- .seq_matrix_partner_index(seq_matrix, align_cache)

  cand_accessions <- unique(sub(
    "\\.[0-9]+$", "",
    ref_genus_rows$composite_id[ref_genus_rows[[species_col]] == candidate_species]
  ))
  cand_accessions <- cand_accessions[!is.na(cand_accessions)]

  # ---- Level 1: direct accession-pair p_match --------------------------------
  # source_accession: set ONLY when exactly one distinct candidate accession
  # contributed the value(s) behind p_match -- an unambiguous, directly-
  # screenable accession (see restore_suppressed_candidates()'s own
  # `RESTORED_<accession>` provenance tag and the 2026-08-08 screenability
  # discussion this field exists to support). NA whenever more than one
  # candidate accession contributed (the median then blends real evidence
  # from several accessions, none of which can honestly be singled out).
  if (!is.na(anchor_accession) && length(cand_accessions) > 0L) {
    lk <- .seq_matrix_lookup(anchor_accession, index)
    contributing <- lk$partner[lk$partner %in% cand_accessions & !is.na(lk$p_match)]
    vals <- lk$p_match[lk$partner %in% cand_accessions]
    vals <- vals[!is.na(vals)]
    if (length(vals) > 0L) {
      distinct_contributors <- unique(contributing)
      src_acc <- if (length(distinct_contributors) == 1L) distinct_contributors else NA_character_
      return(list(
        p_match = stats::median(vals), level = 1L, source = "direct_accession",
        source_accession = src_acc
      ))
    }
  }

  # ---- Level 2: any-accession species-pair p_match ----------------------------
  if (length(cand_accessions) > 0L && length(anchor_accessions) > 0L) {
    lks <- lapply(anchor_accessions, .seq_matrix_lookup, index = index)
    all_partner <- unlist(lapply(lks, `[[`, "partner"), use.names = FALSE)
    all_pmatch <- unlist(lapply(lks, `[[`, "p_match"), use.names = FALSE)
    vals <- all_pmatch[all_partner %in% cand_accessions]
    vals <- vals[!is.na(vals)]
    if (length(vals) > 0L) {
      return(list(
        p_match = stats::median(vals), level = 2L, source = "species_pair",
        source_accession = NA_character_
      ))
    }
  }

  # ---- Level 3: genus-level typical divergence --------------------------------
  # 3 (preferred): model-based, Empirical-Bayes-shrunk genus delta.
  if (!is.null(model_params) && !is.null(model_params$H2_Lookup) &&
    nrow(model_params$H2_Lookup) > 0L) {
    gidx <- match(genus, model_params$H2_Lookup$genus)
    if (!is.na(gidx)) {
      anchor_mu <- NA_real_
      if (!is.null(model_params$H1_Lookup) && nrow(model_params$H1_Lookup) > 0L) {
        aidx <- match(anchor_species, model_params$H1_Lookup$lookup_key)
        if (!is.na(aidx)) anchor_mu <- model_params$H1_Lookup$mu_score[aidx]
      }
      if ((is.na(anchor_mu)) && !is.null(model_params$H1_Global_Mu)) {
        anchor_mu <- unname(model_params$H1_Global_Mu[["score_logit"]] %||%
          model_params$H1_Global_Mu[1L])
      }
      if (!is.na(anchor_mu)) {
        cand_transform <- anchor_mu - model_params$H2_Lookup$delta_shrunk[gidx]
        p <- .untransform_p(cand_transform, method = score_transform)
        return(list(
          p_match = p, level = 3L, source = "genus_model",
          source_accession = NA_character_
        ))
      }
    }
  }
  # 3 (fallback, no model or no genus-specific entry): raw genus-wide median
  # cross-species p_match already present in seq_matrix, ignoring which two
  # specific species are involved. Looks up each genus accession's partner
  # list once (index, not a whole-matrix scan) -- every real pair is seen
  # from BOTH accessions' own lookup, i.e. counted twice, but that's exact,
  # not approximate: doubling a value multiset uniformly leaves its median
  # unchanged (verified: median(c(x,x)) == median(x) for any x), so this is
  # a genuine speedup, not a precision tradeoff.
  genus_accessions <- unique(sub("\\.[0-9]+$", "", ref_genus_rows$composite_id))
  genus_accessions <- genus_accessions[!is.na(genus_accessions)]
  if (length(genus_accessions) > 1L) {
    acc_sp_map <- stats::setNames(
      ref_genus_rows[[species_col]],
      sub("\\.[0-9]+$", "", ref_genus_rows$composite_id)
    )
    lks <- lapply(genus_accessions, .seq_matrix_lookup, index = index)
    n_partners <- lengths(lapply(lks, `[[`, "partner"))
    all_acc <- rep(genus_accessions, n_partners)
    all_partner <- unlist(lapply(lks, `[[`, "partner"), use.names = FALSE)
    all_pmatch <- unlist(lapply(lks, `[[`, "p_match"), use.names = FALSE)
    within_genus <- all_partner %in% genus_accessions
    if (any(within_genus)) {
      sp_x <- unname(acc_sp_map[all_acc[within_genus]])
      sp_y <- unname(acc_sp_map[all_partner[within_genus]])
      cross <- !is.na(sp_x) & !is.na(sp_y) & sp_x != sp_y
      vals <- all_pmatch[within_genus][cross]
      vals <- vals[!is.na(vals)]
      if (length(vals) > 0L) {
        return(list(
          p_match = stats::median(vals), level = 3L, source = "genus_raw_median",
          source_accession = NA_character_
        ))
      }
    }
  }

  unresolved
}

#' Compute-budget mechanism (Section 3b): should Level 4 (live Tier 2
#' alignment) be attempted for this specific anchor/candidate pair?
#'
#' Revised 2026-07-18 after live-testing against two real motivating cases
#' (Mugu `Fundulus lima`/`parvipinnis`, PtConception `Girella simplicidens`/
#' `nigricans`) found the original ratio-only design had a real hole: BOTH
#' real anchors are themselves absent from `taxaexpect_priors` (correctly --
#' they're the occurrence-implausible species this whole mechanism exists to
#' out-compete), which made `R = P_anchor / P_candidate` uncomputable and the
#' old version skip Level 4 for EVERY candidate -- including the one that
#' matters. Real cost measured on the Fundulus case: restoring one marker's
#' 12S data went from a documented ~38s (pre-redesign, `candidate_species_
#' filter`-gated) to ~276s, because Purpose A's genus-wide sweep sent every
#' one of Fundulus's 20 species to a live 16kb-mitogenome alignment.
#'
#' Two-tier gate now, cheapest/most-certain first:
#' \enumerate{
#'   \item \strong{`candidate_species_filter` (default gate, restored from
#'     the pre-redesign design):} a candidate on the caller-supplied
#'     plausibility list -- or ANY candidate, when no filter was supplied at
#'     all (`candidate_species_filter = NULL`, matching Purpose B's own
#'     "no filter = unrestricted" convention) -- is always worth checking.
#'     This is what `candidate_species_filter` did before the Purpose A/B
#'     redesign, restored here specifically for Level 4 (the one expensive
#'     step) -- Levels 1-3 remain fully filter-independent, so Purpose A's
#'     free-tier genus-wide sweep is unaffected.
#'   \item \strong{Floor-vs-documented ratio (fallback, only consulted for a
#'     candidate NOT on the filter):} `R = P_anchor / P_candidate` at the
#'     observation's own grid cell, derived from `posterior_consensus()`'s
#'     `min_posterior` filter (default `0.05`): `R <= 19` is worth spending
#'     Level 4 budget on. Lets a real, prior-supported candidate the static
#'     filter happened to miss still get checked. `R` not being computable
#'     at all (either species absent from `taxaexpect_priors` for this grid
#'     cell -- true for both real anchors above) is treated the same as
#'     `R > 19` -- skip.
#' }
#' @noRd
.worth_level4_check <- function(anchor_species, candidate_species, grid_id,
                                taxaexpect_priors, candidate_species_filter = NULL,
                                taxon_col = "taxon_name",
                                grid_col = "grid_id", theta_col = "theta_mean",
                                budget_ratio_cap = 19) {
  if (is.null(candidate_species_filter) || candidate_species %in% candidate_species_filter) {
    return(TRUE)
  }

  if (is.null(taxaexpect_priors)) {
    return(FALSE)
  } # not on the filter, no ratio possible
  if (is.na(grid_id) ||
    !all(c(taxon_col, grid_col, theta_col) %in% names(taxaexpect_priors))) {
    return(FALSE)
  } # not computable -- treated the same as R > budget_ratio_cap

  rows <- taxaexpect_priors[!is.na(taxaexpect_priors[[grid_col]]) &
    taxaexpect_priors[[grid_col]] == grid_id, , drop = FALSE]
  a_theta <- rows[[theta_col]][match(anchor_species, rows[[taxon_col]])]
  c_theta <- rows[[theta_col]][match(candidate_species, rows[[taxon_col]])]

  if (length(a_theta) == 0L || length(c_theta) == 0L ||
    is.na(a_theta) || is.na(c_theta) || c_theta <= 0) {
    return(FALSE)
  } # absent from taxaexpect_priors entirely -- not computable

  ratio <- a_theta / c_theta
  isTRUE(ratio <= budget_ratio_cap)
}

#' Option C backstop (2026-07-18): a hard cap on how many DISTINCT candidates
#' get a live Level 4 alignment attempt per anchor accession, independent of
#' `.worth_level4_check()`'s plausibility-filter/ratio gate -- insurance
#' against a large or absent `candidate_species_filter` (or a
#' `taxaexpect_priors` ratio that happens to admit many candidates) still
#' forcing an unbounded number of expensive alignments for one anchor.
#' Counts attempts, not successes -- a candidate that fails Level 4
#' (`regional_reject`/`no_reference_data`) still consumes a slot, since the
#' alignment itself was the expensive part regardless of its outcome.
#' Cache-keyed per `anchor_accession` in `align_cache`, so the cap applies
#' once across every observation in one `restore_suppressed_candidates()`
#' call sharing that anchor, not per observation.
#' @noRd
.level4_attempt_allowed <- function(anchor_accession, max_per_anchor, align_cache) {
  if (is.infinite(max_per_anchor)) {
    return(TRUE)
  }
  use_cache <- !is.null(align_cache) && is.environment(align_cache)
  if (!use_cache) {
    return(TRUE)
  } # cannot track without a cache -- fail open

  key <- paste0("l4_attempts::", anchor_accession)
  n <- if (exists(key, envir = align_cache, inherits = FALSE)) {
    get(key, envir = align_cache, inherits = FALSE)
  } else {
    0L
  }
  if (n >= max_per_anchor) {
    return(FALSE)
  }
  assign(key, n + 1L, envir = align_cache)
  TRUE
}

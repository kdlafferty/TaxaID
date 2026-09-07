# NSE column names referenced via dplyr verbs below would otherwise trip an
# R CMD CHECK "no visible binding" note.
utils::globalVariables(c(
  "id_x", "id_y", "p_match", "is_independent", "is_sufficient_coverage",
  "is_species_resolved_y",
  "is_valid_partner", "below_min_congruent", "n_independent_top_matches",
  "n_top_matches_available", "frac_independent_below_min_congruent_rank",
  "finest_common_rank", "k_disagree",
  "hierarchy_flag", "evaluated_at", "cache_hit", "accession", "listed_taxon",
  "species.y"
))

# ==============================================================================
# evaluate_reference_accessions() -- per-accession BLAST-based reference
# quality evaluation
#
# Implements ecosystem_docs/REENTRY_PROMPT_blast_based_reference_quality.md.
# Supersedes the taxon-list-scoped DECIPHER whole-set alignment approach
# (TaxaLikely::audit_reference_database()/classify_reference_accessions(),
# archived at TaxaLikely/archive_decipher_reference_audit/) for the specific
# question this function answers: is a single accession's OWN listed taxon
# congruent with what independent NCBI evidence actually says, evaluated
# against the broadest comparison population BLAST can reach -- not just
# whatever else a caller's own `taxa` argument happened to fetch.
# ==============================================================================

#' Cache-version tag for evaluate_reference_accessions()
#'
#' Bump this any time an internal computation detail changes the verdict
#' without any caller-visible parameter changing -- otherwise a cached row
#' computed under the OLD logic is served as a "fresh" cache hit forever
#' under an unchanged `params_key`. Cheap insurance, not something a caller
#' ever sets directly. History:
#' \itemize{
#'   \item{`v4_hybrid_maternal_proxy` (2026-08-11) -- the 2026-08-13
#'     `require_species_resolved_partner` fix deliberately did NOT bump it,
#'     matching the 2026-08-11 modifier-prefix precedent: `params_key` is one
#'     global string applied uniformly to every cached row, so a bump forces
#'     a full re-BLAST of every real cached row, and that fix's effect was
#'     narrow (the rows worth re-checking were removed from the real cache by
#'     hand instead).}
#'   \item{`v5_amplicon_query` (2026-09-03) -- the query submitted to BLAST
#'     changed from the primer-INCLUSIVE trimmed span to the primer-STRIPPED
#'     amplicon (`query_span = "amplicon"`), which changes what the hit list
#'     can contain (see [evaluate_reference_accessions()]'s `@section Why the
#'     query is the primer-stripped amplicon`). A bump IS warranted here, and
#'     [migrate_reference_cache()] exists so the ~3,000 real cached rows are
#'     not all re-BLASTed for it: `"congruent"` rows are carried forward
#'     (stripping primers only ADDS short-deposit hits, it cannot withdraw a
#'     match already observed), everything else re-evaluates.}
#' }
#' @noRd
.EVAL_REF_ACC_VERSION <- "v5_amplicon_query"

#' Build the one global params_key every cached row is stamped with
#'
#' Factored out of [evaluate_reference_accessions()] (2026-09-03) so
#' [migrate_reference_cache()] can compute the key the current defaults
#' would produce with the SAME code, rather than a second hand-maintained
#' `paste()`. Every argument that affects the verdict itself is in the key;
#' call mechanics (`chunk_size`, TTLs, `max_query_len`, `max_batch_bp`,
#' `prioritize_uncached`, `retry_insufficient`, `skip_locally_corroborated`)
#' are deliberately NOT -- changing one must never invalidate a cache. See
#' `@section Caching` in [evaluate_reference_accessions()].
#'
#' `query_span` (2026-09-03) IS in the key: it changes what is submitted to
#' BLAST and therefore what the hit list can contain.
#' @noRd
.build_params_key <- function(top_n, min_congruent_rank, submission_window,
                              hierarchy_incongruent_threshold, min_independent_partners,
                              score_range, min_score, max_hits, method, database,
                              query_span) {
  paste(top_n, min_congruent_rank, submission_window,
        hierarchy_incongruent_threshold, min_independent_partners,
        score_range, min_score, max_hits, method, database,
        query_span, .EVAL_REF_ACC_VERSION, sep = "|")
}

#' The params_key evaluate_reference_accessions()'s own defaults produce
#'
#' Reads the defaults off the function's formals, so this can never drift
#' from the signature. `match.arg()`-style vector defaults (`method`,
#' `query_span`) resolve to their first element, exactly as the function
#' itself resolves them.
#' @noRd
.default_params_key <- function() {
  f <- formals(evaluate_reference_accessions)
  first_of <- function(x) { v <- eval(x); v[[1L]] }
  .build_params_key(
    top_n = eval(f$top_n), min_congruent_rank = eval(f$min_congruent_rank),
    submission_window = eval(f$submission_window),
    hierarchy_incongruent_threshold = eval(f$hierarchy_incongruent_threshold),
    min_independent_partners = eval(f$min_independent_partners),
    score_range = eval(f$score_range), min_score = eval(f$min_score),
    max_hits = eval(f$max_hits), method = first_of(f$method),
    database = eval(f$database), query_span = first_of(f$query_span)
  )
}

#' Strip a GenBank version suffix ("ACC.1" -> "ACC"), the ecosystem convention
#' @noRd
.strip_acc_version <- function(x) sub("\\.[0-9]+$", "", x)

#' Add any column the persistent cache carries that new rows lack
#'
#' [migrate_reference_cache()] stamps a `migrated_from` column onto the cache
#' file; rows computed afterwards do not have it, and
#' `rbind(cache, new_rows[, names(cache)])` would error on the absent column.
#' `NA`-fills, then orders to the cache's own columns.
#' @noRd
#' Cache columns that may be NA-filled rather than forcing a full discard
#'
#' `.load_reference_accession_cache()` discards an entire cache file whose
#' columns do not match this version's schema, because serving a row that is
#' missing a column some consumer reads is worse than re-BLASTing it. That is
#' the right default and stays the default -- but it makes EVERY additive
#' column cost a full re-evaluation of every cached row (~3,000 across the
#' real PtConception and GreatLakes caches), which is the same price this
#' package refuses to pay for a `params_key` change. The effect was that a
#' purely diagnostic column could not be added at all.
#'
#' A column may be listed here ONLY if `NA` is a safe reading of it for a row
#' computed before it existed -- meaning nothing anywhere turns that `NA`
#' into a different DECISION than the row would otherwise get. That is a
#' strict test, and most columns fail it: `congruent_evidence_exists_anywhere`
#' would be catastrophic (`!(NA %in% TRUE)` is `TRUE`, so an NA-filled row
#' becomes MORE removable), and `n_independent_top_matches` now drives the
#' zero-partner rule in `score_reference_labels()`. Provenance and pure
#' diagnostics pass; anything a verdict, an action, a veto or a TTL consults
#' does not.
#'
#' Adding a column here is therefore a deliberate claim, in the same spirit as
#' deciding whether a new parameter belongs in `params_key`.
#' @noRd
.ADDITIVE_CACHE_COLUMNS <- c(
  "taxonomy_resolution_source",  # provenance of the query-side lineage
  "migrated_from",               # provenance of a migrated row
  "query_len_submitted",         # diagnostic: bp actually sent to BLAST
  "query_trim_path",             # diagnostic: which rescue produced it
  "n_excluded_same_batch",       # diagnostic: hits lost to the independence filter
  "n_excluded_not_species_resolved",  # diagnostic: hits lost to the species-resolution filter
  "local_corroborator_accession"  # provenance: which accession vouches for a locally_corroborated row
)

#' Typed NA vector matching a prototype column
#' @noRd
.na_like <- function(proto, n) proto[rep(NA_integer_, n)]

.align_to_cache_columns <- function(rows, cache) {
  for (nm in setdiff(names(cache), names(rows))) rows[[nm]] <- rep(NA, nrow(rows))
  rows[, names(cache), drop = FALSE]
}

#' Per-accession attributes for the same-submission-batch independence rule
#'
#' Duplicated from `TaxaLikely::.build_submission_batch_lookup()`
#' (`TaxaLikely/archive_decipher_reference_audit/R/hierarchy_congruence.R`) --
#' TaxaMatch must not depend on TaxaLikely (the ecosystem's documented
#' dependency direction is TaxaMatch -> TaxaLikely, never the reverse), so
#' this ~30-line helper is duplicated rather than reached for via `:::`.
#' Mirrors an already-existing precedent between these exact two packages:
#' `.parse_lat_lon()` is deliberately duplicated between
#' `TaxaLikely/R/fetch.R` and `TaxaMatch/R/blast_sequences.R` for the
#' identical reason.
#'
#' @param reference_df Needs `composite_id` and, optionally, `create_date`
#'   (as a `"%Y/%m/%d"`-formatted string -- see
#'   `.fetch_reference_accession_records()`'s own date reformatting, done
#'   specifically so this duplicated helper's parsing logic can stay
#'   byte-identical to the archived original).
#' @return One row per unique `composite_id`: `composite_id`, `acc_date`
#'   (parsed `Date`, `NA` if `create_date` absent/unparseable), `acc_prefix`,
#'   `acc_num` (accession-number heuristic components, `NA` if the accession
#'   doesn't match the simple `<letters><digits>` shape).
#' @noRd
.build_submission_batch_lookup <- function(reference_df) {
  ref_ids  <- reference_df$composite_id
  has_date <- "create_date" %in% names(reference_df)
  parsed_date <- if (has_date) {
    suppressWarnings(as.Date(reference_df$create_date, format = "%Y/%m/%d"))
  } else {
    rep(as.Date(NA), length(ref_ids))
  }
  is_simple_acc <- grepl("^[A-Za-z]+[0-9]+$", ref_ids)
  acc_prefix <- ifelse(is_simple_acc, sub("^([A-Za-z]+)[0-9]+$", "\\1", ref_ids),
                       NA_character_)
  # suppressWarnings(): as.numeric() runs (and warns) on the whole vector
  # before ifelse() selects from it, including the non-matching accessions
  # whose sub() left them unchanged (a non-numeric string) -- the NA those
  # produce is exactly what's wanted and always discarded by is_simple_acc
  # anyway; only the "NAs introduced by coercion" warning is spurious noise.
  acc_num    <- suppressWarnings(ifelse(
    is_simple_acc, as.numeric(sub("^[A-Za-z]+([0-9]+)$", "\\1", ref_ids)), NA_real_
  ))

  lookup <- data.frame(
    composite_id = ref_ids, acc_date = parsed_date,
    acc_prefix = acc_prefix, acc_num = acc_num,
    stringsAsFactors = FALSE
  )
  lookup[!duplicated(lookup$composite_id), , drop = FALSE]
}

#' Vectorised same-submission-batch test
#'
#' Duplicated from `TaxaLikely::.same_submission_batch()` -- see
#' `.build_submission_batch_lookup()`'s own roxygen for why this is a
#' duplicate rather than a cross-package reach. EITHER signal firing (OR'd)
#' means same-batch.
#' @noRd
.same_submission_batch <- function(x_date, x_prefix, x_num,
                                   y_date, y_prefix, y_num,
                                   submission_window) {
  date_same_batch <- !is.na(x_date) & !is.na(y_date) &
    abs(as.numeric(x_date - y_date)) <= submission_window
  acc_same_batch <- !is.na(x_prefix) & !is.na(y_prefix) & x_prefix == y_prefix &
    !is.na(x_num) & !is.na(y_num) & abs(x_num - y_num) < submission_window
  date_same_batch | acc_same_batch
}

#' Compute per-accession taxonomic-hierarchy congruence against independent close matches
#'
#' Duplicated (math unchanged) from
#' `TaxaLikely::.compute_hierarchy_congruence()` -- see that archived
#' function's own roxygen
#' (`TaxaLikely/archive_decipher_reference_audit/R/hierarchy_congruence.R`)
#' for the full design rationale (why the independence filter exists, why a
#' naive top-N nearest-neighbour check is defeated by the exact replicated-
#' contamination case this mechanism exists to catch, why the fraction is
#' Jeffreys-smoothed). What's genuinely adapted here, not duplicated, is the
#' CALLER (`evaluate_reference_accessions()`): the archived version always
#' fed this function a `seq_matrix` built from one big DECIPHER whole-set
#' alignment scoped to a caller's own `taxa` list; the caller here instead
#' builds an equivalent `id_x`/`id_y`/`p_match`/`{rank}.x`/`{rank}.y`-shaped
#' table directly from real, unrestricted BLAST hits -- a genuinely
#' different, broader comparison population, fed through the identical,
#' already-validated congruence math unchanged.
#'
#' @section 2026-08-07 divergence from the archived TaxaLikely original:
#' This copy is no longer byte-identical to the archived version -- it now
#' also computes percent-identity and "is there ANY corroborating evidence
#' at all, even outside the top_n window" diagnostics (`best_hit_pident`,
#' `best_agreeing_pident`, `best_disagreeing_pident`,
#' `congruent_evidence_exists_anywhere`, `congruent_evidence_best_pident`),
#' per an Opus design-consult finding: `hierarchy_flag`/`finest_common_rank`
#' alone cannot distinguish a genuine mislabel from "correct label, but this
#' marker has poor resolving power at this rank for this clade and GenBank
#' has thin coverage at the listed rank" -- both produce identical
#' `(k, n, finest_common_rank)`. Two real accessions
#' (`Abylopsis eschscholtzii`, `KY594854`/`KX384617`) flagged `"incongruent"`
#' with top hits all >=99% identity to a SISTER family within the same
#' order -- indistinguishable, under the old columns, from a genuinely
#' unrelated 99%-identity hit, which would be a much stronger mislabel
#' signal. Both new pieces of information were already being computed and
#' then discarded: `p_match` was used only to ORDER hits before being
#' dropped; whether the listed rank is corroborated ANYWHERE in the full
#' independence-filtered hit pool (not just the `top_n`-truncated slice) is
#' free once the rank-agreement walk below runs over the untruncated pool
#' instead of after truncating. The archived original at
#' `TaxaLikely/archive_decipher_reference_audit/R/hierarchy_congruence.R` is
#' NOT updated to match -- it is dead code, kept for historical reference
#' only, not a shared implementation to keep in sync.
#'
#' @section 2026-08-13 divergence, continued: gains
#' `require_species_resolved_partner` (default `TRUE`) -- excludes a
#' comparison partner whose own listed species isn't resolved to species
#' level from the vote entirely (`is_valid_partner`, alongside the
#' existing independence/coverage filters). See
#' `evaluate_reference_accessions()`'s own `@section Species-resolved
#' comparison partners` for the full real-data motivation and
#' verification.
#'
#' @section 2026-08-13 divergence, continued further: gains
#' `best_disagreeing_taxon` -- the listed species of the same highest-
#' identity independent hit `best_disagreeing_pident` is already computed
#' from (both read off the same position in the same desc(p_match)-sorted
#' slice, so the two stay consistent by construction). Implements the
#' reentry prompt's own Question 2 finding that a second-look reviewer
#' (human or LLM) needs the disagreeing taxon's actual NAME, not just its
#' identity percentage, to recognize e.g. a known hybrid-cross partner or an
#' informal specimen code -- previously computed as part of the rank-
#' agreement walk and then discarded, the same "already computed, silently
#' dropped" pattern the 2026-08-07 identity diagnostics themselves were.
#' `NA` when no independent hit disagrees.
#' @noRd
.compute_hierarchy_congruence <- function(seq_matrix,
                                          reference_df,
                                          rank_system,
                                          top_n              = 5L,
                                          min_congruent_rank = "family",
                                          submission_window  = 5L,
                                          min_coverage        = NULL,
                                          require_species_resolved_partner = TRUE) {

  rank_system <- tolower(rank_system)
  min_congruent_rank <- tolower(min_congruent_rank)
  if (!min_congruent_rank %in% rank_system)
    stop(sprintf(
      "min_congruent_rank ('%s') must be one of rank_system's own ranks: %s",
      min_congruent_rank, paste(rank_system, collapse = ", ")
    ), call. = FALSE)
  min_rank_idx <- which(rank_system == min_congruent_rank)

  lookup <- .build_submission_batch_lookup(reference_df)

  x_lookup <- lookup
  names(x_lookup) <- c("id_x", "x_date", "x_prefix", "x_num")
  y_lookup <- lookup
  names(y_lookup) <- c("id_y", "y_date", "y_prefix", "y_num")

  sm <- seq_matrix |>
    dplyr::left_join(x_lookup, by = "id_x") |>
    dplyr::left_join(y_lookup, by = "id_y")

  sm$is_independent <- !.same_submission_batch(
    sm$x_date, sm$x_prefix, sm$x_num, sm$y_date, sm$y_prefix, sm$y_num, submission_window
  )

  if (!is.null(min_coverage) && "coverage" %in% names(sm)) {
    cov_vals <- sm[["coverage"]]
    sm$is_sufficient_coverage <- is.na(cov_vals) | cov_vals >= min_coverage
  } else {
    sm$is_sufficient_coverage <- TRUE
  }

  # A comparison partner (id_y) whose OWN listed species isn't resolved to
  # species level (e.g. "Serranidae sp. JL-2015" -- a family name used in
  # place of a genus, with an informal specimen code) isn't meaningful
  # evidence either way: whether it happens to "agree" or "disagree" with
  # the query's own rank columns says little when its own identity is
  # itself only fuzzily determined. Found live, 2026-08-11/13, on the real
  # GreatLakes Stereolepis doederleini case -- both real accessions of this
  # genuinely rare, taxonomically isolated species (Polyprionidae has only
  # 2 genera) read "incongruent" purely because the one real independent
  # hit available to disagree with them WAS this exact non-species-resolved
  # accession. Reuses TaxaTools::is_plausible_binomial() (no new logic,
  # same check `listed_taxon_is_species` already applies to the QUERY side
  # -- this applies the identical standard to the HIT side). `species.y` is
  # `NA` when taxonomy resolution found no species-rank entry at all for
  # that hit -- treated the same as a non-binomial string (excluded), not
  # differently -- both mean "this partner's own species identity isn't
  # usable evidence."
  if (require_species_resolved_partner && "species.y" %in% names(sm)) {
    sm$is_species_resolved_y <- ifelse(
      is.na(sm$species.y), FALSE, TaxaTools::is_plausible_binomial(sm$species.y)
    )
  } else {
    sm$is_species_resolved_y <- TRUE
  }

  sm$is_valid_partner <- sm$is_independent & sm$is_sufficient_coverage & sm$is_species_resolved_y

  # Guarantee species.y always exists before it's referenced (below, and by
  # any caller lacking it) -- mirrors the is_species_resolved_y guard just
  # above, which already tolerates a seq_matrix without species.y.
  if (!"species.y" %in% names(sm)) sm$species.y <- NA_character_

  n_available <- sm |>
    dplyr::count(id_x, name = "n_top_matches_available")

  # WHY a hit did not become a voting partner (2026-09-04). Every one of
  # these numbers was already implicit in `sm` and then discarded, so a
  # zero-partner accession gave no way to tell "BLAST found nothing" from
  # "BLAST found twenty hits and every one was the accession's own
  # submission batch" -- a distinction that has to be re-derived by hand
  # every time the question comes up, and that changes what to do about it.
  # Real motivating case: GreatLakes Plate1's zero-partner population is 24
  # of 27 insufficient rows and is dominated by Phoxinus and Etheostoma, a
  # shape completely unlike PtConception's, and nothing in the cached output
  # said which filter was responsible.
  #
  # The two counts PARTITION the excluded hits rather than overlapping: the
  # species-resolution count is conditional on having passed independence,
  # so `available - same_batch - not_species_resolved` is the number that
  # survived both (before the coverage filter, which is off by default).
  n_excluded <- sm |>
    dplyr::group_by(id_x) |>
    dplyr::summarise(
      n_excluded_same_batch = sum(!is_independent),
      n_excluded_not_species_resolved = sum(is_independent & !is_species_resolved_y),
      .groups = "drop"
    )

  # Rank-agreement walk over the FULL independence/coverage-filtered pool,
  # BEFORE truncating to top_n -- deliberately, not the same step as before.
  # This is what makes `congruent_evidence_exists_anywhere` a genuinely
  # different question from `hierarchy_flag` itself: "is there corroborating
  # evidence ANYWHERE GenBank has it" vs. "do the top_n closest hits
  # corroborate it." p_match ordering means the top_n slice almost always
  # contains the single best-identity agreeing hit if one exists at all, but
  # NOT necessarily every agreeing hit, which matters for the "does the
  # listed rank have ANY representation" diagnostic specifically.
  valid <- sm[sm$is_valid_partner, , drop = FALSE]
  finest_idx <- rep(NA_integer_, nrow(valid))
  for (j in seq_along(rank_system)) {
    r <- rank_system[j]
    xcol <- valid[[paste0(r, ".x")]]
    ycol <- valid[[paste0(r, ".y")]]
    if (is.null(xcol) || is.null(ycol)) next
    agree <- !is.na(xcol) & !is.na(ycol) & xcol == ycol
    finest_idx[agree] <- j
  }
  valid$finest_common_rank  <- ifelse(is.na(finest_idx), NA_character_,
                                      rank_system[finest_idx])
  valid$below_min_congruent <- is.na(finest_idx) | finest_idx < min_rank_idx

  # .safe_max(): max() on a possibly-empty or all-NA vector errors/warns
  # ("no non-missing arguments") -- NA is the correct, quiet answer for
  # "no hit exists in this category," not an error.
  .safe_max <- function(x) if (length(x) == 0L || all(is.na(x))) NA_real_ else max(x, na.rm = TRUE)

  # .safe_first_valid(): first non-NA value of x among positions where cond
  # is TRUE. `sliced` (below) is already arranged desc(p_match) within each
  # id_x group before this runs, so applied to species.y/below_min_congruent
  # this returns the listed species of the SAME highest-identity disagreeing
  # hit best_disagreeing_pident's own .safe_max(p_match[below_min_congruent])
  # is computed from -- the two stay consistent with each other by
  # construction, not by a second independent computation.
  .safe_first_valid <- function(x, cond) {
    v <- x[cond]
    v <- v[!is.na(v)]
    if (length(v) == 0L) NA_character_ else v[[1L]]
  }

  # "Anywhere" diagnostic -- congruent evidence exists ANYWHERE in the full
  # independence-filtered pool, not limited to top_n.
  anywhere <- valid |>
    dplyr::group_by(id_x) |>
    dplyr::summarise(
      congruent_evidence_exists_anywhere = any(!below_min_congruent),
      congruent_evidence_best_pident = .safe_max(p_match[!below_min_congruent]) * 100,
      .groups = "drop"
    )

  sliced <- valid |>
    dplyr::group_by(id_x) |>
    dplyr::arrange(dplyr::desc(p_match), .by_group = TRUE) |>
    dplyr::slice_head(n = top_n) |>
    dplyr::ungroup()

  agg <- sliced |>
    dplyr::group_by(id_x) |>
    dplyr::summarise(
      finest_common_rank        = dplyr::first(finest_common_rank),
      n_independent_top_matches = dplyr::n(),
      k_disagree                = sum(below_min_congruent),
      best_hit_pident            = dplyr::first(p_match) * 100,
      best_agreeing_pident        = .safe_max(p_match[!below_min_congruent]) * 100,
      best_disagreeing_pident     = .safe_max(p_match[below_min_congruent]) * 100,
      best_disagreeing_taxon      = .safe_first_valid(species.y, below_min_congruent),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      frac_independent_below_min_congruent_rank =
        (k_disagree + 0.5) / (n_independent_top_matches + 1)
    ) |>
    dplyr::select(-k_disagree)

  all_ids <- unique(seq_matrix$id_x)
  out <- data.frame(id_x = all_ids, stringsAsFactors = FALSE) |>
    dplyr::left_join(agg, by = "id_x") |>
    dplyr::left_join(n_available, by = "id_x") |>
    dplyr::left_join(n_excluded, by = "id_x") |>
    dplyr::left_join(anywhere, by = "id_x")

  out$n_independent_top_matches <- ifelse(
    is.na(out$n_independent_top_matches), 0L, out$n_independent_top_matches
  )
  out$n_top_matches_available <- ifelse(
    is.na(out$n_top_matches_available), 0L, out$n_top_matches_available
  )
  out$n_excluded_same_batch <- ifelse(
    is.na(out$n_excluded_same_batch), 0L, out$n_excluded_same_batch
  )
  out$n_excluded_not_species_resolved <- ifelse(
    is.na(out$n_excluded_not_species_resolved), 0L, out$n_excluded_not_species_resolved
  )
  out$frac_independent_below_min_congruent_rank <- ifelse(
    is.na(out$frac_independent_below_min_congruent_rank),
    0.5, out$frac_independent_below_min_congruent_rank
  )
  out$congruent_evidence_exists_anywhere <- ifelse(
    is.na(out$congruent_evidence_exists_anywhere), FALSE, out$congruent_evidence_exists_anywhere
  )

  # Per-partner pair table, carried out as an attribute rather than folded
  # into the returned per-accession frame (whose one-row-per-accession shape
  # every caller already depends on). This is the ONLY place the individual
  # votes behind `frac_independent_below_min_congruent_rank` exist -- they
  # were previously built, summarised, and discarded, so no verdict could
  # ever be recomputed without a fresh BLAST. `refine_reference_verdicts()`
  # (Thread 1 of REENTRY_PROMPT_reference_quality_verdicts_and_downstream_
  # use.md) needs exactly these rows to re-run the vote with each partner
  # weighted by its own trustworthiness.
  #
  # `pair_finest_common_rank` is stored rather than the derived
  # `below_min_congruent` boolean deliberately: the boolean is a function of
  # `min_congruent_rank`, the rank is not, so a stored pair table stays
  # reusable if a caller later re-votes at a different rank.
  attr(out, "pair_table") <- data.frame(
    id_x                    = valid$id_x,
    id_y                    = valid$id_y,
    p_match                 = valid$p_match,
    pair_finest_common_rank = valid$finest_common_rank,
    species_y               = valid$species.y,
    stringsAsFactors        = FALSE
  )
  out
}

#' Fetch full GenBank records for the accessions being evaluated
#'
#' One combined `rentrez::entrez_fetch(rettype = "gb", retmode = "xml")` call
#' per batch gives sequence, listed organism, and submission create-date all
#' at once -- the same endpoint `.resolve_locations_by_acc()`
#' (`R/blast_sequences.R`) already uses successfully for accession-keyed
#' NCBI lookups, extended here to also parse `GBSeq_sequence` and
#' `GBSeq_organism`. Matches results back to the caller's own requested
#' accession strings via a version-suffix-stripped join (same defensive
#' pattern `.resolve_locations_by_acc()`'s own caller already uses) so the
#' returned `accession` column is always exactly what the caller asked for,
#' never NCBI's own (possibly version-free) `GBSeq_primary-accession` value
#' -- this matters because that returned string becomes `id_x`/`composite_id`
#' for the hierarchy-congruence join downstream.
#'
#' `create_date` is reformatted from GBSeq's `"DD-MON-YYYY"` string to
#' `"%Y/%m/%d"` specifically so the duplicated `.build_submission_batch_lookup()`
#' (which parses with `format = "%Y/%m/%d"`, matching the archived original
#' byte-for-byte) can stay unchanged.
#'
#' @param accessions Character vector, deduped, as requested by the caller.
#' @param want_sequence Logical. `FALSE` skips parsing `GBSeq_sequence`
#'   (cheaper to hold in memory; the fetch cost is identical either way,
#'   `rettype = "gb"` doesn't support selectively omitting it) -- used for
#'   BLAST hit accessions, where only `create_date` is needed.
#' @return data.frame(accession, sequence -- `NA` if `want_sequence = FALSE`,
#'   organism, create_date). One row per accession successfully found;
#'   accessions NCBI has no record for are simply absent (caller compares
#'   against the requested vector via `setdiff()`).
#' @noRd
.fetch_reference_accession_records <- function(accessions,
                                               want_sequence = TRUE,
                                               ncbi_api_key = NULL,
                                               verbose = TRUE) {
  empty <- data.frame(accession = character(0L), sequence = character(0L),
                      organism = character(0L), create_date = character(0L),
                      stringsAsFactors = FALSE)

  .check_pkg("rentrez")
  .check_pkg("xml2")

  if (!is.null(ncbi_api_key) && nzchar(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  accessions <- unique(accessions[!is.na(accessions) & nzchar(accessions)])
  if (length(accessions) == 0L) return(empty)

  batch_size <- 100L
  batches    <- split(accessions, ceiling(seq_along(accessions) / batch_size))
  res        <- vector("list", length(batches))

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    if (verbose)
      message(sprintf("Fetching NCBI records: batch %d/%d (%d accessions)...",
                      i, length(batches), length(batch)))
    for (attempt in 1:3) {
      fetched <- tryCatch({
        xml_raw <- rentrez::entrez_fetch(
          db = "nuccore", id = batch, rettype = "gb", retmode = "xml"
        )
        xml_doc <- xml2::read_xml(xml_raw)
        nodes   <- xml2::xml_find_all(xml_doc, "//GBSeq")

        parsed <- do.call(rbind, lapply(nodes, function(node) {
          acc <- xml2::xml_text(xml2::xml_find_first(node, "./GBSeq_primary-accession"))
          org <- xml2::xml_text(xml2::xml_find_first(node, "./GBSeq_organism"))
          cd_raw <- xml2::xml_text(xml2::xml_find_first(node, "./GBSeq_create-date"))
          cd_parsed <- suppressWarnings(as.Date(cd_raw, format = "%d-%b-%Y"))
          seq_val <- if (want_sequence) {
            gsub("[[:space:]]", "", tolower(
              xml2::xml_text(xml2::xml_find_first(node, "./GBSeq_sequence"))
            ))
          } else {
            NA_character_
          }
          data.frame(
            .primary_accession = acc,
            sequence = seq_val,
            organism = if (nzchar(org)) org else NA_character_,
            create_date = if (!is.na(cd_parsed)) format(cd_parsed, "%Y/%m/%d") else NA_character_,
            stringsAsFactors = FALSE
          )
        }))
        parsed
      }, error = function(e) {
        if (attempt < 3L) {
          Sys.sleep(attempt * 2)
          NULL
        } else {
          if (verbose) warning(sprintf(
            "NCBI record fetch failed for batch %d: %s", i, conditionMessage(e)
          ), call. = FALSE)
          data.frame(.primary_accession = character(0L), sequence = character(0L),
                    organism = character(0L), create_date = character(0L),
                    stringsAsFactors = FALSE)
        }
      })
      if (!is.null(fetched)) { res[[i]] <- fetched; break }
    }
    if (i < length(batches)) Sys.sleep(0.4)
  }

  parsed_all <- do.call(rbind, Filter(Negate(is.null), res))
  if (is.null(parsed_all) || nrow(parsed_all) == 0L) return(empty)

  # Version-suffix-stripped join back to the caller's own requested strings --
  # GBSeq_primary-accession is version-free; the caller's accessions may or
  # may not carry a version suffix. One requested accession can match at
  # most one parsed record under this stripping (both sides deduped/unique
  # per batch), so this is a safe 1:1 attach, not a fan-out join.
  strip_v <- function(x) sub("\\.[0-9]+$", "", x)
  req_df  <- data.frame(accession = accessions, .join = strip_v(accessions),
                        stringsAsFactors = FALSE)
  parsed_all$.join <- strip_v(parsed_all$.primary_accession)

  out <- merge(req_df, parsed_all[, c(".join", "sequence", "organism", "create_date")],
              by = ".join", all.x = FALSE, all.y = FALSE, sort = FALSE)
  out$.join <- NULL
  out[!duplicated(out$accession), , drop = FALSE]
}

#' Load the persistent per-accession evaluation cache
#' @noRd
.load_reference_accession_cache <- function(cache_dir) {
  empty <- data.frame(
    accession = character(0L), listed_taxon = character(0L),
    n_independent_top_matches = integer(0L), n_top_matches_available = integer(0L),
    frac_independent_below_min_congruent_rank = numeric(0L),
    finest_common_rank = character(0L),
    best_hit_pident = numeric(0L), best_agreeing_pident = numeric(0L),
    best_disagreeing_pident = numeric(0L), best_disagreeing_taxon = character(0L),
    congruent_evidence_exists_anywhere = logical(0L),
    congruent_evidence_best_pident = numeric(0L),
    hierarchy_flag = character(0L),
    evaluated_at = as.POSIXct(character(0L)), params_key = character(0L),
    taxonomy_resolution_source = character(0L),
    query_len_submitted = integer(0L), query_trim_path = character(0L),
    n_excluded_same_batch = integer(0L),
    n_excluded_not_species_resolved = integer(0L),
    local_corroborator_accession = character(0L),
    stringsAsFactors = FALSE
  )
  if (is.null(cache_dir)) return(empty)
  path <- file.path(cache_dir, "reference_accession_cache.rds")
  if (!file.exists(path)) return(empty)
  cached <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(cached) || !is.data.frame(cached)) return(empty)

  # A cache file written by an OLDER package version can be missing columns
  # this version expects (found live: a real cache from before the
  # 2026-08-07 identity-diagnostics columns were added). params_key already
  # invalidates individual STALE ROWS on an internal-logic version bump
  # (.EVAL_REF_ACC_VERSION) -- but that can't rescue a file whose COLUMN
  # SCHEMA itself doesn't match, since `cache_hit_rows[, out_cols]` would
  # error on a genuinely absent column regardless of how many (zero or
  # more) rows survive the params_key filter. Discarding the whole file and
  # starting fresh is the correct, safe response to a schema mismatch --
  # symmetric with how a params_key mismatch already discards individual
  # rows -- not a partial/patched read.
  #
  # UPDATED 2026-09-04: a column listed in .ADDITIVE_CACHE_COLUMNS is
  # NA-filled instead, because for those columns NA is the honest reading of
  # "this row was computed before we recorded that" and nothing turns it into
  # a different decision. Discarding for those was costing a full re-BLAST of
  # every cached row to add a diagnostic -- the same price this package
  # refuses to pay for a params_key change. Any OTHER missing column still
  # discards the whole file, unchanged: that is the case where serving the
  # row could silently change a verdict.
  missing_cols <- setdiff(names(empty), names(cached))
  hard_missing <- setdiff(missing_cols, .ADDITIVE_CACHE_COLUMNS)
  if (length(hard_missing) > 0L) {
    warning(sprintf(
      "evaluate_reference_accessions(): cache at %s predates this package version (missing column(s): %s) -- starting a fresh cache. Every previously-cached verdict will be recomputed once.",
      path, paste(hard_missing, collapse = ", ")
    ), call. = FALSE)
    return(empty)
  }
  soft_missing <- intersect(missing_cols, .ADDITIVE_CACHE_COLUMNS)
  if (length(soft_missing) > 0L) {
    for (nm in soft_missing) cached[[nm]] <- .na_like(empty[[nm]], nrow(cached))
    message(sprintf(
      "evaluate_reference_accessions(): cache at %s predates %d additive diagnostic column(s) (%s) -- filled with NA. No verdict is affected and nothing is re-BLASTed; the column(s) populate as accessions are re-evaluated.",
      path, length(soft_missing), paste(soft_missing, collapse = ", ")
    ))
  }
  cached
}

#' Persist the per-accession evaluation cache
#' @noRd
.save_reference_accession_cache <- function(cache_dir, cache_df) {
  if (is.null(cache_dir)) return(invisible(NULL))
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(cache_dir, "reference_accession_cache.rds")
  saveRDS(cache_df, path)
  invisible(NULL)
}

#' Sidecar cache of the per-partner votes behind each accession's verdict
#'
#' A SECOND file in the same `cache_dir`, deliberately not folded into
#' `reference_accession_cache.rds`: that file is strictly one row per
#' accession and several consumers rely on it (including
#' `.load_reference_accession_cache()`'s own schema check, which discards a
#' whole file whose columns don't match). The pair table is one row per
#' (accession, valid comparison partner) -- a different grain entirely.
#'
#' Being a separate file also makes it purely ADDITIVE: an existing cache
#' directory with no `reference_pair_cache.rds` keeps working unchanged, and
#' simply has no pair data until its accessions are re-evaluated. Nothing
#' reads this file except [refine_reference_verdicts()], which degrades to a
#' documented no-op for any accession absent from it.
#'
#' @param cache_dir Character or `NULL` (no-op).
#' @return `.load_reference_pair_cache()`: a data frame with columns
#'   `id_x`, `id_y`, `p_match`, `pair_finest_common_rank`, `species_y`,
#'   `params_key`, `evaluated_at` -- zero rows if the file is absent or its
#'   schema doesn't match (same discard-and-start-fresh policy as the
#'   per-accession cache, for the same reason: a partially-readable file is
#'   worse than none).
#' @noRd
.empty_reference_pair_cache <- function() {
  data.frame(
    id_x = character(0L), id_y = character(0L), p_match = numeric(0L),
    pair_finest_common_rank = character(0L), species_y = character(0L),
    params_key = character(0L), evaluated_at = as.POSIXct(character(0L)),
    stringsAsFactors = FALSE
  )
}

#' @noRd
.load_reference_pair_cache <- function(cache_dir) {
  empty <- .empty_reference_pair_cache()
  if (is.null(cache_dir)) return(empty)
  path <- file.path(cache_dir, "reference_pair_cache.rds")
  if (!file.exists(path)) return(empty)
  cached <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.data.frame(cached) || !all(names(empty) %in% names(cached))) {
    if (!is.null(cached))
      warning(sprintf(
        "Discarding pair cache at %s -- unexpected schema. It will be rebuilt as accessions are re-evaluated.",
        path
      ), call. = FALSE)
    return(empty)
  }
  cached[, names(empty), drop = FALSE]
}

#' @noRd
.save_reference_pair_cache <- function(cache_dir, pair_df) {
  if (is.null(cache_dir)) return(invisible(NULL))
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(pair_df, file.path(cache_dir, "reference_pair_cache.rds"))
  invisible(NULL)
}

#' Evaluate One Chunk of Accessions -- Fetch, BLAST, Score
#'
#' Extracted from `evaluate_reference_accessions()`'s own body (2026-08-14,
#' see `ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md`'s
#' chunking/circuit-breaker follow-on work) so the caller can run it once per
#' CHUNK of `needs_eval` accessions and write the persistent cache
#' incrementally after each one, instead of once for the entire accession
#' list at the very end -- see `evaluate_reference_accessions()`'s own
#' `@section Chunked evaluation and NCBI rate-limiting resilience` for the
#' full rationale. Byte-identical logic to what this function's body used to
#' do inline; `chunk_acc` plays the role `needs_eval` used to play, scoped to
#' one chunk instead of the whole call.
#'
#' `max_query_len`/`max_batch_bp` (2026-09-01, see
#' `ecosystem_docs/REENTRY_PROMPT_eval_ref_accessions_long_sequence_robustness.md`)
#' implement the hard submission cap and length-aware BLAST batching -- see
#' `evaluate_reference_accessions()`'s own `@section Long-sequence
#' robustness` for the full design.
#'
#' @return A list: `computed_rows` (data.frame or `NULL`, same shape the
#'   caller writes to the persistent cache), `missing_acc` (character
#'   vector -- accessions in `chunk_acc` not evaluated this call: not found,
#'   no usable sequence, or BLAST did not complete), `circuit_breaker_
#'   tripped` (logical -- `TRUE` when this chunk's own `blast_sequences()`
#'   call reported sustained batch failures and stopped early; see
#'   `blast_sequences(max_consecutive_batch_failures=)`).
#' @noRd
.evaluate_reference_accessions_chunk <- function(chunk_acc, rank_system, method, database,
                                                 score_range, min_score, max_hits,
                                                 ncbi_api_key, poll_max_wait, barcode_term,
                                                 max_consecutive_batch_failures,
                                                 max_query_len, max_batch_bp,
                                                 top_n, min_congruent_rank, submission_window,
                                                 min_independent_partners,
                                                 hierarchy_incongruent_threshold,
                                                 params_key, now, verbose,
                                                 query_span = "amplicon") {
  strip_primers <- identical(query_span, "amplicon")

  # ---- Fetch the accessions being evaluated: sequence + listed taxon +
  # create_date, all from one GBSeq XML round trip -----------------------------
  query_meta_raw <- .fetch_reference_accession_records(
    chunk_acc, want_sequence = TRUE, ncbi_api_key = ncbi_api_key, verbose = verbose
  )
  not_found_acc <- setdiff(chunk_acc, query_meta_raw$accession)
  query_meta <- query_meta_raw[!is.na(query_meta_raw$sequence) &
                               nzchar(query_meta_raw$sequence), , drop = FALSE]
  # An accession NCBI has a record for but with no usable sequence content
  # (e.g. GBSeq_sequence omitted for an extremely large record) is a
  # distinct failure mode from "not found at all" -- both are folded into
  # one missing_acc set so neither silently vanishes from the output.
  no_sequence_acc <- setdiff(query_meta_raw$accession, query_meta$accession)
  missing_acc <- union(not_found_acc, no_sequence_acc)
  if (length(missing_acc) > 0L)
    warning(sprintf(
      "evaluate_reference_accessions(): %d accession(s) could not be evaluated this call (not found, or no usable sequence content) -- will retry next call, not cached:\n  %s",
      length(missing_acc), paste(missing_acc, collapse = ", ")
    ), call. = FALSE)

  # Why a query was NOT rescued by the feature-table fallback, one value per
  # row (NA where the fallback was never attempted or succeeded). Initialised
  # up front so mechanism 2 can read it unconditionally, including on the
  # barcode_term = NULL path where no fallback runs at all.
  query_meta$fallback_decline <- rep(NA_character_, nrow(query_meta))
  # Which rescue, if any, produced the sequence that will be submitted.
  # "as_deposited" until something shortens it.
  query_meta$trim_path <- rep("as_deposited", nrow(query_meta))

  if (!is.null(barcode_term) && nrow(query_meta) > 0L) {
    trimmed <- .trim_queries_to_amplicon(
      query_meta$sequence, barcode_term = barcode_term,
      strip_primers = strip_primers, verbose = verbose
    )
    was_trimmed <- attr(trimmed, "trimmed")
    if (!is.null(was_trimmed))
      query_meta$trim_path[was_trimmed %in% TRUE] <- "primer_match"
    query_meta$sequence <- as.character(trimmed)

    # ---- Mechanism 1: feature-table-guided extraction fallback for a query
    # STILL over the marker's own length window after primer trimming
    # (primer site(s) not found, or an implausible matched span) -- see
    # .extract_feature_table_fallback() (R/trim_query_to_amplicon.R) for the
    # full mechanism. Only reachable when barcode_term is supplied (the same
    # precondition primer trimming itself already requires).
    # .resolve_trimmed_span_max(), NOT resolve_barcode_lengths()$max_bp.
    # `.trim_queries_to_amplicon()` returns a primer-INCLUSIVE span
    # (211-233 bp for MiFish-U); max_bp reports the variable region
    # EXCLUDING primers (130-210 bp). Those windows are disjoint, so the
    # original test called every correctly-trimmed query "still over-length"
    # -- 100% of them, by construction -- and sent each one through an extra
    # NCBI annotation fetch that could not help it. Measured 2026-09-02 on a
    # real run: "extracted the amplicon from 40 of 40" immediately followed
    # by "feature-table fallback rescued 40 of 40 still-over-length", which
    # cannot both be true. This is the same primer-length miscalibration
    # `.trim_queries_to_amplicon()` was itself fixed for on 2026-08-10,
    # reintroduced here; both sites now read one shared definition -- and,
    # since 2026-09-03, the bound for whichever span (`query_span`) the
    # trimmer was asked for.
    bt_max_len <- .resolve_trimmed_span_max(barcode_term, strip_primers = strip_primers)
    if (!is.na(bt_max_len)) {
      still_over <- !is.na(query_meta$sequence) & nchar(query_meta$sequence) > bt_max_len
      if (any(still_over)) {
        rescued <- .extract_feature_table_fallback(
          accessions = query_meta$accession[still_over],
          sequences  = query_meta$sequence[still_over],
          barcode_term = barcode_term, ncbi_api_key = ncbi_api_key, verbose = verbose
        )
        # Capture the decline reason BEFORE the assignment below -- writing a
        # character vector into a data-frame column drops its attributes, and
        # this is the only place the annotation evidence exists. Mechanism 2
        # reads it to tell a wrong-marker record apart from a merely long one.
        decline <- attr(rescued, "decline_reason")
        query_meta$fallback_decline[still_over] <- decline
        # A rescued row is one the fallback recorded no decline reason for.
        query_meta$trim_path[which(still_over)[is.na(decline)]] <- "feature_table"
        query_meta$sequence[still_over] <- as.character(rescued)
      }
    }
  }

  # ---- Mechanism 2: hard submission cap. After BOTH rescue strategies
  # above, any query still longer than max_query_len is NOT submitted to
  # BLAST -- a full-length mitogenome (or larger) that neither primer-
  # matched nor had a usable feature-table annotation would otherwise be
  # BLASTed at full length, consuming orders of magnitude more server CPU
  # than a short amplicon and risking a real CPU-budget rejection (see
  # barcode_term's own documentation for the real captured case). The
  # contract this revises ("never discards or errors, only shortens or
  # leaves unchanged") is honored EXPLICITLY, not silently: such an
  # accession gets a real, labeled cached row (hierarchy_flag =
  # "not_evaluated_oversized") below, with the same insufficient-evidence-
  # style TTL (retryable after expiry, so a future annotation/primer fix or
  # a raised max_query_len can rescue it later) -- never just dropped.
  oversized_rows <- NULL
  if (nrow(query_meta) > 0L && is.finite(max_query_len)) {
    seq_lens <- nchar(query_meta$sequence)
    is_oversized <- !is.na(seq_lens) & seq_lens > max_query_len
    if (any(is_oversized)) {
      oversized_meta <- query_meta[is_oversized, , drop = FALSE]
      # ---- Wrong marker, not wrong size (2026-09-04). An accession the
      # feature-table fallback declined with "marker_absent" HAS annotated
      # features and none of them is the marker `barcode_term` implies. Its
      # length is a symptom; the cause is that it does not belong in this
      # screen's candidate set at all, which is the actionable thing to tell a
      # reviewer -- "oversized" implies a size problem the caller could fix by
      # raising max_query_len, and for this class no length ever helps.
      # Real case: HM561627 (Lasiurus intermedius), 2,657 bp, whose GBSeq
      # feature table contains exactly one feature -- 16S ribosomal RNA,
      # spanning 1061-2657 -- in a 12S (MiFishU) screen. It was 1 of 1
      # oversized accessions on the real 995-accession PtConception run.
      is_wrong_marker <- oversized_meta$fallback_decline %in% "marker_absent"
      oversized_rows <- data.frame(
        accession = oversized_meta$accession,
        listed_taxon = oversized_meta$organism,
        n_independent_top_matches = NA_integer_,
        n_top_matches_available = NA_integer_,
        frac_independent_below_min_congruent_rank = NA_real_,
        finest_common_rank = NA_character_,
        best_hit_pident = NA_real_, best_agreeing_pident = NA_real_,
        best_disagreeing_pident = NA_real_, best_disagreeing_taxon = NA_character_,
        congruent_evidence_exists_anywhere = NA,
        congruent_evidence_best_pident = NA_real_,
        hierarchy_flag = ifelse(is_wrong_marker,
                                "not_evaluated_wrong_marker",
                                "not_evaluated_oversized"),
        evaluated_at = now,
        cache_hit = FALSE,
        params_key = params_key,
        taxonomy_resolution_source = NA_character_,
        query_len_submitted = NA_integer_,   # never submitted
        query_trim_path = oversized_meta$trim_path,
        n_excluded_same_batch = NA_integer_,
        n_excluded_not_species_resolved = NA_integer_,
        local_corroborator_accession = NA_character_,
        stringsAsFactors = FALSE
      )
      if (verbose) {
        if (any(!is_wrong_marker))
          message(sprintf(
            "evaluate_reference_accessions(): %d accession(s) still exceed max_query_len (%d bp) after trimming/feature-table extraction -- deferred as 'not_evaluated_oversized', never submitted to BLAST:\n  %s",
            sum(!is_wrong_marker), as.integer(max_query_len),
            paste(oversized_meta$accession[!is_wrong_marker], collapse = ", ")
          ))
        if (any(is_wrong_marker))
          message(sprintf(
            "evaluate_reference_accessions(): %d accession(s) carry annotated features but none for the marker '%s' implies -- deferred as 'not_evaluated_wrong_marker' (they do not belong in this screen's candidate set; raising max_query_len cannot help):\n  %s",
            sum(is_wrong_marker), barcode_term,
            paste(oversized_meta$accession[is_wrong_marker], collapse = ", ")
          ))
      }
      query_meta <- query_meta[!is_oversized, , drop = FALSE]
    }
  }

  computed_rows <- NULL
  pair_table    <- NULL
  circuit_breaker_tripped <- FALSE

  if (nrow(query_meta) > 0L) {
    # ---- Query's own full kingdom->species lineage, via the SAME NCBI
    # taxonomy-resolution mechanism already used for BLAST hits
    # (.resolve_taxonomy_by_acc() -> .resolve_taxonomy(), both internal to
    # this file) -- guarantees the query and hit sides of every comparison
    # are classified by the identical authority/rank definitions, rather
    # than mixing NCBI's own taxonomy DB (hits) with a GNVerifier-backed
    # backbone lookup (the previous TaxaTools::fill_higher_ranks()-based
    # approach, which also only ever resolved genus+family, never the
    # coarser ranks this section exists to add).
    query_tax <- .resolve_taxonomy_by_acc(query_meta$accession, ncbi_api_key, verbose)
    for (r in rank_system) {
      col <- paste0(r, ".x")
      query_meta[[col]] <- if (r %in% names(query_tax)) {
        query_tax[[r]][match(query_meta$accession, query_tax$accession)]
      } else {
        NA_character_
      }
    }
    # species.x should read exactly what THIS accession's own GenBank record
    # says, not the taxonomy DB's scientific name for its taxid (usually
    # identical, but the record's own listed organism is the more direct,
    # more defensible value for "the label being evaluated").
    query_meta$species.x <- query_meta$organism

    # ---- Hybrid-labeled accessions: NCBI's own taxonomy for a hybrid-cross
    # organism is genuinely incomplete (confirmed live, 2026-08-10, against
    # real GreatLakes candidates -- lineage stops at "unclassified
    # Cyprinoidei", no family/genus/species) -- see this function's own
    # @section Hybrid-labeled accessions for the full mechanism and why
    # it's biologically correct to substitute the maternal parent's real
    # lineage at every rank coarser than species. Detection requires BOTH
    # signals: a standalone " x " token in the listed organism name (the
    # standard nomenclatural hybrid marker) AND the accession's own
    # resolved family being unresolvable -- an ordinary non-hybrid taxon
    # with a genuinely incomplete NCBI lineage is never routed through this
    # maternal-parent substitution, which has no biological justification
    # without a real hybrid cross.
    query_meta$taxonomy_resolution_source <- "direct"
    if ("family" %in% rank_system) {
      is_hybrid_labeled <- grepl("(?<=\\s)x(?=\\s)", query_meta$organism, perl = TRUE)
      needs_proxy <- is_hybrid_labeled & is.na(query_meta[["family.x"]])

      if (any(needs_proxy)) {
        # TaxaTools::clean_taxon_names() (2026-08-11 onward) already strips
        # a single leading breeding/ploidy-manipulation modifier word (e.g.
        # "androgenetic", "autodiploid", "autotetraploid" -- all found on
        # real GreatLakes Carassius/Megalobrama hybrid records) before its
        # own capital-letter filter, using a curated, safety-vetted word
        # list (deliberately excludes uncertainty-hedge words like
        # "possible"/"putative", which must keep failing the filter, not
        # get silently rescued) -- see that function's own roxygen for the
        # full list and reasoning. No local pre-processing needed here;
        # calling it directly is both simpler and keeps this single-source-
        # of-truth behavior available to every other caller in the
        # ecosystem, not just this one mechanism.
        proxy_name <- rep(NA_character_, nrow(query_meta))
        proxy_name[needs_proxy] <- TaxaTools::clean_taxon_names(query_meta$organism[needs_proxy])
        has_proxy <- needs_proxy & !is.na(proxy_name)

        if (any(has_proxy)) {
          proxy_verified <- tryCatch(
            TaxaTools::verify_taxon_names(unique(proxy_name[has_proxy]), backbone_id = 4L),
            error = function(e) NULL
          )
          if (!is.null(proxy_verified) && nrow(proxy_verified) > 0L) {
            for (r in setdiff(rank_system, "species")) {
              proxy_rank_val <- mapply(
                TaxaTools::parse_classification_path,
                proxy_verified$classification_path, proxy_verified$classification_ranks,
                MoreArgs = list(target_rank = r)
              )
              resolved <- proxy_rank_val[match(proxy_name[has_proxy], proxy_verified$user_supplied_name)]
              query_meta[[paste0(r, ".x")]][has_proxy] <- resolved
            }
            query_meta$taxonomy_resolution_source[has_proxy] <- "hybrid_maternal_proxy"
          }
        }
        query_meta$taxonomy_resolution_source[needs_proxy & !has_proxy] <- "hybrid_unresolved"

        if (verbose && any(has_proxy))
          message(sprintf(
            "evaluate_reference_accessions(): %d hybrid-labeled accession(s) resolved via maternal parent species proxy.",
            sum(has_proxy)
          ))
      }
    }

    # ---- BLAST every chunk_acc accession's own sequence against the
    # broad, unrestricted database in one batched call ------------------------
    seq_df <- data.frame(asv_id = query_meta$accession, sequence = query_meta$sequence,
                         stringsAsFactors = FALSE)
    hits <- blast_sequences(
      seq_df, method = method, database = database, score_range = score_range,
      min_score = min_score, max_hits = max_hits, resolve_taxonomy = TRUE,
      ncbi_api_key = ncbi_api_key, poll_max_wait = poll_max_wait,
      max_consecutive_batch_failures = max_consecutive_batch_failures,
      max_batch_bp = max_batch_bp, verbose = verbose
    )
    circuit_breaker_tripped <- isTRUE(attr(hits, "circuit_breaker_tripped"))

    # An accession whose BLAST search never completed (timed out, even after
    # blast_sequences()'s own halved-batch-size retry, OR skipped outright
    # because blast_sequences()'s own circuit breaker tripped) must NOT flow
    # through to a computed hierarchy_flag below -- it would read identically
    # to a genuine zero-hit "insufficient_independent_evidence" verdict and
    # get cached as one, silently. Folded into missing_acc/query_meta
    # exclusion here so it gets the exact same "not cached, will retry next
    # call" treatment as an accession NCBI has no record for at all. See
    # poll_max_wait's own documentation for the real run that found this.
    blast_failed_acc <- attr(hits, "failed_query_ids")
    if (!is.null(blast_failed_acc) && length(blast_failed_acc) > 0L) {
      warning(sprintf(
        "evaluate_reference_accessions(): %d accession(s)' BLAST search did not complete this call (NCBI queue timeout%s) -- will retry next call, not cached:\n  %s",
        length(blast_failed_acc),
        if (circuit_breaker_tripped) ", or sustained rate-limiting" else "",
        paste(blast_failed_acc, collapse = ", ")
      ), call. = FALSE)
      query_meta <- query_meta[!query_meta$accession %in% blast_failed_acc, , drop = FALSE]
      missing_acc <- union(missing_acc, blast_failed_acc)
    }

    if (is.data.frame(hits) && nrow(hits) > 0L) {
      # Self-hits (the accession finding its own deposited record in the
      # database) are not evidence of anything -- excluded via a version-
      # suffix-stripped comparison, same convention as remove_flagged_
      # references()/blast_sequences()'s own resolve_location join.
      strip_v <- function(x) sub("\\.[0-9]+$", "", x)
      hits <- hits[strip_v(hits$observation_id) != strip_v(hits$accession), , drop = FALSE]
    }

    if (is.data.frame(hits) && nrow(hits) > 0L) {
      # ---- create_date for every hit accession, needed by the
      # independence filter -----------------------------------------------------
      hit_acc <- unique(hits$accession)
      hit_meta <- .fetch_reference_accession_records(
        hit_acc, want_sequence = FALSE, ncbi_api_key = ncbi_api_key, verbose = verbose
      )

      # ---- Adapt BLAST hit shape into the id_x/id_y/{rank}.x/{rank}.y pair
      # table .compute_hierarchy_congruence() expects -----------------------------
      # dplyr::left_join(), not base merge() with differing by.x/by.y names --
      # `hits` and `qm_join` both have a real column literally named
      # `accession` (the BLAST hit's own subject accession vs. qm_join's join
      # key, the query accession) and base merge()'s handling of that exact
      # collision is not something to rely on without checking; left_join()'s
      # `by = c(x = y)` form is unambiguous (only the join key is consumed
      # from the right side, `hits$accession` is untouched).
      qm_join <- query_meta[, c("accession", paste0(rank_system, ".x")), drop = FALSE]
      sm <- dplyr::left_join(hits, qm_join, by = c("observation_id" = "accession"))
      sm$id_x <- sm$observation_id
      sm$id_y <- sm$accession
      sm$p_match <- sm$score / 100
      sm$coverage <- if ("query_coverage" %in% names(sm)) sm$query_coverage / 100 else NA_real_
      # blast_sequences(resolve_taxonomy = TRUE) already attaches every rank
      # in TaxaTools::standard_ranks (when resolvable) directly under its
      # own bare name (e.g. "family", not "family.y") -- rename into the
      # .y-suffixed form .compute_hierarchy_congruence() expects.
      for (r in rank_system) {
        sm[[paste0(r, ".y")]] <- if (r %in% names(sm)) sm[[r]] else NA_character_
      }

      ref_lookup <- unique(rbind(
        data.frame(composite_id = query_meta$accession, create_date = query_meta$create_date,
                  stringsAsFactors = FALSE),
        data.frame(composite_id = hit_meta$accession, create_date = hit_meta$create_date,
                  stringsAsFactors = FALSE)
      ))
      ref_lookup <- ref_lookup[!duplicated(ref_lookup$composite_id), , drop = FALSE]

      congruence <- .compute_hierarchy_congruence(
        sm, ref_lookup, rank_system = rank_system, top_n = top_n,
        min_congruent_rank = min_congruent_rank, submission_window = submission_window,
        min_coverage = NULL, require_species_resolved_partner = TRUE
      )
      # Lifted off the attribute BEFORE the merge()/subset()ing below, which
      # would silently drop it (base R attributes don't survive those).
      pair_table <- attr(congruence, "pair_table")
    } else {
      # No hits survived (either none returned at all, or all were self-hits)
      # -- an empty frame in the FULL shape .compute_hierarchy_congruence()
      # would have produced, not just id_x alone. A bare id_x-only frame here
      # would silently drop every one of these accessions from computed_rows
      # a few lines down (the merge()'s right side would have no
      # n_independent_top_matches/etc. columns to bring in at all).
      congruence <- data.frame(
        id_x = character(0L), finest_common_rank = character(0L),
        n_independent_top_matches = integer(0L), n_top_matches_available = integer(0L),
        n_excluded_same_batch = integer(0L), n_excluded_not_species_resolved = integer(0L),
        frac_independent_below_min_congruent_rank = numeric(0L),
        best_hit_pident = numeric(0L), best_agreeing_pident = numeric(0L),
        best_disagreeing_pident = numeric(0L), best_disagreeing_taxon = character(0L),
        congruent_evidence_exists_anywhere = logical(0L),
        congruent_evidence_best_pident = numeric(0L),
        stringsAsFactors = FALSE
      )
    }

    # Every fetched accession gets a row, even one with literally zero
    # BLAST hits (a genuine "insufficient_independent_evidence" case) --
    # .compute_hierarchy_congruence()'s own all_ids only covers accessions
    # that appear at least once in seq_matrix, so a zero-hit accession is
    # filled in here rather than silently dropped.
    congruence <- merge(
      data.frame(id_x = query_meta$accession, stringsAsFactors = FALSE),
      congruence, by = "id_x", all.x = TRUE, sort = FALSE
    )
    congruence$n_independent_top_matches[is.na(congruence$n_independent_top_matches)] <- 0L
    congruence$n_top_matches_available[is.na(congruence$n_top_matches_available)] <- 0L
    congruence$frac_independent_below_min_congruent_rank[
      is.na(congruence$frac_independent_below_min_congruent_rank)
    ] <- 0.5
    congruence$congruent_evidence_exists_anywhere[
      is.na(congruence$congruent_evidence_exists_anywhere)
    ] <- FALSE

    congruence$hierarchy_flag <- ifelse(
      congruence$n_independent_top_matches < min_independent_partners,
      "insufficient_independent_evidence",
      ifelse(
        congruence$frac_independent_below_min_congruent_rank >= hierarchy_incongruent_threshold,
        "incongruent", "congruent"
      )
    )

    # nrow(congruence) == 0 is a real, reachable case -- not hypothetical --
    # whenever EVERY accession still in query_meta at this point fails BLAST
    # in the same call (e.g. a sustained NCBI server-side CPU-budget
    # rejection wave affecting an entire batch): query_meta itself was
    # already filtered to 0 rows above (via blast_failed_acc), so the
    # merge() just above also produces 0 rows. Building computed_rows in
    # that case previously crashed the ENTIRE call (losing every accession
    # successfully evaluated earlier in the SAME call, since the persistent
    # cache only writes once, at the very end) -- data.frame() does not
    # recycle a length-1 scalar column (evaluated_at/cache_hit/params_key)
    # down to 0 rows the way it recycles into a longer common length; it
    # errors instead ("arguments imply differing number of rows"). Found
    # live, 2026-08-10, on a real GreatLakes run where NCBI rejected every
    # single one of 414 remaining accessions.
    if (nrow(congruence) > 0L) {
      computed_rows <- data.frame(
        accession = congruence$id_x,
        listed_taxon = query_meta$organism[match(congruence$id_x, query_meta$accession)],
        n_independent_top_matches = congruence$n_independent_top_matches,
        n_top_matches_available = congruence$n_top_matches_available,
        frac_independent_below_min_congruent_rank =
          congruence$frac_independent_below_min_congruent_rank,
        finest_common_rank = congruence$finest_common_rank,
        best_hit_pident = congruence$best_hit_pident,
        best_agreeing_pident = congruence$best_agreeing_pident,
        best_disagreeing_pident = congruence$best_disagreeing_pident,
        best_disagreeing_taxon = congruence$best_disagreeing_taxon,
        congruent_evidence_exists_anywhere = congruence$congruent_evidence_exists_anywhere,
        congruent_evidence_best_pident = congruence$congruent_evidence_best_pident,
        hierarchy_flag = congruence$hierarchy_flag,
        evaluated_at = now,
        cache_hit = FALSE,
        params_key = params_key,
        taxonomy_resolution_source =
          query_meta$taxonomy_resolution_source[match(congruence$id_x, query_meta$accession)],
        # Audit trail (2026-09-04): what was actually submitted, and which
        # rescue produced it. Both are additive diagnostics -- see
        # .ADDITIVE_CACHE_COLUMNS.
        query_len_submitted =
          as.integer(nchar(query_meta$sequence[match(congruence$id_x, query_meta$accession)])),
        query_trim_path =
          query_meta$trim_path[match(congruence$id_x, query_meta$accession)],
        n_excluded_same_batch = as.integer(congruence$n_excluded_same_batch),
        n_excluded_not_species_resolved =
          as.integer(congruence$n_excluded_not_species_resolved),
        local_corroborator_accession = NA_character_,  # this row went through BLAST, not the local-corroboration skip
        stringsAsFactors = FALSE
      )
    }
  }

  # Fold mechanism 2's oversized rows in regardless of whether the BLAST
  # block above ran at all (query_meta can be legitimately empty here purely
  # because every remaining accession this chunk was oversized).
  if (!is.null(oversized_rows)) {
    computed_rows <- if (is.null(computed_rows)) {
      oversized_rows
    } else {
      rbind(computed_rows, oversized_rows[, names(computed_rows), drop = FALSE])
    }
  }

  list(computed_rows = computed_rows, missing_acc = missing_acc,
       pair_table = pair_table,
       circuit_breaker_tripped = circuit_breaker_tripped)
}

#' Evaluate Reference-Accession Quality via Unrestricted BLAST Comparison
#'
#' For each accession, BLASTs its own sequence against a broad,
#' \strong{unrestricted} database (not scope-limited to any caller-chosen
#' taxon list), applies the same-submission-batch independence filter, and
#' computes a Jeffreys-smoothed taxonomic-hierarchy congruence verdict --
#' the same congruence math
#' `TaxaLikely::audit_reference_database()`/`classify_reference_accessions()`
#' used to compute from a narrow, taxon-list-scoped DECIPHER alignment, now
#' fed from real, broad BLAST hits instead.
#'
#' @section Why this exists (and why the old approach was abandoned):
#' The superseded approach's "among"/foreign comparison population for ANY
#' accession was exactly and only whatever else got fetched under the
#' caller's own `taxa` argument -- no broader NCBI comparison existed
#' anywhere in that pipeline. This produces both false positives (real,
#' correctly-labeled accessions read "incongruent" purely because nothing
#' else from their own family happened to be in the caller's list) and false
#' negatives (a mislabeled accession's true contaminating identity can only
#' ever be caught if its genus happens to be on the caller's list too).
#' BLASTing each accession against an unrestricted database removes the
#' `taxa`-list dependency for both directions at once. See
#' `ecosystem_docs/REENTRY_PROMPT_blast_based_reference_quality.md` for the
#' full real-data evidence (a real 6-genus GreatLakes 12S test flagged 15
#' genuine, Smithsonian-vouchered `Menidia` accessions "incongruent" purely
#' because `Menidia`'s family had no other representative on the list).
#'
#' @section Scoping a large marker's screen (2026-09-05):
#' Per-accession remote BLAST does not scale to a large reference set under
#' this ecosystem's own NCBI throttle -- confirmed directly: a 995-accession
#' PtConception 12S run has already tripped it, and the 18S reference set
#' (21,899 accessions) is over 20x that size. Screening every accession in a
#' large marker's reference set is NOT the recommended default; it is a
#' deliberate, budgeted choice for when you specifically want that coverage
#' and can absorb the cost (`chunk_size`/`max_consecutive_batch_failures`
#' exist to make a full run survivable, not to make it free).
#'
#' The recommended default for a large marker scopes the screen to the two
#' populations that actually drive real decisions, both already-built tools,
#' not something this section is asking you to build:
#' \itemize{
#'   \item \strong{Accessions that actually drive a match.}
#'     [match_driving_accessions()] returns only the accessions that are the
#'     max-scoring accession of their species for at least one real
#'     observation -- everything else can never change an assignment
#'     regardless of what this function would say about it. Real effect:
#'     709 of 995 on a real PtConception 12S match object.
#'   \item \strong{Accessions the training screen already flagged.}
#'     [verify_flagged_references()] verifies only
#'     `TaxaLikely::flag_reference_errors()`'s own `"likely_mislabeled"`
#'     subset (that screen already runs for free, no NCBI call, reusing the
#'     `seq_matrix` already built for training) -- turning "BLAST the whole
#'     training reference set" into "BLAST only the ~9-11% it actually
#'     disputed." See that function's own `@section Why the flagged subset,
#'     not the whole reference set`.
#' }
#' Together these concentrate this screen's real NCBI cost exactly where a
#' verdict can change something -- a match-driving accession feeds a real
#' assignment; a training-flagged accession feeds `train_likelihood_model()`'s
#' own silent removal -- while leaving every other accession in a large
#' reference set unscreened by default, not as an oversight but as the
#' documented, correct scope.
#'
#' @section Why "incongruent" gained a TTL (2026-09-02):
#' It was cached indefinitely on the reasoning that an accession's own
#' sequence and label do not change once deposited. That is true and still
#' irrelevant: the verdict is not a property of the accession, it is a
#' property of what BLAST returned about the accession's NEIGHBOURHOOD, and
#' that changes. Measured, not hypothesised: `OP056918`
#' (`Cryptacanthodes maculatus`) read `"incongruent"` with no corroborating
#' evidence anywhere on 2026-09-01, and `"congruent"` with four conspecific
#' hits at 100% identity on 2026-09-02, under an IDENTICAL `params_key`.
#' Under the old policy that first, wrong verdict would have been served from
#' cache forever -- and it is the one verdict
#' [remove_incongruent_references()] acts on destructively.
#'
#' What the flip was, established by
#' `diagnostics/blast_verdict_repeatability_probe.R` the same day: NOT
#' instability. Three back-to-back replicates of all 12 PtConception
#' `"incongruent"` accessions, each into a fresh cache, returned identical
#' verdicts, identical diagnostics, and identical hit sets (Jaccard 1.000,
#' 14-20 partners each) -- BLAST is exactly reproducible at a fixed
#' `params_key`. The corroborating records' GenBank create- AND update-dates
#' are both months earlier, so they were not newly released either. The
#' surviving explanation is that NCBI's `nt` is a periodically-rebuilt
#' SNAPSHOT rather than the live nuccore database: a record public in Entrez
#' since January need not be in the `nt` volume BLAST searches until a rebuild
#' includes it.
#'
#' That reframes this TTL. The 09-02 verdict was not a correction of a
#' malfunction -- both verdicts were correct given the database each was
#' computed against. What goes stale is the SNAPSHOT, which is exactly what a
#' TTL is for -- and it is also what sets the right cadence for one. `nt`
#' rebuilds run on the order of days to weeks, so the default is 30 days, not
#' the 180 of the "we do not know yet" flags: a TTL much longer than the
#' rebuild interval would keep serving a stale `"incongruent"` long after the
#' evidence that overturns it became searchable, which is the exact failure
#' this TTL exists to prevent. The recheck costs ~1% of an accession
#' population. See
#' `ecosystem_docs/REENTRY_PROMPT_reference_quality_verdicts_and_downstream_use.md`.
#'
#' @section Coarse-rank diagnostic (2026-08-07):
#' `finest_common_rank` walks the FULL `kingdom`->`species` ladder
#' (`TaxaTools::standard_ranks`), not just `min_congruent_rank` and finer.
#' `hierarchy_flag`'s classification threshold is unaffected -- it still
#' fires at `min_congruent_rank` (default `"family"`) exactly as before --
#' but `finest_common_rank` can now report a real coarser match (e.g.
#' `"order"`) instead of collapsing straight to `NA` the moment `"family"`
#' fails. This distinction is real, not cosmetic: found live-testing against
#' a real PtConception 18S accession (`Abylopsis eschscholtzii`,
#' `KY594854`/`KX384617`) whose top independent BLAST hits are consistently
#' `Diphyidae` -- a SISTER family within the same order (Siphonophorae,
#' Calycophorae), not an unrelated organism. Both accessions flagged
#' `"incongruent"` under the family-only version with no way to tell that
#' apart from a genuine cross-phylum mismatch; `finest_common_rank = "order"`
#' now reports that real, more specific picture. The likely underlying
#' cause here is 18S's well-documented poor resolving power within
#' Calycophorae combined with thin `Abylidae` GenBank coverage at this
#' locus -- NOT necessarily a mislabel -- and this diagnostic is what makes
#' that distinguishable at all from the output alone, without re-BLASTing
#' by hand. Query-side taxonomy for every rank is resolved via the internal
#' `.resolve_taxonomy_by_acc()` (the same NCBI-taxonomy-DB mechanism already
#' used to classify BLAST hits), not `TaxaTools::fill_higher_ranks()`
#' (GNVerifier-backed, and only ever resolved genus/family) -- keeps both
#' sides of every comparison authority-consistent.
#'
#' @section Caching:
#' Deduplication (`unique(accessions)`) happens regardless of caching -- an
#' accession is never re-evaluated twice within one call. A persistent,
#' cross-run cache underneath (keyed by accession alone, not by
#' taxon/genus/project) is what lets a project only pay evaluation cost for
#' accessions that are genuinely new or previously out of scope anywhere --
#' no `taxa` list to decide up front. Staleness is handled asymmetrically,
#' per flag, and the asymmetry follows what each verdict actually CLAIMS:
#' \itemize{
#'   \item{`"congruent"` -- cached indefinitely. It asserts corroborating
#'     evidence WAS FOUND, and nothing a later BLAST returns can withdraw a
#'     match already observed; new deposits can only add more.}
#'   \item{`"incongruent"` -- expires after `incongruent_ttl_days`
#'     (default 30; **new 2026-09-02**, previously cached indefinitely). It
#'     asserts corroborating evidence was NOT found, which is a statement
#'     about ABSENCE, and absence is exactly what later evidence overturns.
#'     See `@section Why "incongruent" gained a TTL` below.}
#'   \item{`"insufficient_independent_evidence"` (original),
#'     `"not_evaluated_oversized"` (2026-09-01) and
#'     `"not_evaluated_wrong_marker"` (2026-09-04) -- expire after
#'     `insufficient_evidence_ttl_days` (default 180). All three explicitly
#'     mean "we do not know yet": new NCBI deposits (for the first), a later
#'     annotation/primer fix or a raised `max_query_len` (for the second), or
#'     a corrected upstream annotation -- or simply a different
#'     `barcode_term`, since the wrong-marker claim is relative to the marker
#'     THIS call asked for (for the third).}
#'   \item{`"locally_corroborated"` (2026-09-03) -- cached indefinitely,
#'     like `"congruent"`: it asserts corroborating evidence WAS found, in
#'     the caller's own reference set. The one way it is re-evaluated is a
#'     later call with `skip_locally_corroborated = FALSE`, which sends it
#'     to BLAST after all.}
#' }
#' `retry_insufficient = FALSE` opts a single call out of retrying ANY
#' expired row past its TTL, serving the stale row instead (see that param's
#' own documentation; the name predates `"incongruent"` gaining a TTL).
#' Setting `incongruent_ttl_days = Inf` restores the pre-2026-09-02 policy
#' exactly. TTLs are deliberately NOT part of `params_key` -- changing one
#' must not invalidate a cache. A cached row is also treated as stale (recomputed) if any
#' parameter that affects the verdict itself (`top_n`, `min_congruent_rank`,
#' `submission_window`, `hierarchy_incongruent_threshold`,
#' `min_independent_partners`, `score_range`, `min_score`, `max_hits`,
#' `method`, `database`, `query_span`) differs from the call that produced
#' it -- `chunk_size`, `max_consecutive_batch_failures`, `max_query_len`,
#' `max_batch_bp`, `prioritize_uncached`, `retry_insufficient`,
#' `local_corroboration` and `skip_locally_corroborated` are deliberately
#' NOT in this list (see `@section Long-sequence robustness` below for
#' why). The 2026-09-03 `query_span` change bumped the internal cache
#' version to `"v5_amplicon_query"`, which invalidates every row cached
#' before it; run [migrate_reference_cache()] on an existing cache directory
#' first so its `"congruent"` rows are carried forward instead of re-BLASTed.
#'
#' @param accessions Character vector of NCBI accessions to evaluate.
#'   Deduplicated internally.
#' @param cache_dir Character or `NULL`. Default
#'   `tools::R_user_dir("TaxaMatch", "cache")`. Set `NULL` to disable
#'   caching entirely (every call re-evaluates every accession).
#' @param insufficient_evidence_ttl_days Numeric (default `180`). See
#'   Caching above.
#' @param incongruent_ttl_days Numeric (default `30`). Days after which an
#'   `"incongruent"` cached verdict is re-evaluated. `Inf` restores the
#'   pre-2026-09-02 behaviour (cached indefinitely). Much shorter than
#'   `insufficient_evidence_ttl_days` on purpose, for two compounding reasons:
#'   `"incongruent"` is the only verdict that causes a reference to be
#'   REMOVED, and the thing that goes stale underneath it -- NCBI's `nt`
#'   snapshot -- is rebuilt on the order of days to weeks, not months. It is
#'   also ~1% of a real accession population (12 of 995 on the PtConception
#'   screen), so this is simultaneously the most valuable and the cheapest
#'   recheck available. See `@section Why "incongruent" gained a TTL`.
#' @param top_n Integer (default `5L`). Max independent BLAST hits ranked
#'   per accession for the congruence verdict.
#' @param min_congruent_rank Character (default `"family"`). Passed to the
#'   shared congruence math -- see
#'   `TaxaLikely::audit_reference_database()`'s own roxygen for why
#'   `"family"`, not a coarser rank, is this ecosystem's default.
#' @param hierarchy_incongruent_threshold Numeric (default `0.5`). An
#'   accession's smoothed `frac_independent_below_min_congruent_rank` at or
#'   above this value reads `"incongruent"`.
#' @param min_independent_partners Integer (default `3L`). Fewer independent
#'   top matches than this reads `"insufficient_independent_evidence"`
#'   regardless of the fraction -- mirrors
#'   `TaxaLikely::repair_thin_evidence()`'s identical floor.
#' @param submission_window Integer (default `5L`). Days (or accession-number
#'   proximity) within which two accessions are treated as the same
#'   submission batch, and therefore non-independent evidence of each other.
#' @param method,database,score_range,min_score,max_hits Passed through to
#'   `blast_sequences()` -- see that function's own documentation.
#' @param ncbi_api_key Character or `NULL`. Optional NCBI API key for higher
#'   rate limits (also forwarded to `blast_sequences()`).
#' @param poll_max_wait Numeric (default `1800`, i.e. 30 minutes). Forwarded
#'   to `blast_sequences(poll_max_wait =)` -- how long to keep polling NCBI
#'   for one BLAST batch's results before giving up on it. An accession
#'   whose batch times out (even after `blast_sequences()`'s own automatic
#'   halved-batch-size retry) is treated the same as one NCBI has no record
#'   for at all -- excluded from this call's cache write and reported via
#'   `$unresolved`-style warning, NOT scored as
#'   `"insufficient_independent_evidence"` -- a real, previously-possible
#'   silent-miscache risk found 2026-08-09 on a real, large (1,183-
#'   accession), multi-hour remote-BLAST run: sustained NCBI queue
#'   congestion caused most batches after the first to time out at the old
#'   hardcoded 600s ceiling, and every one of those accessions would
#'   otherwise have been cached as a false `"insufficient_independent_
#'   evidence"` verdict for up to `insufficient_evidence_ttl_days` (180 days
#'   by default) -- masking the real infrastructure failure as if it were a
#'   genuine evidentiary finding.
#' @param barcode_term Character or `NULL` (default). When supplied, any
#'   query sequence exceeding the marker's expected length (via
#'   `TaxaTools::resolve_barcode_lengths(barcode_term)`) is trimmed to its
#'   amplicon region (via `TaxaTools::resolve_barcode_primers(barcode_term)`
#'   + the same primer-matching algorithm as `TaxaLikely::trim_to_amplicon()`,
#'   duplicated here -- see `.extract_amplicon_one_tm()`'s own documentation)
#'   before being BLASTed, instead of submitting the full sequence.
#'   BLASTing a full-length over-length reference (e.g. a complete
#'   mitogenome, ~16.5kb) against a broad database is dramatically more
#'   CPU-expensive than BLASTing its short barcode region, and was found
#'   2026-08-09 to be the real cause of a live NCBI server-side CPU-budget
#'   rejection on a real, large run whose queries were often full
#'   mitogenomes (see `poll_max_wait`'s own documentation for the real
#'   captured case) -- the accession's own species-identity signal lives in
#'   the short barcode region regardless, so trimming answers the identical
#'   question at a fraction of the cost. A sequence whose primer sites
#'   can't be found is next tried against the record's own annotated
#'   feature table (2026-09-01 -- see `@section Long-sequence robustness`
#'   below), then, if still over-length, subject to the `max_query_len`
#'   hard cap -- never silently dropped or errored either way; at worst it
#'   is deferred as `"not_evaluated_oversized"`, an explicit, labeled,
#'   TTL-retryable non-result. `NULL` (default) submits every sequence at
#'   full length, unchanged from prior behavior.
#' @param query_span Character, `"amplicon"` (default) or
#'   `"primer_inclusive"`. Which span of a `barcode_term`-trimmed query is
#'   submitted to BLAST: the primer-STRIPPED amplicon (the region between the
#'   two primer sites, ~169 bp for MiFish-U) or the primer-INCLUSIVE span
#'   (~217 bp), the only behaviour before 2026-09-03. See `@section Why the
#'   query is the primer-stripped amplicon`. Verdict-affecting, so it is part
#'   of `params_key`. Ignored when `barcode_term` is `NULL` (nothing is
#'   trimmed).
#' @param chunk_size Integer (default `200L`). Accessions needing real
#'   evaluation are processed this many at a time, with the persistent
#'   cache written after EACH chunk -- see `@section Chunked evaluation and
#'   NCBI rate-limiting resilience` below. `Inf` restores the pre-2026-08-14
#'   single-shot behavior (one chunk covering every accession, cache written
#'   only once at the very end).
#' @param max_consecutive_batch_failures Numeric (default `3L`). Forwarded
#'   to `blast_sequences()` -- see that function's own documentation for the
#'   full circuit-breaker mechanism (a `.blast_server_rejected()` rejection
#'   counts double toward this threshold; a plain poll timeout counts once).
#'   `Inf` disables it.
#' @param max_query_len Numeric or `NULL` (default). The hard submission
#'   cap -- after BOTH `barcode_term` rescue strategies (primer trimming,
#'   then the feature-table-guided extraction fallback) have been tried, any
#'   query still longer than this is NOT submitted to BLAST at all. `NULL`
#'   resolves a default: `10x` the marker's own `amplicon_range` upper bound
#'   (via `TaxaTools::resolve_barcode_primers(barcode_term)`) when
#'   `barcode_term` is supplied -- generous enough to never reject a real
#'   amplicon-length sequence, but small enough to exclude a full
#'   mitogenome or larger record -- or a flat `5000` when it is not (no
#'   marker-specific bound to derive one from). `Inf` disables the cap
#'   entirely, restoring the pre-2026-09-01 behavior (an unrescuable
#'   over-length query is always BLASTed at full length). See `@section
#'   Long-sequence robustness` below for the full mechanism and the new
#'   `"not_evaluated_oversized"` verdict this produces.
#' @param max_batch_bp Numeric (default `100000L`). Forwarded to
#'   `blast_sequences()` -- see that function's own documentation for the
#'   length-aware BLAST batching this adds alongside the existing
#'   count-based batching. `Inf` disables it.
#' @param prioritize_uncached Logical (default `TRUE`). Orders `needs_eval`
#'   so accessions with NO existing cached verdict under the current call's
#'   parameters are evaluated before expired
#'   `"insufficient_independent_evidence"`/`"not_evaluated_oversized"` rows
#'   being retried past their TTL -- a budget-limited call (one that trips
#'   `blast_sequences()`'s own circuit breaker partway through) buys real
#'   NEW coverage first, rather than re-spending BLAST budget re-checking
#'   accessions that already have SOME cached answer. A pure ordering
#'   change within one call -- never changes which accessions end up
#'   evaluated, only in what order -- so, unlike every other new parameter
#'   here, this one changes existing default behavior deliberately: it is
#'   strictly better (or a no-op), never worse.
#' @param retry_insufficient Logical (default `TRUE`). `FALSE` skips
#'   retrying EXPIRED `"insufficient_independent_evidence"`/
#'   `"not_evaluated_oversized"` cached rows entirely for this call -- they
#'   are served from cache as-is (their TTL notwithstanding) instead of
#'   being re-submitted to NCBI. Addresses a real documented complaint: by
#'   default, a call the caller expects to be purely cache-served (every
#'   accession already evaluated at least once) can still spend real BLAST
#'   budget re-checking every TTL-expired row, grinding against the same
#'   CPU-budget throttle this whole feature exists to survive. Set `FALSE`
#'   on a call where zero new NCBI cost is required this time.
#' @param local_corroboration Data frame or `NULL` (default). Output of
#'   [corroborate_references_locally()] for the caller's own reference set.
#'   When supplied (and `skip_locally_corroborated = TRUE`), any accession
#'   whose `local_tier` is `"corroborated"` and that has no fresh cached
#'   verdict is NOT BLASTed: it is written to the cache as
#'   `hierarchy_flag = "locally_corroborated"` with
#'   `n_independent_top_matches = n_independent_conspecific`,
#'   `best_agreeing_pident = 100 * best_independent_pident`,
#'   `congruent_evidence_exists_anywhere = TRUE`,
#'   `finest_common_rank = "species"`, and every other diagnostic `NA`. See
#'   `@section Local corroboration`.
#' @param skip_locally_corroborated Logical (default `TRUE`). `FALSE` sends
#'   locally-corroborated accessions to BLAST like any other, and also
#'   re-evaluates any row previously cached as `"locally_corroborated"`
#'   (that flag records a decision not to evaluate, not an evaluation).
#'   Not part of `params_key`.
#' @param verbose Logical (default `TRUE`). Print progress messages.
#'
#' @return A data frame, one row per unique input accession:
#'   \describe{
#'     \item{`accession`}{Exactly as supplied by the caller.}
#'     \item{`listed_taxon`}{The accession's own labeled organism (from its
#'       real GenBank record).}
#'     \item{`n_independent_top_matches`}{Independent BLAST hits actually
#'       used for the verdict (`<= top_n`). Also excludes any hit whose OWN
#'       listed species isn't itself resolved to species level -- see
#'       `@section Species-resolved comparison partners` below.}
#'     \item{`n_top_matches_available`}{All BLAST hits before the
#'       independence filter -- diagnostic only.}
#'     \item{`frac_independent_below_min_congruent_rank`}{Jeffreys-smoothed
#'       fraction of independent hits disagreeing at or above
#'       `min_congruent_rank`.}
#'     \item{`finest_common_rank`}{Finest rank at which the single best
#'       independent hit agrees with the listed taxon (`NA` if none), walking
#'       the full `kingdom`->`species` ladder -- see `@section Coarse-rank
#'       diagnostic` above.}
#'     \item{`best_hit_pident`}{Percent identity (0-100) of the single best
#'       independent hit, regardless of whether it agrees or disagrees.}
#'     \item{`best_agreeing_pident`}{Percent identity of the highest-identity
#'       independent hit that agrees at or above `min_congruent_rank`, among
#'       the `top_n` slice used for the verdict itself. `NA` if none agree.}
#'     \item{`best_disagreeing_pident`}{Percent identity of the highest-
#'       identity independent hit that disagrees (coarser than
#'       `min_congruent_rank`), among the `top_n` slice. `NA` if none
#'       disagree. See `@section Identity diagnostics` below for why this
#'       matters -- a high value here is a much stronger mislabel signal
#'       than a low one, information the binary `hierarchy_flag` alone
#'       cannot convey.}
#'     \item{`best_disagreeing_taxon`}{The listed species of that same
#'       highest-identity disagreeing hit (`NA` if none disagree). Lets a
#'       reviewer -- human or LLM -- recognize e.g. a known hybrid-cross
#'       partner or an informal specimen code by name, not just by percent
#'       identity alone.}
#'     \item{`congruent_evidence_exists_anywhere`}{Logical. Unlike
#'       `hierarchy_flag` (computed only from the `top_n` closest
#'       independent hits), this asks whether ANY independent hit anywhere
#'       in the full BLAST result (up to `max_hits`) agrees at or above
#'       `min_congruent_rank`. `FALSE` here is a stronger statement than an
#'       `"incongruent"` `hierarchy_flag` alone -- it means the listed rank
#'       has no representation at all among this accession's independent
#'       matches, not just none close enough to make the `top_n` cut.}
#'     \item{`congruent_evidence_best_pident`}{Percent identity of the best
#'       such anywhere-agreeing hit. `NA` when
#'       `congruent_evidence_exists_anywhere` is `FALSE`.}
#'     \item{`hierarchy_flag`}{`"congruent"`, `"incongruent"`,
#'       `"insufficient_independent_evidence"`,
#'       `"not_evaluated_oversized"` (added 2026-09-01 -- see `@section
#'       Long-sequence robustness` below; the query was never submitted to
#'       BLAST at all, so this is NOT evidence of anything, and downstream
#'       consumers ([flag_incongruent_references()],
#'       [remove_incongruent_references()]) never treat it as a flag),
#'       `"not_evaluated_wrong_marker"` (added 2026-09-04 -- also never
#'       submitted, and also never a flag, but it names a CAUSE rather than a
#'       symptom: the record's own GBSeq feature table carries annotated
#'       features and none of them is the marker `barcode_term` implies, so
#'       the accession does not belong in this screen's candidate set and no
#'       `max_query_len` can rescue it), or
#'       `"locally_corroborated"` (added 2026-09-03 -- skipped because an
#'       independent conspecific in the caller's own reference set already
#'       corroborates it; see `@section Local corroboration`. Treated like
#'       `"congruent"` everywhere downstream: never a flag, never removable,
#'       `reference_action = "keep"`).
#'       `NA` if the accession's own GenBank record could not be fetched (a
#'       `warning()` is issued listing these; not cached, so a subsequent
#'       call retries them).}
#'     \item{`local_corroborator_accession`}{The specific accession vouching
#'       for a `"locally_corroborated"` row (added 2026-09-05, critical-fix-
#'       review finding B5) -- `NA` for every other `hierarchy_flag` value.
#'       `"locally_corroborated"` is cached indefinitely and exempt from
#'       [refine_reference_verdicts()]'s trust-weighted refinement (the
#'       MATCH itself, once observed, is permanent) -- but the corroborator's
#'       own label is exactly as falsifiable as any other accession's, so
#'       this column exists to make that dependency visible and checkable,
#'       the same transparency [verify_removal_candidates()] already gives
#'       its own corroborators.}
#'     \item{`evaluated_at`}{When this verdict was computed (`NA` for a
#'       fetch failure).}
#'     \item{`cache_hit`}{`TRUE` if this row was read from `cache_dir`
#'       rather than recomputed this call.}
#'     \item{`taxonomy_resolution_source`}{`"direct"` (the accession's own
#'       NCBI taxonomy, the normal case), `"hybrid_maternal_proxy"` (a
#'       hybrid-labeled accession whose coarser-rank lineage was resolved
#'       from its maternal parent species instead -- see `@section
#'       Hybrid-labeled accessions` below), `"hybrid_unresolved"` (detected
#'       as hybrid-labeled but no usable parent species name could be
#'       extracted from the label, so the accession's own -- structurally
#'       incomplete -- NCBI lineage is used as-is), or `NA` for a fetch
#'       failure.}
#'     \item{`listed_taxon_is_species`}{Logical. `FALSE` when `listed_taxon`
#'       does not structurally look like a species-level binomial (via
#'       [TaxaTools::is_plausible_binomial()] -- e.g. a family name used in
#'       place of a genus with an informal specimen code, such as
#'       `"Serranidae sp. JL-2015"`, a real GreatLakes case). A
#'       structurally different problem from both mislabeling
#'       (`hierarchy_flag`) and hybrid-labeling
#'       (`taxonomy_resolution_source`): such a reference can't
#'       discriminate at species level regardless of whether it's
#'       internally self-consistent, so this can be `FALSE` even when
#'       `hierarchy_flag` reads `"congruent"`. `NA` for a fetch failure
#'       (never `FALSE` -- a fetch failure means "not evaluated," not
#'       "evaluated and found non-species").}
#'   }
#'
#'   Also carries `attr(result, "run_summary")` -- a list (`n_total`,
#'   `n_from_cache`, `n_evaluated_this_call`,
#'   `n_skipped_locally_corroborated`, `n_pending`, `pct_complete`,
#'   `circuit_breaker_tripped`, `recommended_pause_minutes`) summarizing
#'   what happened this call -- see `@section Chunked evaluation and NCBI
#'   rate-limiting resilience` below.
#'
#' @section Chunked evaluation and NCBI rate-limiting resilience (2026-08-14):
#' A large accession list is evaluated `chunk_size` accessions at a time,
#' with the persistent cache written after EACH chunk rather than once at
#' the very end. Combined with `blast_sequences()`'s own circuit breaker
#' (`max_consecutive_batch_failures` -- stops submitting further BLAST
#' batches once several in a row have failed, rather than continuing to pay
#' up to `poll_max_wait` for each of dozens of doomed batches), this means a
#' sustained NCBI rate-limiting or CPU-budget-throttling episode is detected
#' and this function stops itself early, rather than grinding through the
#' full accession list at up to 30 minutes per doomed batch. When this
#' happens: every accession successfully evaluated in an EARLIER chunk this
#' call is already safely cached (nothing already computed is lost);
#' `attr(result, "run_summary")$circuit_breaker_tripped` is `TRUE`; and an
#' actionable `message()` reports how many accessions were resolved this
#' call (as a percentage), how many are still pending, and recommends a
#' pause before calling `evaluate_reference_accessions()` again with the
#' *same* accessions and `cache_dir` -- already-cached accessions are read
#' straight from the cache (no re-BLAST), so a resumed call only pays for
#' what's still genuinely outstanding. Before this existed, the documented
#' workaround for a large real run (e.g.
#' `AuditNCBI_Goal2_MatchCandidateScreen.R`, a real external GreatLakes
#' workflow) was to manually pre-split the accession list into chunks of
#' ~200 and call this function once per chunk -- `chunk_size` automates
#' exactly that.
#'
#' @section Hybrid-labeled accessions (2026-08-10):
#' NCBI's own taxonomy entry for a hybrid-cross-labeled organism (e.g.
#' `"Ctenopharyngodon idella x Megalobrama amblycephala"`) is genuinely
#' incomplete -- confirmed live against several real GreatLakes candidates:
#' the lineage terminates at `"unclassified Cyprinoidei"`, with no family,
#' genus, or species populated at all. Left as-is, such an accession can
#' never agree with any independent hit at family rank or finer (there is
#' nothing on the query side to compare), which this function's rank-walk
#' mechanically reads as maximal disagreement -- a real, confirmed
#' false-positive mode (10 of 13 `"incongruent"` flags on a real
#' 1,183-accession GreatLakes run were this artifact, not genuine
#' mislabels; the other 3, with complete normal lineages, were real
#' candidates worth reviewing).
#'
#' Fixed by resolving the accession's maternal parent species' OWN real
#' lineage instead, for every rank coarser than species: since mtDNA is
#' maternally inherited in fish, a hybrid's barcode sequence genuinely IS
#' its maternal parent's lineage at kingdom through genus, even though it
#' is (correctly) not literally the same SPECIES as that parent. The
#' maternal parent's name is extracted from `listed_taxon` via
#' `TaxaTools::clean_taxon_names()`'s existing 3-token simplification (it
#' already keeps only the first genus + epithet, discarding everything
#' from `" x ..."` onward -- the same simplification this ecosystem
#' already applies to hybrid-formula names elsewhere), then resolved via
#' `TaxaTools::verify_taxon_names(backbone_id = 4L)` (NCBI, the same
#' authority every other taxonomy resolution in this function uses).
#' `species.x` (the finest rank) is deliberately left as the accession's
#' own real listed hybrid label, never replaced by the proxy -- a hybrid
#' genuinely is not the same species as its maternal parent, so a spurious
#' species-level agreement would be biologically wrong in the opposite
#' direction. Detection requires BOTH `listed_taxon` containing a
#' standalone `" x "` token (the standard nomenclatural hybrid marker) AND
#' the accession's own resolved `family` being unresolvable -- so an
#' ordinary, non-hybrid taxon with a genuinely incomplete NCBI lineage
#' (e.g. a real undescribed/unclassified species) is never routed through
#' this maternal-parent substitution, which would have no biological
#' justification for a non-hybrid. A leading lowercase breeding/ploidy-
#' manipulation modifier (e.g. `"androgenetic"`, `"autodiploid"`,
#' `"autotetraploid"` -- all found on real GreatLakes records, 2026-08-11)
#' is stripped before `clean_taxon_names()` runs, since the maternal-
#' inheritance argument still holds (these manipulate the nuclear genome,
#' not which egg's cytoplasm/mitochondria the offspring develops in). A
#' label the hybrid-marker regex catches but still cannot be parsed into a
#' usable proxy even after that stripping falls back to the accession's
#' own unresolved lineage, `taxonomy_resolution_source =
#' "hybrid_unresolved"` -- an honest admission, not a guess.
#'
#' @section Species-resolved comparison partners (2026-08-13):
#' A comparison partner (an independent BLAST hit) whose OWN listed species
#' isn't resolved to species level (e.g. `"Serranidae sp. JL-2015"` -- a
#' family name used in place of a genus, with an informal specimen code) is
#' excluded from `n_independent_top_matches`/
#' `frac_independent_below_min_congruent_rank` entirely, via
#' `require_species_resolved_partner = TRUE` (default, not currently a
#' caller-facing parameter). Found live, 2026-08-11/13, on the real
#' GreatLakes *Stereolepis doederleini* case: both real accessions of this
#' genuinely isolated species (Polyprionidae has only 2 genera) read
#' `"incongruent"` purely because the one real independent hit available in
#' all of NCBI to disagree with them was itself a non-species-resolved
#' accession -- whether such a partner happens to agree or disagree isn't
#' meaningful evidence either way, since its own identity is only fuzzily
#' determined. Live-verified before shipping (a direct standalone BLAST re-
#' run against the real accession, not assumed): after this exclusion, the
#' real vote count for *S. doederleini* drops to 1 (a single genuine
#' independent conspecific), correctly producing
#' `"insufficient_independent_evidence"` instead of `"incongruent"` -- the
#' honest answer, not an inflated `"congruent"` either, since there really
#' is only one real corroborating record in NCBI for this species. Reuses
#' `TaxaTools::is_plausible_binomial()` (the same check
#' `listed_taxon_is_species` already applies to the QUERY side) applied to
#' the HIT side's own resolved species name.
#'
#' @section Identity diagnostics (2026-08-07):
#' `hierarchy_flag`/`finest_common_rank` alone cannot distinguish a genuine
#' mislabel from "the listed rank has no well-covered independent relative
#' in GenBank at this marker" -- both produce identical rank-agreement
#' output. Percent identity is the cheapest available discriminator and was
#' already being computed (`p_match`, used only to ORDER hits) and then
#' discarded. A DISAGREEING hit at ~99% identity is a real mislabel signal
#' (the deposited sequence is nearly identical to something in a different
#' family); a disagreeing hit at ~85-90% is unremarkable for a conserved
#' marker (e.g. 18S) with poor resolving power at that rank. This does NOT
#' resolve the ambiguity on its own -- it is a design-consult finding
#' (2026-08-07, grounded in a real case: `Abylopsis eschscholtzii`,
#' `KY594854`/`KX384617`, both flagged `"incongruent"` with disagreeing
#' hits at family that are consistently a SISTER family within the same
#' order) that these columns give a caller genuinely new information to
#' judge that question with, not a verdict. No classification threshold in
#' this function reads these columns; they are informational only.
#'
#' @section Long-sequence robustness (2026-09-01):
#' Implements `ecosystem_docs/REENTRY_PROMPT_
#' eval_ref_accessions_long_sequence_robustness.md`. `barcode_term`
#' trimming already shortens an over-length query when the primer sites can
#' be found; four further mechanisms address what happens when they
#' CAN'T -- a full mitogenome (or larger) record submitted to remote BLAST
#' at full length is dramatically more CPU-expensive than a short amplicon,
#' the real, confirmed cause of sustained NCBI server-side CPU-budget
#' rejections that stall this function's own progress:
#' \enumerate{
#'   \item{Feature-table-guided extraction fallback -- a query still
#'     over-length after primer trimming is checked against the record's
#'     OWN annotated GBSeq feature table for a feature matching the marker
#'     `barcode_term` implies, and that coordinate span (plus margin) is
#'     extracted instead. See `.extract_feature_table_fallback()`
#'     (`R/trim_query_to_amplicon.R`), which reuses
#'     `check_marker_mismatch()`'s own fetch/matching internals
#'     (`R/check_marker_mismatch.R`) rather than duplicating them.}
#'   \item{Hard submission cap -- `max_query_len`: a query still over-length
#'     after BOTH rescue strategies is never submitted to BLAST at all. Gets
#'     a real cached row, `hierarchy_flag = "not_evaluated_oversized"`,
#'     every diagnostic column `NA` -- an explicit, labeled non-result, not
#'     a silent drop. TTL-retryable like `"insufficient_independent_
#'     evidence"` (see `@section Caching` above), so a later annotation fix,
#'     primer update, or a raised `max_query_len` can rescue it.}
#'   \item{Wrong marker, separated from wrong size (2026-09-04): when the
#'     feature-table fallback declined because the record HAS annotated
#'     features and none is this marker, the deferred row reads
#'     `"not_evaluated_wrong_marker"` instead. The distinction is
#'     actionable, which is the whole point: `"oversized"` implies a size
#'     problem a caller could fix by raising `max_query_len`, and for this
#'     class no length ever helps -- the accession should not be in the
#'     candidate set. Real case: `HM561627` (*Lasiurus intermedius*), 2,657
#'     bp, whose feature table contains exactly one feature, 16S ribosomal
#'     RNA at 1061-2657, sitting in a 12S (MiFishU) screen. It was 1 of 1
#'     oversized accessions on the real 995-accession PtConception run --
#'     i.e. 100% of that population was this case, not a length problem.
#'     Before building more rescue machinery, check what fraction of your own
#'     oversized rows are really this.}
#'   \item{Length-aware BLAST batching -- `max_batch_bp`, forwarded to
#'     `blast_sequences()`: closes a submission batch on a cumulative bp cap
#'     as well as the existing count cap, and rides one very long query
#'     alone rather than letting it doom a whole batch of otherwise-cheap
#'     queries.}
#'   \item{Retry-priority ordering + a retry switch -- `prioritize_uncached`
#'     (default `TRUE`, changes existing default ordering, deliberately
#'     safe) and `retry_insufficient` (default `TRUE`; `FALSE` makes a call
#'     purely cache-served, spending zero new NCBI budget on expired
#'     retries this call).}
#' }
#' `max_query_len`, `max_batch_bp`, `prioritize_uncached`, and
#' `retry_insufficient` are all additive and deliberately excluded from
#' `params_key` -- like `chunk_size`/`max_consecutive_batch_failures`
#' before them, they govern call MECHANICS/scheduling policy (how/whether
#' work is submitted this call), not what verdict a given accession's
#' evidence would produce, so changing them between calls never invalidates
#' an already-`"congruent"`/`"incongruent"`-cached row. `.EVAL_REF_ACC_
#' VERSION` was unchanged by that work (it was bumped on 2026-09-03 for
#' `query_span`, see below).
#'
#' @section Why the query is the primer-stripped amplicon (2026-09-03):
#' The screen runs `blastn` (`megablast = FALSE`, +2 match / -3 mismatch).
#' With the primer-INCLUSIVE 217 bp MiFish-U query, a 169 bp perfect
#' conspecific amplicon-only deposit scores 338 raw, while every full-length
#' relative at >= 93.1% identity over the whole 217 bp scores >= 359 -- so
#' NCBI's `HITLIST_SIZE = 100` list fills with mitogenome relatives and the
#' short perfect conspecific never arrives. Behind that,
#' [blast_sequences()]'s default `min_query_coverage = 80` would have
#' dropped it anyway (169/217 = 77.9%). Found on the real PtConception
#' screen: `KM057996` (*Zaniolepis frenata*) was actioned `"remove"` ("no
#' conspecific evidence anywhere in nt") while the user's own reference set
#' held `OQ846041`, a 169 bp *Z. frenata* deposit from 2023 at 100% identity
#' over 97% overlap. A live probe (`diagnostics/blast_coverage_blindspot_
#' probe.R`) confirmed the mechanism: the 217 bp query returns no
#' conspecific but itself among 100 hits; the same query with the primers
#' stripped (169 bp) returns `OQ846041` at rank 2, score 100, coverage 100.
#' Amplicon-only deposits are 33% of PtConception's references and 25% of
#' GreatLakes', so the whole class was invisible as corroborators. With the
#' stripped query both barriers vanish and `min_query_coverage` needs no
#' change. Because this changes what is submitted, it is verdict-affecting:
#' `query_span` is in `params_key` and the cache version was bumped to
#' `"v5_amplicon_query"`; [migrate_reference_cache()] carries an existing
#' cache's `"congruent"` rows forward (stripping primers only ADDS hits, it
#' cannot withdraw a match already observed) and leaves everything else to
#' re-BLAST under the new query.
#'
#' @section Local corroboration (2026-09-03):
#' If an ASV matches several references of the same species that agree with
#' each other, why BLAST any of them? [corroborate_references_locally()]
#' answers that from the workflow's own `seq_matrix`, for free: a reference
#' whose best INDEPENDENT (different submission batch, the screen's own
#' rule) conspecific matches at >= `min_pident` over >= `min_overlap` of
#' the amplicon is `"corroborated"`. Passed here as `local_corroboration`,
#' such accessions are skipped rather than BLASTed (about 40% of the
#' PtConception population, 15% of GreatLakes), cached as
#' `"locally_corroborated"` with TTL `Inf`. [score_reference_labels()] uses
#' the same table for provenance (`corroboration_source`) and to VETO a
#' BLAST `"remove"` down to `"inspect"` when the local set corroborates the
#' label -- the disagreement between the two is what exposed the blind spot
#' above. The overlap filter is not optional: `KM057967` (*Jordania zonope*)
#' looked corroborated by `LC126244` at "100%" over a 5.6% overlap (~40 bp
#' of a different 12S region); it is a true singleton and its removal
#' stands.
#'
#' @seealso [remove_incongruent_references()], [flag_incongruent_references()],
#'   [corroborate_references_locally()], [match_driving_accessions()],
#'   [migrate_reference_cache()], [blast_sequences()]
#'
#' @export
evaluate_reference_accessions <- function(accessions,
                                          cache_dir = tools::R_user_dir("TaxaMatch", "cache"),
                                          insufficient_evidence_ttl_days = 180,
                                          incongruent_ttl_days = 30,
                                          top_n = 5L,
                                          min_congruent_rank = "family",
                                          hierarchy_incongruent_threshold = 0.5,
                                          min_independent_partners = 3L,
                                          submission_window = 5L,
                                          method = c("remote", "local"),
                                          database = "nt",
                                          score_range = 8,
                                          min_score = 70,
                                          max_hits = 20L,
                                          ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""),
                                          poll_max_wait = 1800,
                                          barcode_term = NULL,
                                          query_span = c("amplicon", "primer_inclusive"),
                                          chunk_size = 200L,
                                          max_consecutive_batch_failures = 3L,
                                          max_query_len = NULL,
                                          max_batch_bp = 100000L,
                                          prioritize_uncached = TRUE,
                                          retry_insufficient = TRUE,
                                          local_corroboration = NULL,
                                          skip_locally_corroborated = TRUE,
                                          verbose = TRUE) {

  if (!is.character(accessions) || length(accessions) == 0L)
    stop("accessions must be a non-empty character vector.", call. = FALSE)
  method <- match.arg(method)
  query_span <- match.arg(query_span)
  if (!is.logical(skip_locally_corroborated) || length(skip_locally_corroborated) != 1L ||
      is.na(skip_locally_corroborated))
    stop("skip_locally_corroborated must be TRUE or FALSE.", call. = FALSE)
  if (!is.null(local_corroboration)) {
    lc_needed <- c("accession", "local_tier", "n_independent_conspecific",
                   "best_independent_pident")
    if (!is.data.frame(local_corroboration))
      stop("local_corroboration must be NULL or a data frame from corroborate_references_locally().",
           call. = FALSE)
    lc_missing <- setdiff(lc_needed, names(local_corroboration))
    if (length(lc_missing) > 0L)
      stop(sprintf(
        "local_corroboration is missing required column(s): %s (expected corroborate_references_locally() output).",
        paste(lc_missing, collapse = ", ")
      ), call. = FALSE)
  }
  if (!is.numeric(chunk_size) || length(chunk_size) != 1L || is.na(chunk_size) ||
      chunk_size < 1L)
    stop("chunk_size must be a positive integer (Inf for a single unchunked call).",
         call. = FALSE)
  if (!is.null(max_query_len) &&
      (!is.numeric(max_query_len) || length(max_query_len) != 1L ||
       is.na(max_query_len) || max_query_len < 1))
    stop("max_query_len must be NULL, a positive number, or Inf to disable.", call. = FALSE)
  if (!is.numeric(max_batch_bp) || length(max_batch_bp) != 1L ||
      is.na(max_batch_bp) || max_batch_bp < 1)
    stop("max_batch_bp must be a positive number (Inf to disable).", call. = FALSE)
  if (!is.logical(prioritize_uncached) || length(prioritize_uncached) != 1L ||
      is.na(prioritize_uncached))
    stop("prioritize_uncached must be TRUE or FALSE.", call. = FALSE)
  if (!is.logical(retry_insufficient) || length(retry_insufficient) != 1L ||
      is.na(retry_insufficient))
    stop("retry_insufficient must be TRUE or FALSE.", call. = FALSE)
  if (!is.numeric(incongruent_ttl_days) || length(incongruent_ttl_days) != 1L ||
      is.na(incongruent_ttl_days) || incongruent_ttl_days <= 0)
    stop("incongruent_ttl_days must be a positive number (Inf to never expire an \"incongruent\" verdict).",
         call. = FALSE)

  # max_query_len's default depends on barcode_term (a marker-aware bound
  # when one is supplied, a flat absolute fallback otherwise) -- resolved
  # here, once, rather than as a literal default value in the signature
  # above. tryCatch(): TaxaTools::resolve_barcode_primers() requires the
  # SPECIFIC primer variant and errors on an ambiguous/unlisted barcode_term
  # -- the SAME error .trim_queries_to_amplicon() would already raise later
  # for the identical reason, just deferred to chunk-processing time; caught
  # here purely so resolving this default never introduces a NEW upfront
  # failure mode ahead of where one already existed, falling back to the
  # flat 5000L default instead.
  if (is.null(max_query_len)) {
    max_query_len <- if (!is.null(barcode_term)) {
      primer_info <- tryCatch(TaxaTools::resolve_barcode_primers(barcode_term),
                              error = function(e) NULL)
      if (!is.null(primer_info) && !is.null(primer_info$amplicon_range)) {
        as.numeric(primer_info$amplicon_range[2L]) * 10
      } else {
        5000
      }
    } else {
      5000
    }
  }

  unique_acc <- unique(accessions[!is.na(accessions) & nzchar(accessions)])
  if (length(unique_acc) == 0L)
    stop("No valid (non-NA, non-blank) accessions supplied.", call. = FALSE)

  # Full kingdom->species ladder, not just family/genus/species -- see
  # this function's own @section Coarse-rank diagnostic below. min_congruent_
  # rank (default "family") still controls the CLASSIFICATION threshold
  # unchanged; the extra coarser ranks only give finest_common_rank more to
  # report when family (or finer) fails, so a caller can tell "missed
  # family but still same order" from "no agreement even at phylum" instead
  # of both collapsing to the identical NA.
  rank_system <- TaxaTools::standard_ranks

  # params_key: one global string per cached row. The version tag
  # (.EVAL_REF_ACC_VERSION, file scope -- see its own roxygen for the bump
  # history and the discipline around bumping it) and every verdict-
  # affecting argument go in; call mechanics stay out. Built by
  # .build_params_key() so migrate_reference_cache() computes the identical
  # key from the identical code.
  params_key <- .build_params_key(
    top_n = top_n, min_congruent_rank = min_congruent_rank,
    submission_window = submission_window,
    hierarchy_incongruent_threshold = hierarchy_incongruent_threshold,
    min_independent_partners = min_independent_partners,
    score_range = score_range, min_score = min_score, max_hits = max_hits,
    method = method, database = database, query_span = query_span
  )

  cache <- .load_reference_accession_cache(cache_dir)
  if (!"params_key" %in% names(cache)) cache$params_key <- NA_character_

  now <- Sys.time()

  in_cache <- cache[cache$accession %in% unique_acc &
                    !is.na(cache$params_key) & cache$params_key == params_key, ,
                    drop = FALSE]

  # Per-flag TTL. The asymmetry between the three expiring flags and
  # "congruent" is not caution, it is what each verdict actually claims:
  #
  #   "congruent" asserts that corroborating evidence WAS FOUND. New NCBI
  #     deposits can only add more of it; nothing a later BLAST returns can
  #     withdraw a match that was already observed. Cached indefinitely.
  #
  #   "incongruent" asserts that corroborating evidence was NOT found -- a
  #     statement about ABSENCE, and absence is exactly what later evidence
  #     overturns. Expires after incongruent_ttl_days (2026-09-02).
  #
  #   "insufficient_independent_evidence" (original) and
  #     "not_evaluated_oversized" (2026-09-01, never actually submitted to
  #     BLAST, so a later annotation/primer fix or a raised max_query_len
  #     could change the answer) are both explicitly "we do not know yet".
  #
  # The incongruent TTL was added after a measured case, not on principle:
  # OP056918 (Cryptacanthodes maculatus) read "incongruent" with no
  # corroboration anywhere on 2026-09-01 and "congruent" with four
  # conspecific hits at 100% on 2026-09-02, under an IDENTICAL params_key.
  # Under the previous policy that first, wrong verdict would have been
  # cached forever -- and "incongruent" is the only verdict that causes a
  # reference to be REMOVED (see remove_incongruent_references()), so a
  # permanently stale one is the most costly kind. The recheck is cheap:
  # "incongruent" is ~1% of a real accession population (12 of 995 on the
  # PtConception screen), so a much shorter TTL than the "we do not know yet"
  # flags costs almost nothing while protecting the destructive decision.
  # 30 days, not 180, because the thing that goes stale underneath the
  # verdict is NCBI's `nt` snapshot, and that is rebuilt on the order of days
  # to weeks -- a TTL far longer than the rebuild interval would defeat the
  # purpose (see the note just below).
  #
  # WHAT GOES STALE IS NCBI'S `nt` SNAPSHOT, not the accession and not this
  # package's math. Established 2026-09-02 by
  # diagnostics/blast_verdict_repeatability_probe.R: three back-to-back
  # replicates of all 12 PtConception "incongruent" accessions returned
  # identical verdicts AND identical hit sets (Jaccard 1.000), so BLAST is
  # exactly reproducible at a fixed params_key; and the corroborating
  # records' create- and update-dates are both months earlier, so they were
  # not newly released. `nt` is a periodically-rebuilt snapshot of nuccore,
  # and a record public in Entrez need not be searchable in `nt` until a
  # rebuild includes it. Both verdicts were correct given the database each
  # was computed against -- which is precisely the situation a TTL exists
  # for.
  #
  # "locally_corroborated" (2026-09-03) is Inf like "congruent" and for the
  # same reason: it asserts corroborating evidence WAS found (in the
  # caller's own reference set rather than in nt). Enumerated explicitly so
  # the next new flag value has to be placed here deliberately.
  # "not_evaluated_wrong_marker" (2026-09-04) sits with the "we don't know
  # yet" flags at 180 days rather than with the permanent ones, and that is a
  # deliberate reading of what it claims: the accession's own annotation says
  # it carries a different marker, which is stable, but the CLAIM is relative
  # to this call's barcode_term -- and an annotation can also be corrected
  # upstream at NCBI. Retryable is the safe direction; nothing acts on it.
  ttl_days_for_flag <- function(flag) {
    ifelse(
      flag %in% c("insufficient_independent_evidence", "not_evaluated_oversized",
                  "not_evaluated_wrong_marker"),
      insufficient_evidence_ttl_days,
      ifelse(flag %in% "incongruent", incongruent_ttl_days,
             ifelse(flag %in% c("congruent", "locally_corroborated"), Inf, Inf))
    )
  }
  row_ttl_secs <- ttl_days_for_flag(in_cache$hierarchy_flag) * 86400
  fresh_enough <- if (isTRUE(retry_insufficient)) {
    is.infinite(row_ttl_secs) |
      (as.numeric(now) - as.numeric(in_cache$evaluated_at)) < row_ttl_secs
  } else {
    # retry_insufficient = FALSE: never retry ANY expired row this call --
    # serve it from cache regardless of age, so a caller expecting a purely
    # cache-served run (nothing new to evaluate) doesn't silently pay real
    # NCBI cost anyway. See @param retry_insufficient.
    rep(TRUE, nrow(in_cache))
  }
  # A cached "locally_corroborated" row is a cache hit only while the caller
  # still wants the skip. skip_locally_corroborated = FALSE says "BLAST these
  # after all", so such a row goes back into needs_eval regardless of TTL --
  # the flag records a decision not to evaluate, not an evaluation.
  if (!isTRUE(skip_locally_corroborated))
    fresh_enough <- fresh_enough & !(in_cache$hierarchy_flag %in% "locally_corroborated")
  cache_hit_rows <- in_cache[fresh_enough, , drop = FALSE]
  # A scalar assigned onto a NEW column of a possibly-zero-row data frame
  # does not recycle the way it would on an existing column -- base R
  # errors ("replacement has 1 row, data has 0") rather than silently
  # producing a zero-length column, so this must be sized explicitly.
  cache_hit_rows$cache_hit <- rep(TRUE, nrow(cache_hit_rows))

  needs_eval <- setdiff(unique_acc, cache_hit_rows$accession)

  if (isTRUE(prioritize_uncached)) {
    # Never-before-cached (or cached under a different params_key)
    # accessions first; expired capped rows actually being retried this call
    # last -- see @param prioritize_uncached. Purely a reordering of
    # needs_eval's own elements (setdiff()/intersect() both preserve the
    # first argument's order), never changes its membership.
    retried_expired <- if (isTRUE(retry_insufficient)) {
      in_cache$accession[!fresh_enough]
    } else {
      character(0L)
    }
    never_evaluated <- setdiff(needs_eval, retried_expired)
    needs_eval <- c(never_evaluated, intersect(needs_eval, retried_expired))
  }

  # ---- Local corroboration skip (2026-09-03) --------------------------------
  # An accession that still needs a verdict but is independently corroborated
  # by a conspecific in the caller's OWN reference set (corroborate_
  # references_locally(): a different submission batch, identity >=
  # min_pident over >= min_overlap of the amplicon) is not BLASTed at all.
  # It gets a real cached row, hierarchy_flag = "locally_corroborated", with
  # the corroboration's own numbers where the BLAST diagnostics would have
  # gone and NA elsewhere -- never a fabricated BLAST result. Measured on the
  # real PtConception screen this is ~40% of the BLAST population (15% on
  # GreatLakes), and it is free. Applied to needs_eval only: a row that
  # already has a BLAST verdict keeps it.
  skipped_rows <- NULL
  if (!is.null(local_corroboration) && isTRUE(skip_locally_corroborated) &&
      length(needs_eval) > 0L) {
    lc_acc <- .strip_acc_version(local_corroboration$accession)
    corroborated_acc <- lc_acc[local_corroboration$local_tier %in% "corroborated"]
    is_skip <- .strip_acc_version(needs_eval) %in% corroborated_acc
    if (any(is_skip)) {
      skip_acc <- needs_eval[is_skip]
      idx <- match(.strip_acc_version(skip_acc), lc_acc)
      skipped_rows <- data.frame(
        accession = skip_acc,
        listed_taxon = if ("species" %in% names(local_corroboration)) {
          as.character(local_corroboration$species[idx])
        } else {
          NA_character_
        },
        n_independent_top_matches = as.integer(local_corroboration$n_independent_conspecific[idx]),
        n_top_matches_available = NA_integer_,
        frac_independent_below_min_congruent_rank = NA_real_,
        finest_common_rank = "species",
        best_hit_pident = NA_real_,
        best_agreeing_pident = 100 * as.numeric(local_corroboration$best_independent_pident[idx]),
        best_disagreeing_pident = NA_real_, best_disagreeing_taxon = NA_character_,
        congruent_evidence_exists_anywhere = TRUE,
        congruent_evidence_best_pident = NA_real_,
        hierarchy_flag = "locally_corroborated",
        evaluated_at = now,
        cache_hit = FALSE,
        params_key = params_key,
        taxonomy_resolution_source = NA_character_,
        query_len_submitted = NA_integer_,
        query_trim_path = NA_character_,   # never fetched, so never trimmed
        n_excluded_same_batch = NA_integer_,
        n_excluded_not_species_resolved = NA_integer_,
        # Provenance (2026-09-05 critical-fix-review finding B5): WHICH
        # accession is vouching for this one. A locally_corroborated verdict
        # is cached with TTL Inf and exempt from refine_reference_verdicts()'s
        # trust-weighted refinement -- reasonable for the MATCH itself (a
        # permanent fact), but the corroborator's own label is exactly as
        # falsifiable as any other accession's. Recording it here is the same
        # transparency treatment verify_removal_candidates() already gives its
        # own corroborators, so a reviewer (or a future automated check) can
        # look this accession up too, rather than the corroboration resting
        # on an unnamed, unverifiable partner forever.
        local_corroborator_accession = .strip_acc_version(
          as.character(local_corroboration$best_independent_partner[idx])),
        stringsAsFactors = FALSE
      )
      needs_eval <- needs_eval[!is_skip]
      cache <- cache[!(cache$accession %in% skipped_rows$accession &
                       cache$params_key == params_key), , drop = FALSE]
      cache <- rbind(cache, .align_to_cache_columns(skipped_rows, cache))
      .save_reference_accession_cache(cache_dir, cache)
      if (verbose)
        message(sprintf(
          "evaluate_reference_accessions(): %d skipped: independently corroborated in the local reference set (hierarchy_flag = 'locally_corroborated', never submitted to BLAST).",
          nrow(skipped_rows)
        ))
    }
  }
  n_skipped_local <- if (is.null(skipped_rows)) 0L else nrow(skipped_rows)

  if (verbose)
    message(sprintf(
      "evaluate_reference_accessions(): %d unique accession(s), %d from cache, %d to evaluate.",
      length(unique_acc), nrow(cache_hit_rows), length(needs_eval)
    ))

  out_cols <- c("accession", "listed_taxon", "n_independent_top_matches",
               "n_top_matches_available", "frac_independent_below_min_congruent_rank",
               "finest_common_rank", "best_hit_pident", "best_agreeing_pident",
               "best_disagreeing_pident", "best_disagreeing_taxon",
               "congruent_evidence_exists_anywhere",
               "congruent_evidence_best_pident", "hierarchy_flag", "evaluated_at", "cache_hit",
               "taxonomy_resolution_source", "query_len_submitted", "query_trim_path",
               "n_excluded_same_batch", "n_excluded_not_species_resolved",
               "local_corroborator_accession")

  # No early return for a purely cache-served call (removed 2026-09-03): the
  # general path below handles an empty needs_eval (the chunk loop simply
  # does not run), and it is the only path that appends the post-hoc
  # listed_taxon_is_species / label_confidence / reference_action columns
  # and the run_summary attribute -- the old early return silently omitted
  # all of them from a fully-cached result, and could not carry the
  # locally-corroborated rows either.

  # ---- Chunked evaluation with incremental cache writes --------------------
  # needs_eval is processed chunk_size accessions at a time (default 200L,
  # matching this ecosystem's own previously-manual chunking convention --
  # see AuditNCBI_Goal2_MatchCandidateScreen.R's header comment, written
  # before this was automated). The persistent cache is written after EACH
  # chunk, not once at the very end -- an interruption (crash, Ctrl+C, lost
  # connection) after that point only loses whatever chunk was still in
  # flight, not every accession successfully evaluated earlier in the same
  # call. See @section Chunked evaluation and NCBI rate-limiting resilience
  # below for the full rationale.
  chunks <- if (length(needs_eval) > 0L) {
    split(needs_eval, ceiling(seq_along(needs_eval) / chunk_size))
  } else {
    list()
  }

  all_computed_rows <- vector("list", length(chunks))
  missing_acc <- character(0)
  circuit_breaker_tripped <- FALSE
  n_chunks_attempted <- 0L
  pair_cache <- .load_reference_pair_cache(cache_dir)

  for (ci in seq_along(chunks)) {
    chunk_acc <- chunks[[ci]]
    if (verbose && length(chunks) > 1L)
      message(sprintf(
        "evaluate_reference_accessions(): chunk %d/%d (%d accession(s))...",
        ci, length(chunks), length(chunk_acc)
      ))

    chunk_result <- .evaluate_reference_accessions_chunk(
      chunk_acc, rank_system = rank_system, method = method, database = database,
      score_range = score_range, min_score = min_score, max_hits = max_hits,
      ncbi_api_key = ncbi_api_key, poll_max_wait = poll_max_wait,
      barcode_term = barcode_term,
      max_consecutive_batch_failures = max_consecutive_batch_failures,
      max_query_len = max_query_len, max_batch_bp = max_batch_bp,
      top_n = top_n, min_congruent_rank = min_congruent_rank,
      submission_window = submission_window,
      min_independent_partners = min_independent_partners,
      hierarchy_incongruent_threshold = hierarchy_incongruent_threshold,
      params_key = params_key, now = now, verbose = verbose,
      query_span = query_span
    )
    n_chunks_attempted <- ci
    missing_acc <- union(missing_acc, chunk_result$missing_acc)

    if (!is.null(chunk_result$computed_rows) && nrow(chunk_result$computed_rows) > 0L) {
      all_computed_rows[[ci]] <- chunk_result$computed_rows
      # ---- Incremental cache write: persist THIS chunk's results now,
      # rather than waiting for every remaining chunk to also finish. ----
      cache <- cache[!(cache$accession %in% chunk_result$computed_rows$accession &
                       cache$params_key == params_key), , drop = FALSE]
      cache <- rbind(cache, .align_to_cache_columns(chunk_result$computed_rows, cache))
      .save_reference_accession_cache(cache_dir, cache)

      # Sidecar pair table, written on the same incremental schedule and for
      # the same reason (an interruption should only lose the chunk still in
      # flight). Superseded rows for these accessions are dropped first, so
      # re-evaluating an accession replaces its votes rather than
      # accumulating a second, stale copy alongside them.
      if (!is.null(chunk_result$pair_table) && nrow(chunk_result$pair_table) > 0L) {
        new_pairs <- chunk_result$pair_table
        new_pairs$params_key   <- params_key
        new_pairs$evaluated_at <- now
        pair_cache <- pair_cache[!(pair_cache$id_x %in% new_pairs$id_x &
                                     pair_cache$params_key == params_key), , drop = FALSE]
        pair_cache <- rbind(pair_cache, new_pairs[, names(pair_cache), drop = FALSE])
        .save_reference_pair_cache(cache_dir, pair_cache)
      }
    }

    if (isTRUE(chunk_result$circuit_breaker_tripped)) {
      circuit_breaker_tripped <- TRUE
      break  # stop processing further chunks -- see the chunk loop's own
             # header comment; nothing past this point is worth submitting
             # to a confirmed-throttled NCBI connection right now.
    }
  }

  # Every accession in a chunk the loop never even reached (the tail after
  # an early circuit-breaker stop) is "not evaluated this call" too --
  # identical treatment to any other missing_acc, so it shows up as an NA
  # row below and is retried on the next call, never silently dropped.
  if (circuit_breaker_tripped && n_chunks_attempted < length(chunks)) {
    missing_acc <- union(
      missing_acc,
      unlist(chunks[(n_chunks_attempted + 1L):length(chunks)], use.names = FALSE)
    )
  }

  computed_rows <- Filter(Negate(is.null), all_computed_rows)
  computed_rows <- if (length(computed_rows) > 0L) do.call(rbind, computed_rows) else NULL

  computed_out <- if (!is.null(computed_rows) && nrow(computed_rows) > 0L) {
    computed_rows[, out_cols, drop = FALSE]
  } else {
    NULL
  }

  failed_out <- if (length(missing_acc) > 0L) {
    data.frame(
      accession = missing_acc, listed_taxon = NA_character_,
      n_independent_top_matches = NA_integer_, n_top_matches_available = NA_integer_,
      frac_independent_below_min_congruent_rank = NA_real_,
      finest_common_rank = NA_character_,
      best_hit_pident = NA_real_, best_agreeing_pident = NA_real_,
      best_disagreeing_pident = NA_real_, best_disagreeing_taxon = NA_character_,
      congruent_evidence_exists_anywhere = NA,
      congruent_evidence_best_pident = NA_real_,
      hierarchy_flag = NA_character_,
      evaluated_at = as.POSIXct(NA), cache_hit = FALSE,
      taxonomy_resolution_source = NA_character_,
      query_len_submitted = NA_integer_, query_trim_path = NA_character_,
      n_excluded_same_batch = NA_integer_, n_excluded_not_species_resolved = NA_integer_,
      local_corroborator_accession = NA_character_,
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }

  skipped_out <- if (!is.null(skipped_rows)) skipped_rows[, out_cols, drop = FALSE] else NULL

  out <- do.call(rbind, Filter(Negate(is.null), list(
    cache_hit_rows[, out_cols, drop = FALSE], skipped_out, computed_out, failed_out
  )))
  rownames(out) <- NULL

  # listed_taxon_is_species: a structurally different problem from both
  # mislabeling (hierarchy_flag) and hybrid-labeling (taxonomy_resolution_
  # source) -- some real accessions are labeled at coarser-than-species
  # resolution to begin with (e.g. "Serranidae sp. JL-2015", a family name
  # used in place of a genus plus an informal specimen code -- found live,
  # 2026-08-11, GreatLakes population). Such a reference can't discriminate
  # at species level regardless of whether it's internally self-consistent,
  # so it's worth surfacing even when hierarchy_flag itself reads
  # "congruent". Reuses TaxaTools::is_plausible_binomial() directly (no new
  # logic) -- purely a function of listed_taxon, which is already stored,
  # so this is computed post-hoc on the final result rather than added to
  # the persistent cache schema: no .EVAL_REF_ACC_VERSION bump, no cache
  # invalidation, applies instantly even to an existing cache with zero
  # recompute cost. Kept as its own column, not folded into hierarchy_flag,
  # matching this file's own established design (Check 1/Check 2 in the
  # archived DECIPHER-era design, best_agreeing_pident/best_disagreeing_
  # pident here -- separate diagnostic signals, combined only by the
  # caller, never conflated into one column).
  # is_plausible_binomial()'s own grepl()-based implementation returns FALSE
  # (not NA) for an NA input -- would misleadingly read "checked, not a
  # species name" for a fetch-failure row (listed_taxon itself NA) rather
  # than "unknown, not evaluated"; guarded explicitly here.
  out$listed_taxon_is_species <- ifelse(
    is.na(out$listed_taxon), NA, TaxaTools::is_plausible_binomial(out$listed_taxon)
  )

  # label_confidence / label_identity_margin / reference_action -- derived
  # here, post-hoc, from columns already in the result, for exactly the
  # reason listed_taxon_is_species just above is: a pure function of stored
  # columns costs no .EVAL_REF_ACC_VERSION bump, no cache invalidation, and
  # applies instantly to an existing cache. `hierarchy_flag`'s own meaning
  # and cached values are untouched -- these are additive columns beside it,
  # not a redefinition of it. See score_reference_labels() for the formula,
  # its one free parameter, and why "remove" carries two hard vetoes.
  # 2026-09-03: forward the caller's local-corroboration table so the veto
  # (remove -> inspect on an independently corroborated accession) and the
  # corroboration_source provenance are applied here, not only when a caller
  # remembers to call score_reference_labels() a second time.
  out <- score_reference_labels(out, local_corroboration = local_corroboration)

  # ---- Run summary: what happened this call, in one place -------------------
  # See @section Chunked evaluation and NCBI rate-limiting resilience below.
  # n_evaluated_this_call counts accessions that got a REAL verdict this
  # call (present in computed_rows) -- NOT nrow(out), which also includes
  # cache hits and NA missing_acc rows.
  n_evaluated_this_call <- if (!is.null(computed_rows)) nrow(computed_rows) else 0L
  n_total <- length(unique_acc)
  n_resolved <- nrow(cache_hit_rows) + n_evaluated_this_call + n_skipped_local
  pct_complete <- if (n_total > 0L) round(100 * n_resolved / n_total, 1) else 100
  recommended_pause_minutes <- 15L

  run_summary <- list(
    n_total = n_total,
    n_from_cache = nrow(cache_hit_rows),
    n_evaluated_this_call = n_evaluated_this_call,
    n_skipped_locally_corroborated = n_skipped_local,
    n_pending = length(missing_acc),
    pct_complete = pct_complete,
    circuit_breaker_tripped = circuit_breaker_tripped,
    recommended_pause_minutes = if (circuit_breaker_tripped) recommended_pause_minutes else NA_integer_
  )
  attr(out, "run_summary") <- run_summary

  if (circuit_breaker_tripped) {
    message(sprintf(
      paste0(
        "\nevaluate_reference_accessions(): stopped early -- NCBI appears to be ",
        "rate-limiting or CPU-throttling this connection.\n",
        "  %d of %d accession(s) resolved this call (%.1f%% of the full request); ",
        "%d still pending.\n",
        "  Results so far are cached%s.\n",
        "  Recommended: wait at least %d minutes, then call ",
        "evaluate_reference_accessions() again with the SAME accessions and ",
        "cache_dir -- already-cached accessions will not be re-BLASTed, only ",
        "the %d still-pending one(s) will be attempted.\n"
      ),
      n_resolved, n_total, pct_complete, length(missing_acc),
      if (!is.null(cache_dir)) sprintf(" at %s", cache_dir) else " (cache_dir = NULL -- NOT persisted; nothing will be resumable next call)",
      recommended_pause_minutes, length(missing_acc)
    ))
  }

  out
}

#' Annotate a Match Object with Reference-Accession Quality, Without Removing Anything
#'
#' The RECOMMENDED default consumer of [evaluate_reference_accessions()] --
#' left-joins its evaluation columns onto `match_df` by accession
#' (version-suffix-stripped, same convention as
#' [remove_incongruent_references()]) so `hierarchy_flag` and the identity/
#' coverage diagnostics travel with the match object for review, without
#' ever discarding a candidate taxon.
#'
#' @section Why flag-by-default, not drop-by-default (2026-08-07):
#' [remove_incongruent_references()] (below) was this session's first cut,
#' and was the ONLY consumer until a real case
#' (`Abylopsis eschscholtzii`, `KY594854`/`KX384617`) showed why an
#' unreviewed hard drop is the wrong default: `hierarchy_flag =
#' "incongruent"` cannot currently distinguish a genuine mislabel from
#' "correct label, but this marker has poor resolving power at this rank
#' for this clade and GenBank coverage is thin" -- see
#' [evaluate_reference_accessions()]'s own `@section Identity diagnostics`.
#' Dropping the accession destroys the candidate taxon entirely and
#' irreversibly on the strength of a verdict that can be wrong in exactly
#' this ambiguous way. This ecosystem has made and reverted this same
#' mistake twice before with unrelated mechanisms, for the identical reason
#' -- `TaxaLikely::apply_coverage_constraints(constraint_behavior)`'s
#' default changed `"zero"` -> `"relabel"` (a genus-completeness NCBI-query
#' result treated as certain ground truth, permanently discarding a correct
#' hypothesis with no way for downstream evidence to recover it), and
#' `TaxaFetch::filter_gbif_quality()`'s `exclude_institution` ->
#' `flag_institution` (real, correctly-labeled observations near a
#' biodiversity institution were being auto-removed alongside real errors,
#' since proximity to an institution -- like thin reference coverage for a
#' correctly-labeled clade -- is not itself proof of error). Use this
#' function by default; reach for [remove_incongruent_references()]
#' deliberately, after review, not as the default pipeline step.
#'
#' @param match_df Data frame. A standardized match object (from
#'   [standardize_match_data()]) containing an `accession` column.
#' @param evaluation Data frame. Output of [evaluate_reference_accessions()].
#'
#' @return `match_df` with `hierarchy_flag`, `finest_common_rank`,
#'   `frac_independent_below_min_congruent_rank`, `n_independent_top_matches`,
#'   `n_top_matches_available`, `best_hit_pident`, `best_agreeing_pident`,
#'   `best_disagreeing_pident`, `congruent_evidence_exists_anywhere`, and
#'   `congruent_evidence_best_pident` joined on, plus `label_confidence`,
#'   `label_identity_margin`, `reference_action` and `listed_taxon_is_species`
#'   whenever `evaluation` carries them (it always does when it came from
#'   [evaluate_reference_accessions()] or [score_reference_labels()]; an
#'   `evaluation` read straight off a pre-2026-09-02 cache file will not).
#'   A row whose accession was not found in `evaluation` gets `NA` in all of
#'   these (not evaluated yet, not evidence of anything). Row count and order
#'   are unchanged.
#'
#' @seealso [evaluate_reference_accessions()], [remove_incongruent_references()]
#'
#' @export
flag_incongruent_references <- function(match_df, evaluation) {

  if (!is.data.frame(match_df))
    stop("match_df must be a data frame.", call. = FALSE)
  if (!is.data.frame(evaluation))
    stop("evaluation must be a data frame.", call. = FALSE)

  join_cols <- c("hierarchy_flag", "finest_common_rank",
                 "frac_independent_below_min_congruent_rank",
                 "n_independent_top_matches", "n_top_matches_available",
                 "best_hit_pident", "best_agreeing_pident", "best_disagreeing_pident",
                 "congruent_evidence_exists_anywhere", "congruent_evidence_best_pident")
  missing_cols <- setdiff(c("accession", join_cols), names(evaluation))
  # Carried when present, not required: an `evaluation` read straight off a
  # pre-2026-09-02 cache file has the diagnostics but not the derived
  # verdict columns, and joining what exists beats erroring on what doesn't.
  optional_cols <- intersect(
    c("label_confidence", "label_identity_margin", "reference_action",
      "listed_taxon_is_species",
      "corroboration_source", "local_best_independent_pident",
      "local_n_independent_conspecific", "action_reason"),
    names(evaluation)
  )
  join_cols <- c(join_cols, optional_cols)
  if (length(missing_cols) > 0L)
    stop(sprintf(
      "evaluation is missing required columns: %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)

  if (!"accession" %in% names(match_df)) {
    warning(
      "match_df has no 'accession' column -- cannot match against evaluated ",
      "reference accessions. Returning match_df unchanged.",
      call. = FALSE
    )
    return(match_df)
  }

  collide <- intersect(join_cols, names(match_df))
  if (length(collide) > 0L)
    stop(sprintf(
      "match_df already has column(s) also produced by flag_incongruent_references(): %s -- rename or drop them first to avoid ambiguity.",
      paste(collide, collapse = ", ")
    ), call. = FALSE)

  match_df$.join_acc   <- sub("\\.[0-9]+$", "", match_df$accession)
  match_df$.orig_order <- seq_len(nrow(match_df))
  eval_join <- evaluation[!duplicated(evaluation$accession), c("accession", join_cols)]
  eval_join$.join_acc <- sub("\\.[0-9]+$", "", eval_join$accession)
  eval_join$accession <- NULL

  out <- merge(match_df, eval_join, by = ".join_acc", all.x = TRUE, sort = FALSE)
  # merge() does not preserve row order -- .orig_order (added above,
  # untouched by the join) restores it, the standard base-R idiom, rather
  # than a fragile attempt to re-derive order from post-merge content.
  out <- out[order(out$.orig_order), , drop = FALSE]
  out$.join_acc <- NULL
  out$.orig_order <- NULL
  rownames(out) <- NULL
  out
}

#' Remove Confidently-Incongruent Reference Accessions from a Match Object
#'
#' Filters a match data frame to remove rows whose reference accession was
#' flagged `"incongruent"` by [evaluate_reference_accessions()] -- mirrors
#' `TaxaLikely::remove_flagged_references()`'s existing consumption pattern
#' (which drops `flag_reference_errors()`'s `"likely_mislabeled"` rows) but
#' fed from the new BLAST-based verdict instead. Deliberately conservative:
#' only the confident `"incongruent"` verdict is dropped by default --
#' `"insufficient_independent_evidence"` is ambiguous (may simply mean a
#' sparsely-referenced region of the database, not a real problem) and is
#' retained unless `remove_insufficient_evidence = TRUE`.
#'
#' @section Use [flag_incongruent_references()] first (2026-08-07):
#' This function is no longer the recommended default pipeline step -- see
#' [flag_incongruent_references()]'s own `@section Why flag-by-default, not
#' drop-by-default` for the real case that changed this. Reach for this
#' function deliberately, after reviewing `hierarchy_flag` alongside the
#' identity diagnostics (`best_agreeing_pident`/`best_disagreeing_pident`/
#' `congruent_evidence_exists_anywhere`), not as an unreviewed default step.
#'
#' @section The evidence gate is now the default (2026-09-02):
#' `gate = "action"` (the default) removes an accession only when
#' [score_reference_labels()] resolved it to `reference_action == "remove"`
#' -- flagged `"incongruent"` AND uncorroborated anywhere AND below the
#' confidence threshold -- rather than on `hierarchy_flag == "incongruent"`
#' alone. `hierarchy_flag` is a majority vote over the top-N neighbours in
#' which percent identity never appears, so in a thinly-covered clade it
#' fires on correct references by construction. Measured on the real
#' 995-accession PtConception screen: the old `gate = "flag"` behaviour would
#' have removed 12 accessions behind 1,688 observations -- including cabezon
#' (`OK172573`, 1,120 observations, agreeing hit at 100%) -- to catch the 4
#' (16 observations) that genuinely had no corroboration anywhere.
#' `gate = "action"` removes exactly those 4. Pass `gate = "flag"` to get the
#' pre-2026-09-02 behaviour back.
#'
#' @section This is a blacklist decision, not the whole signal:
#' Even under `gate = "action"` this function consumes only a yes/no removal
#' decision. The continuous signal ([score_reference_labels()]'s
#' `label_confidence`) travels separately, via
#' [flag_incongruent_references()], and is meant for review. A likelihood-model
#' covariate driven by it was prototyped on 2026-09-02 and removed the same
#' day -- see
#' `ecosystem_docs/REENTRY_PROMPT_reference_quality_verdicts_and_downstream_use.md`
#' for what was measured, before proposing it again. Do not let this
#' function's use become the only place the full `evaluation` object's signal
#' is consulted.
#'
#' @param match_df Data frame. A standardized match object (from
#'   [standardize_match_data()]) containing an `accession` column.
#' @param evaluation Data frame. Output of [evaluate_reference_accessions()].
#' @param gate Character, `"action"` (default) or `"flag"`. `"action"` removes
#'   accessions whose `reference_action` is `"remove"`; `"flag"` removes every
#'   accession whose `hierarchy_flag` is `"incongruent"`, the pre-2026-09-02
#'   behaviour. Under `"action"`, `reference_action` is computed on the fly
#'   via [score_reference_labels()] if `evaluation` does not already carry it.
#' @param remove_insufficient_evidence Logical (default `FALSE`). If `TRUE`,
#'   also removes accessions flagged `"insufficient_independent_evidence"`.
#'   Applies under both `gate` settings -- `reference_action` can never be
#'   `"remove"` for that flag on its own (see [score_reference_labels()]'s
#'   `@section Why "remove" also requires no corroboration anywhere`), so this
#'   argument stays the only way to drop them.
#' @param override_accessions Character vector of accession IDs (default
#'   `NULL`), or `NULL` to disable. Accessions listed here are NEVER removed,
#'   regardless of `hierarchy_flag` -- the automated counterpart to the
#'   `@section Use flag_incongruent_references() first` caution above.
#'   `hierarchy_flag = "incongruent"` alone cannot distinguish a genuine
#'   mislabel from a correctly-labeled record with poor marker resolution or
#'   thin corroborating coverage (a real confirmed case in this ecosystem:
#'   `Stereolepis doederleini` was flagged `"incongruent"` by a broad screen,
#'   then separately investigated and found to be exactly this -- not a real
#'   mislabel). [resolve_review_overrides()] derives this argument
#'   automatically from [review_flagged_accessions()]'s LLM second-look
#'   verdicts, so a caller can safely default to removing every flagged
#'   accession while still letting a specific, reviewed explanation override
#'   that default for the one accession it actually applies to -- rather
#'   than choosing between "remove everything, including real correctly-
#'   labeled records" and "remove nothing, unreviewed." Only ever rescues,
#'   never removes an accession `hierarchy_flag` would otherwise have kept.
#'
#' @return The input `match_df` with flagged rows removed. Unchanged if no
#'   flagged accessions are found.
#'
#' @seealso [evaluate_reference_accessions()], [flag_incongruent_references()],
#'   [resolve_review_overrides()]
#'
#' @export
remove_incongruent_references <- function(match_df,
                                          evaluation,
                                          remove_insufficient_evidence = FALSE,
                                          override_accessions = NULL,
                                          gate = c("action", "flag")) {

  if (!is.data.frame(match_df))
    stop("match_df must be a data frame.", call. = FALSE)
  if (!is.data.frame(evaluation))
    stop("evaluation must be a data frame.", call. = FALSE)
  if (!is.null(override_accessions) && !is.character(override_accessions))
    stop("override_accessions must be NULL or a character vector of accessions.", call. = FALSE)
  gate <- match.arg(gate)

  needed <- c("accession", "hierarchy_flag")
  missing_cols <- setdiff(needed, names(evaluation))
  if (length(missing_cols) > 0L)
    stop(sprintf(
      "evaluation is missing required columns: %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)

  if (gate == "action" && !"reference_action" %in% names(evaluation)) {
    # An `evaluation` from a pre-2026-09-02 cache read straight off disk has
    # the diagnostics but no derived verdict. Deriving it here (rather than
    # silently falling back to gate = "flag", which would remove ~3x more
    # accessions than the caller asked for) keeps the default meaningful;
    # a frame genuinely lacking the diagnostics gets a message naming the
    # explicit escape hatch instead of a bare column-not-found error.
    evaluation <- tryCatch(
      score_reference_labels(evaluation),
      error = function(e) stop(sprintf(
        paste0("gate = \"action\" needs `reference_action`, or the diagnostic columns ",
               "score_reference_labels() derives it from, and evaluation has neither ",
               "(%s).\n  Re-run evaluate_reference_accessions(), or pass gate = \"flag\" ",
               "for the pre-2026-09-02 hierarchy_flag-only behaviour."),
        conditionMessage(e)
      ), call. = FALSE)
    )
  }

  if (!"accession" %in% names(match_df)) {
    warning(
      "match_df has no 'accession' column -- cannot match against evaluated ",
      "reference accessions. Returning match_df unchanged.",
      call. = FALSE
    )
    return(match_df)
  }

  flags_to_remove <- if (gate == "flag") "incongruent" else character(0L)
  if (isTRUE(remove_insufficient_evidence))
    flags_to_remove <- c(flags_to_remove, "insufficient_independent_evidence")

  bad_ids <- evaluation$accession[evaluation$hierarchy_flag %in% flags_to_remove]
  if (gate == "action")
    bad_ids <- unique(c(
      bad_ids, evaluation$accession[evaluation$reference_action %in% "remove"]
    ))

  override_clean <- sub("\\.[0-9]+$", "", override_accessions)
  bad_ids_clean_check <- sub("\\.[0-9]+$", "", bad_ids)
  n_overridden <- length(intersect(bad_ids_clean_check, override_clean))
  bad_ids <- bad_ids[!bad_ids_clean_check %in% override_clean]
  if (n_overridden > 0L)
    message(sprintf(
      "%d flagged accession(s) kept despite hierarchy_flag, per override_accessions.",
      n_overridden
    ))

  if (length(bad_ids) == 0L) {
    message("No incongruent references to remove.")
    return(match_df)
  }

  acc_clean <- sub("\\.[0-9]+$", "", match_df$accession)
  bad_clean <- sub("\\.[0-9]+$", "", bad_ids)
  flagged_mask <- acc_clean %in% bad_clean

  n_rows_removed <- sum(flagged_mask)
  n_accessions   <- length(unique(acc_clean[flagged_mask]))

  if (n_rows_removed == 0L) {
    message("No incongruent accessions found in match_df.")
    return(match_df)
  }

  result <- match_df[!flagged_mask, , drop = FALSE]

  removed_for <- if (gate == "action") {
    c("reference_action == \"remove\"", flags_to_remove)
  } else {
    flags_to_remove
  }
  message(sprintf(
    "Removed %d row(s) (%d accession(s)) flagged as %s.",
    n_rows_removed, n_accessions, paste(removed_for, collapse = " or ")
  ))

  result
}

#' Verify a Small, Flagged Reference Subset via BLAST, Not the Whole Database
#'
#' Bridges `TaxaLikely::flag_reference_errors()`'s free, offline (but known
#' over-flagging) within-reference-set mislabel screen to this package's
#' stronger, BLAST-based `evaluate_reference_accessions()` -- purpose-built
#' so a caller never has to BLAST an entire training reference database to
#' get the benefit of the better screen.
#'
#' @section Why the flagged subset, not the whole reference set (2026-08-18):
#' `TaxaLikely::train_likelihood_model()` calls `flag_reference_errors()`
#' unconditionally on every training run and silently drops every
#' `"likely_mislabeled"` accession before fitting H1/H2/H3 -- this has
#' always been true, it just went unnoticed until a user asked directly
#' whether it was happening at all. That screen is known to over-flag (see
#' `flag_reference_errors()`'s own `@param verified_clean`): a real pilot
#' check against a real GreatLakes 12S reference set found 0 of 40
#' randomly-sampled `"likely_mislabeled"` accessions confirmed as genuine
#' mislabels by this package's own `evaluate_reference_accessions()` (a
#' BLAST-based check against a broad, independent database) -- 85% looked
#' like false positives.
#'
#' `evaluate_reference_accessions()` is the right tool to adjudicate this,
#' but BLASTing an entire training reference database (which can be LARGER
#' than a typical match-candidate screening population -- confirmed on real
#' GreatLakes data, ~2,650 accessions vs. a 1,183-accession match-candidate
#' run that already tripped a real NCBI CPU-budget rejection) risks exactly
#' the shutout this package's rate-limit resilience
#' (`evaluate_reference_accessions(chunk_size=,
#' max_consecutive_batch_failures=)`) exists to survive, not avoid entirely.
#' `flag_reference_errors()` is already running for free (no NCBI call,
#' reuses the `seq_matrix` already built for training) -- this function
#' verifies only the small subset it actually flagged, turning "BLAST
#' thousands of accessions to find a few real mislabels" into "BLAST only
#' the disputed ones."
#'
#' @param flagged Either a data frame (output of
#'   `TaxaLikely::flag_reference_errors()`, with `id_x`/`error_type`
#'   columns) or a plain character vector of accession IDs to verify.
#' @param error_types Character vector (default `"likely_mislabeled"`).
#'   When `flagged` is a data frame, only rows whose `error_type` is in this
#'   set are verified. The default matches what
#'   `train_likelihood_model()` actually removes by default --
#'   `"unverified_singleton_high_match"` is computed by
#'   `flag_reference_errors()` but never acted on automatically, so
#'   verifying it too roughly doubles NCBI cost for a category that isn't
#'   currently removing anything from training. Pass
#'   `c("likely_mislabeled", "unverified_singleton_high_match")` to verify
#'   both.
#' @param trust_insufficient_evidence Logical (default `FALSE`). Whether an
#'   `"insufficient_independent_evidence"` verdict (broader evidence exists,
#'   but too little of it to say either way) counts as verified-clean.
#'   `FALSE` is the conservative choice -- an accession this ambiguous stays
#'   removed from training rather than being restored on thin grounds.
#' @param cache_dir,ncbi_api_key,barcode_term,... Forwarded to
#'   `evaluate_reference_accessions()`. `cache_dir` deliberately shares that
#'   function's own default (`tools::R_user_dir("TaxaMatch", "cache")`) --
#'   pass an explicit, project-scoped path shared with a real match-candidate
#'   screen so any accession appearing in both populations is served from
#'   cache for free rather than BLASTed twice.
#'
#' @return A list: `verified_clean` (character vector of accessions safe to
#'   pass to `flag_reference_errors(verified_clean=)`/
#'   `train_likelihood_model(verified_clean=)` -- everything NOT confirmed
#'   `"incongruent"`), and `evaluation` (the full
#'   `evaluate_reference_accessions()` output, for review). `verified_clean`
#'   is `character(0)` and `evaluation` is `NULL` when `flagged` contains no
#'   matching accessions -- no NCBI call is made in that case.
#'
#' @seealso [evaluate_reference_accessions()],
#'   [TaxaLikely::flag_reference_errors()]
#'
#' @examples
#' \dontrun{
#' seq_matrix <- TaxaLikely::build_sequence_matrix(reference_df,
#'   rank_system = c("family", "genus", "species"))
#' errors <- TaxaLikely::flag_reference_errors(seq_matrix)
#' result <- verify_flagged_references(errors,
#'   cache_dir = "~/my_project_ref_eval_cache")
#' lik_model <- TaxaLikely::train_likelihood_model(seq_matrix,
#'   rank_system = c("family", "genus", "species"),
#'   verified_clean = result$verified_clean)
#' }
#'
#' @export
verify_flagged_references <- function(flagged,
                                       error_types = "likely_mislabeled",
                                       trust_insufficient_evidence = FALSE,
                                       cache_dir = tools::R_user_dir("TaxaMatch", "cache"),
                                       ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""),
                                       barcode_term = NULL,
                                       ...) {

  if (is.data.frame(flagged)) {
    needed <- c("id_x", "error_type")
    missing_cols <- setdiff(needed, names(flagged))
    if (length(missing_cols) > 0L)
      stop(sprintf(
        "flagged is missing required columns: %s",
        paste(missing_cols, collapse = ", ")
      ), call. = FALSE)
    accessions <- unique(flagged$id_x[flagged$error_type %in% error_types])
  } else if (is.character(flagged)) {
    accessions <- unique(flagged)
  } else {
    stop(
      "flagged must be a data frame (TaxaLikely::flag_reference_errors() ",
      "output) or a character vector of accessions.",
      call. = FALSE
    )
  }

  if (length(accessions) == 0L) {
    message("No flagged accessions to verify -- no NCBI call made.")
    return(list(verified_clean = character(0L), evaluation = NULL))
  }

  qc <- evaluate_reference_accessions(
    accessions,
    cache_dir    = cache_dir,
    ncbi_api_key = ncbi_api_key,
    barcode_term = barcode_term,
    ...
  )

  # "locally_corroborated" (2026-09-03) counts as verified-clean alongside
  # "congruent": both assert corroborating evidence WAS found, only the
  # source differs (the caller's own reference set vs nt). It can only
  # appear here if the caller forwarded a local_corroboration table through
  # `...`.
  keep_flags <- if (isTRUE(trust_insufficient_evidence)) {
    c("congruent", "locally_corroborated", "insufficient_independent_evidence")
  } else {
    c("congruent", "locally_corroborated")
  }
  verified_clean <- unique(qc$accession[qc$hierarchy_flag %in% keep_flags])
  n_incongruent  <- sum(qc$hierarchy_flag == "incongruent", na.rm = TRUE)

  message(sprintf(
    "%d of %d flagged accession(s) verified NOT incongruent (safe to keep in training); %d confirmed incongruent.",
    length(verified_clean), length(accessions), n_incongruent
  ))

  list(verified_clean = verified_clean, evaluation = qc)
}

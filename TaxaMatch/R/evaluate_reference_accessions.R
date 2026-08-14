# NSE column names referenced via dplyr verbs below would otherwise trip an
# R CMD CHECK "no visible binding" note.
utils::globalVariables(c(
  "id_x", "id_y", "p_match", "is_independent", "is_sufficient_coverage",
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
    dplyr::left_join(anywhere, by = "id_x")

  out$n_independent_top_matches <- ifelse(
    is.na(out$n_independent_top_matches), 0L, out$n_independent_top_matches
  )
  out$n_top_matches_available <- ifelse(
    is.na(out$n_top_matches_available), 0L, out$n_top_matches_available
  )
  out$frac_independent_below_min_congruent_rank <- ifelse(
    is.na(out$frac_independent_below_min_congruent_rank),
    0.5, out$frac_independent_below_min_congruent_rank
  )
  out$congruent_evidence_exists_anywhere <- ifelse(
    is.na(out$congruent_evidence_exists_anywhere), FALSE, out$congruent_evidence_exists_anywhere
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
  missing_cols <- setdiff(names(empty), names(cached))
  if (length(missing_cols) > 0L) {
    warning(sprintf(
      "evaluate_reference_accessions(): cache at %s predates this package version (missing column(s): %s) -- starting a fresh cache. Every previously-cached verdict will be recomputed once.",
      path, paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
    return(empty)
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
                                                 top_n, min_congruent_rank, submission_window,
                                                 min_independent_partners,
                                                 hierarchy_incongruent_threshold,
                                                 params_key, now, verbose) {

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

  if (!is.null(barcode_term) && nrow(query_meta) > 0L) {
    query_meta$sequence <- .trim_queries_to_amplicon(
      query_meta$sequence, barcode_term = barcode_term, verbose = verbose
    )
  }

  computed_rows <- NULL
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
      max_consecutive_batch_failures = max_consecutive_batch_failures, verbose = verbose
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
        stringsAsFactors = FALSE
      )
    }
  }

  list(computed_rows = computed_rows, missing_acc = missing_acc,
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
#' no `taxa` list to decide up front. Staleness is handled asymmetrically:
#' `"congruent"`/`"incongruent"` verdicts are cached indefinitely (an
#' accession's own sequence/label doesn't change once deposited); only
#' `"insufficient_independent_evidence"` verdicts expire after
#' `insufficient_evidence_ttl_days` and are retried, since new NCBI deposits
#' could genuinely change that specific answer. A cached row is also treated
#' as stale (recomputed) if any parameter that affects the verdict itself
#' (`top_n`, `min_congruent_rank`, `submission_window`,
#' `hierarchy_incongruent_threshold`, `min_independent_partners`,
#' `score_range`, `min_score`, `max_hits`, `method`, `database`) differs from
#' the call that produced it.
#'
#' @param accessions Character vector of NCBI accessions to evaluate.
#'   Deduplicated internally.
#' @param cache_dir Character or `NULL`. Default
#'   `tools::R_user_dir("TaxaMatch", "cache")`. Set `NULL` to disable
#'   caching entirely (every call re-evaluates every accession).
#' @param insufficient_evidence_ttl_days Numeric (default `180`). See
#'   Caching above.
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
#'   can't be found is left at full length (never dropped or errored) and
#'   BLASTed as before. `NULL` (default) submits every sequence at full
#'   length, unchanged from prior behavior.
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
#'     \item{`hierarchy_flag`}{`"congruent"`, `"incongruent"`, or
#'       `"insufficient_independent_evidence"`. `NA` if the accession's own
#'       GenBank record could not be fetched (a `warning()` is issued
#'       listing these; not cached, so a subsequent call retries them).}
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
#'   `n_from_cache`, `n_evaluated_this_call`, `n_pending`, `pct_complete`,
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
#' @seealso [remove_incongruent_references()], [flag_incongruent_references()],
#'   [blast_sequences()]
#'
#' @export
evaluate_reference_accessions <- function(accessions,
                                          cache_dir = tools::R_user_dir("TaxaMatch", "cache"),
                                          insufficient_evidence_ttl_days = 180,
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
                                          chunk_size = 200L,
                                          max_consecutive_batch_failures = 3L,
                                          verbose = TRUE) {

  if (!is.character(accessions) || length(accessions) == 0L)
    stop("accessions must be a non-empty character vector.", call. = FALSE)
  method <- match.arg(method)
  if (!is.numeric(chunk_size) || length(chunk_size) != 1L || is.na(chunk_size) ||
      chunk_size < 1L)
    stop("chunk_size must be a positive integer (Inf for a single unchunked call).",
         call. = FALSE)

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

  # .EVAL_REF_ACC_VERSION: bump this any time an internal computation
  # detail changes without any caller-visible parameter changing (e.g. the
  # 2026-08-07 rank_system extension below) -- otherwise a cached row
  # computed under the OLD internal logic gets served as a "fresh" cache
  # hit forever under an unchanged params_key, silently keeping stale
  # values (e.g. a pre-fix finest_common_rank = NA where a fresh
  # computation would now report "order") indefinitely. Cheap insurance,
  # not something a caller ever sets directly.
  #
  # 2026-08-13 require_species_resolved_partner fix: deliberately NOT
  # bumped, matching the 2026-08-11 modifier-prefix fix's own precedent.
  # params_key is one global string applied uniformly to every cached row
  # (not conditional per row), so bumping it here would invalidate and
  # force a fresh re-BLAST of all ~1,163 already-correctly-cached real
  # GreatLakes rows -- real, unnecessary NCBI cost for a fix whose effect
  # is narrow (only rows whose top-N independent BLAST hits include a
  # non-species-resolved reference can possibly change) and, on the one
  # real case fully investigated (Stereolepis doederleini vs. its
  # Serranidae sp. JL-2015 partner), was confirmed to be a no-op on the
  # actual verdict. Instead, the specific rows worth re-checking (every
  # currently non-"congruent" row, the only rows where this filter could
  # plausibly change what a reviewer sees) were surgically removed from
  # the real persistent cache directly, so only those get re-evaluated
  # under the new logic on the next run.
  .EVAL_REF_ACC_VERSION <- "v4_hybrid_maternal_proxy"

  params_key <- paste(top_n, min_congruent_rank, submission_window,
                      hierarchy_incongruent_threshold, min_independent_partners,
                      score_range, min_score, max_hits, method, database,
                      .EVAL_REF_ACC_VERSION, sep = "|")

  cache <- .load_reference_accession_cache(cache_dir)
  if (!"params_key" %in% names(cache)) cache$params_key <- NA_character_

  now <- Sys.time()
  ttl_secs <- insufficient_evidence_ttl_days * 86400

  in_cache <- cache[cache$accession %in% unique_acc &
                    !is.na(cache$params_key) & cache$params_key == params_key, ,
                    drop = FALSE]
  fresh_enough <- in_cache$hierarchy_flag != "insufficient_independent_evidence" |
    (as.numeric(now) - as.numeric(in_cache$evaluated_at)) < ttl_secs
  cache_hit_rows <- in_cache[fresh_enough, , drop = FALSE]
  # A scalar assigned onto a NEW column of a possibly-zero-row data frame
  # does not recycle the way it would on an existing column -- base R
  # errors ("replacement has 1 row, data has 0") rather than silently
  # producing a zero-length column, so this must be sized explicitly.
  cache_hit_rows$cache_hit <- rep(TRUE, nrow(cache_hit_rows))

  needs_eval <- setdiff(unique_acc, cache_hit_rows$accession)

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
               "taxonomy_resolution_source")

  if (length(needs_eval) == 0L) {
    out <- cache_hit_rows[, out_cols, drop = FALSE]
    rownames(out) <- NULL
    return(out)
  }

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
  chunks <- split(needs_eval, ceiling(seq_along(needs_eval) / chunk_size))

  all_computed_rows <- vector("list", length(chunks))
  missing_acc <- character(0)
  circuit_breaker_tripped <- FALSE
  n_chunks_attempted <- 0L

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
      top_n = top_n, min_congruent_rank = min_congruent_rank,
      submission_window = submission_window,
      min_independent_partners = min_independent_partners,
      hierarchy_incongruent_threshold = hierarchy_incongruent_threshold,
      params_key = params_key, now = now, verbose = verbose
    )
    n_chunks_attempted <- ci
    missing_acc <- union(missing_acc, chunk_result$missing_acc)

    if (!is.null(chunk_result$computed_rows) && nrow(chunk_result$computed_rows) > 0L) {
      all_computed_rows[[ci]] <- chunk_result$computed_rows
      # ---- Incremental cache write: persist THIS chunk's results now,
      # rather than waiting for every remaining chunk to also finish. ----
      cache <- cache[!(cache$accession %in% chunk_result$computed_rows$accession &
                       cache$params_key == params_key), , drop = FALSE]
      cache <- rbind(cache, chunk_result$computed_rows[, names(cache), drop = FALSE])
      .save_reference_accession_cache(cache_dir, cache)
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
      stringsAsFactors = FALSE
    )
  } else {
    NULL
  }

  out <- do.call(rbind, Filter(Negate(is.null), list(
    cache_hit_rows[, out_cols, drop = FALSE], computed_out, failed_out
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

  # ---- Run summary: what happened this call, in one place -------------------
  # See @section Chunked evaluation and NCBI rate-limiting resilience below.
  # n_evaluated_this_call counts accessions that got a REAL verdict this
  # call (present in computed_rows) -- NOT nrow(out), which also includes
  # cache hits and NA missing_acc rows.
  n_evaluated_this_call <- if (!is.null(computed_rows)) nrow(computed_rows) else 0L
  n_total <- length(unique_acc)
  n_resolved <- nrow(cache_hit_rows) + n_evaluated_this_call
  pct_complete <- if (n_total > 0L) round(100 * n_resolved / n_total, 1) else 100
  recommended_pause_minutes <- 15L

  run_summary <- list(
    n_total = n_total,
    n_from_cache = nrow(cache_hit_rows),
    n_evaluated_this_call = n_evaluated_this_call,
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
#'   `congruent_evidence_best_pident` joined on. A row whose accession was
#'   not found in `evaluation` gets `NA` in all of these (not evaluated
#'   yet, not evidence of anything). Row count and order are unchanged.
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
#' @section Full-signal weighting is separate, later work:
#' This function only ever consumes `hierarchy_flag`'s binary blacklist
#' decision. The full per-accession quality signal (`frac_independent_
#' below_min_congruent_rank`, etc.) needs to survive through to
#' `TaxaLikely::evaluate_likelihoods()` so it can inflate/discount
#' likelihood the same way `score_likelihood_cov` already does for
#' alignment coverage -- that TaxaLikely-side consumption is real, agreed-on
#' future work, not designed or implemented here. Do not let this function's
#' use become the only place the full `evaluation` object's signal is
#' consulted.
#'
#' @param match_df Data frame. A standardized match object (from
#'   [standardize_match_data()]) containing an `accession` column.
#' @param evaluation Data frame. Output of [evaluate_reference_accessions()].
#' @param remove_insufficient_evidence Logical (default `FALSE`). If `TRUE`,
#'   also removes accessions flagged `"insufficient_independent_evidence"`.
#'
#' @return The input `match_df` with flagged rows removed. Unchanged if no
#'   flagged accessions are found.
#'
#' @seealso [evaluate_reference_accessions()], [flag_incongruent_references()]
#'
#' @export
remove_incongruent_references <- function(match_df,
                                          evaluation,
                                          remove_insufficient_evidence = FALSE) {

  if (!is.data.frame(match_df))
    stop("match_df must be a data frame.", call. = FALSE)
  if (!is.data.frame(evaluation))
    stop("evaluation must be a data frame.", call. = FALSE)

  needed <- c("accession", "hierarchy_flag")
  missing_cols <- setdiff(needed, names(evaluation))
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

  flags_to_remove <- "incongruent"
  if (isTRUE(remove_insufficient_evidence))
    flags_to_remove <- c(flags_to_remove, "insufficient_independent_evidence")

  bad_ids <- evaluation$accession[evaluation$hierarchy_flag %in% flags_to_remove]

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

  message(sprintf(
    "Removed %d row(s) (%d accession(s)) flagged as %s.",
    n_rows_removed, n_accessions, paste(flags_to_remove, collapse = " or ")
  ))

  result
}

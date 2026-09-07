# ==============================================================================
# investigate_flagged_accession() -- deep-dive verification for a single
# flagged reference accession
#
# Prompted directly by the user after manually reviewing evaluate_reference_
# accessions()'s real 2026-08-07 GreatLakes/PtConception results by hand (see
# TaxaMatch/CLAUDE.md's own top session note): PV382872's raw top BLAST hits
# looked alarming (an eel, a catfish, a parasitic isopod, all at ~99.5%
# identity) until direct verification showed they were all from the SAME
# real submission batch as the query itself -- evaluate_reference_
# accessions()'s own independence filter had already correctly excluded them,
# but nothing short of re-fetching the raw GenBank records by hand revealed
# that. This function automates exactly that kind of manual deep-dive, but
# ONLY for the small subset of accessions a caller has already decided are
# worth a closer look -- deliberately NOT meant to run at evaluate_reference_
# accessions()'s own broad, unrestricted scale.
#
# Two comparisons, per the user's own suggestion ("blast Cephalopholis argus
# to see how its other reference sequences look"):
#   1. Self-consistency: how well does the flagged accession match OTHER
#      real GenBank accessions of its own listed species? High identity
#      here is reassuring (the accession is self-consistent with its own
#      species -- the original "incongruent" flag more likely reflects thin
#      coverage of RELATED taxa, not a problem with this specific record).
#      Low identity here is a much stronger warning sign than anything
#      evaluate_reference_accessions() alone can report -- it means the
#      "does this look like a real X" question fails even within X itself.
#   2. Cross-taxon consistency: how well does the flagged accession match
#      other accessions of whichever taxon its disagreeing BLAST hits
#      belong to? High identity here (paired with low self-consistency
#      above) is the strongest evidence of a genuine mislabel.
# ==============================================================================

#' Search NCBI nucleotide for other accessions of a given species
#'
#' `rentrez::entrez_search()` returns UIDs, not accession strings -- this
#' resolves them via `entrez_summary()$caption`, the identical pattern
#' `.resolve_taxonomy_by_acc()` already uses for the reverse direction
#' (accession -> taxid).
#'
#' @section Length-ratio pre-filter (2026-08-08, Option B, now REQUIRED not optional):
#' A plain `[Organism]` search has no gene/marker constraint at all. Live
#' testing against the real `MZ605481` case (the motivating regression this
#' whole file exists to fix -- see `.blast_against_comparison_set()`'s own
#' `@section A real, live-found correction`) found this is not a rare edge
#' case: for `Pseudorasbora parva`, a species with a published reference
#' genome, 26 of the first 30 `[Organism]`-search results were whole-
#' chromosome shotgun-assembly records 60-80+ MILLION bp long (`slen`
#' confirmed live via `rentrez::entrez_summary()`) -- and
#' `.fetch_reference_accession_records()`'s `GBSeq_sequence` fetch silently
#' returns `NA` for records that large (too big for NCBI to embed inline),
#' so a caller relying on `want_sequence = TRUE` never even learns why they
#' got nothing. Filtering by length via the (already free, already batched)
#' `slen` ESummary field, BEFORE ever fetching full sequence content, is the
#' reentry prompt's own originally-deferred Option B -- deferred at design
#' time as "cheaper but doesn't fully solve the problem" relative to Option
#' A's BLAST-based comparison; live testing found it's not optional at all,
#' it's a REQUIRED companion to Option A, since Option A's BLAST search
#' (however it's scoped) still needs candidate accessions that are even
#' plausibly the same gene region to begin with.
#' @param species Character scalar, full species binomial (or any organism
#'   name NCBI's own `[Organism]` field search accepts).
#' @param exclude Character vector of accessions to exclude from the result
#'   (version-suffix-stripped comparison) -- typically the accession being
#'   investigated itself.
#' @param max_records Integer. Caps how many accessions are returned --
#'   this function is for a small, deliberate deep-dive, not exhaustive
#'   reference-database compilation.
#' @param reference_length Numeric or `NULL` (default). The flagged
#'   accession's own sequence length (bp) -- when supplied, candidates whose
#'   `slen` falls outside `[reference_length / max_length_ratio,
#'   reference_length * max_length_ratio]` are discarded before
#'   `max_records` truncation, and the underlying NCBI search casts a much
#'   wider net (`retmax`) to compensate for the (potentially large) fraction
#'   of `[Organism]`-search hits this pre-filter will discard. `NULL`
#'   disables the filter entirely (not recommended for real use -- see
#'   `@section Length-ratio pre-filter` above).
#' @param max_length_ratio Numeric (default `3`). See `reference_length`.
#'   A tentative, not empirically-tuned starting point (the reentry prompt's
#'   own "2-3x?" suggestion) -- may need recalibration against more real
#'   cases.
#' @return Character vector of accessions (possibly empty; never `NA`).
#' @noRd
.search_species_accessions <- function(species, exclude = character(0L),
                                       max_records = 30L, reference_length = NULL,
                                       max_length_ratio = 3, ncbi_api_key = NULL,
                                       verbose = TRUE) {
  .check_pkg("rentrez")
  if (is.null(species) || is.na(species) || !nzchar(trimws(species))) {
    return(character(0L))
  }
  if (!is.null(ncbi_api_key) && nzchar(ncbi_api_key)) {
    rentrez::set_entrez_key(ncbi_api_key)
  }

  # Length restriction happens SERVER-SIDE via NCBI's own `[SLEN]` Entrez
  # query field, not by fetching a wide net and filtering client-side.
  # Found necessary live (2026-08-08): client-side widening (fetch up to
  # 500 `[Organism]`-search results, then filter by ESummary's `slen`)
  # returned ZERO usable candidates for `Cyprinus carpio` -- a species with
  # 67,744 total nuccore records, whose first 500 by NCBI's default sort
  # order apparently contain no length-comparable sequence at all.
  # `AND lo:hi[SLEN]` restricts the SEARCH ITSELF, independent of how many
  # total records the species has -- confirmed live: the identical query
  # correctly surfaces real, length-comparable records for BOTH species
  # (six genuine "12S rRNA" 177bp records for `Pseudorasbora parva`; COX1/
  # ribosomal-RNA-gene records for `Cyprinus carpio`).
  has_ref_len <- .valid_reference_length(reference_length)
  term <- sprintf('"%s"[Organism]', species)
  if (has_ref_len) {
    lo <- max(1, floor(reference_length / max_length_ratio))
    hi <- ceiling(reference_length * max_length_ratio)
    term <- sprintf("%s AND %d:%d[SLEN]", term, lo, hi)
  }

  found <- tryCatch(
    {
      rentrez::entrez_search(
        db = "nuccore", term = term, retmax = max_records + length(exclude) + 5L
      )
    },
    error = function(e) {
      if (verbose) {
        warning(sprintf(
          "Species search failed for '%s': %s", species,
          conditionMessage(e)
        ), call. = FALSE)
      }
      NULL
    }
  )
  if (is.null(found) || length(found$ids) == 0L) {
    return(character(0L))
  }

  # entrez_summary() is still batched defensively (a real HTTP 414 "request
  # too large" was hit live with 500 unbatched IDs during this fix's own
  # development, before the server-side SLEN restriction above made a wide
  # `retmax` unnecessary) -- the same 100-per-batch convention already used
  # elsewhere in this file (`.fetch_reference_accession_records()`).
  id_batches <- split(found$ids, ceiling(seq_along(found$ids) / 100L))
  summaries <- list()
  for (batch in id_batches) {
    batch_summaries <- tryCatch(
      rentrez::entrez_summary(db = "nuccore", id = batch),
      error = function(e) {
        if (verbose) {
          warning(sprintf(
            "ESummary batch fetch failed for '%s' (%d of %d IDs): %s",
            species, length(batch), length(found$ids), conditionMessage(e)
          ), call. = FALSE)
        }
        NULL
      }
    )
    if (is.null(batch_summaries)) next
    if (inherits(batch_summaries, "esummary")) batch_summaries <- list(batch_summaries)
    summaries <- c(summaries, batch_summaries)
  }
  if (length(summaries) == 0L) {
    return(character(0L))
  }

  accs <- vapply(summaries, function(s) s$caption %||% NA_character_, character(1L))
  lens <- vapply(summaries, function(s) {
    v <- suppressWarnings(as.numeric(s$slen %||% NA_real_))
    if (length(v) != 1L) NA_real_ else v
  }, numeric(1L))

  .filter_and_cap_accessions(accs, lens, exclude, max_records, reference_length, max_length_ratio)
}

#' Is `reference_length` a usable (non-`NULL`, positive, non-`NA` scalar) value?
#' @noRd
.valid_reference_length <- function(reference_length) {
  !is.null(reference_length) && is.numeric(reference_length) &&
    length(reference_length) == 1L && !is.na(reference_length) && reference_length > 0
}

#' Pure filtering/capping logic for `.search_species_accessions()`
#'
#' Extracted so the length-ratio pre-filter (see
#' `.search_species_accessions()`'s own `@section Length-ratio pre-filter`)
#' can be unit-tested directly against synthetic `accs`/`lens` vectors,
#' without mocking `rentrez::entrez_search()`/`entrez_summary()` (this
#' package's established testing convention mocks only its OWN internal
#' NCBI-fetch wrappers, never raw `rentrez` calls directly).
#'
#' @param accs Character vector of accession strings (may contain `NA`).
#' @param lens Numeric vector, same length as `accs` -- each accession's own
#'   sequence length (`NA` where unknown).
#' @param exclude Character vector of accessions to exclude
#'   (version-suffix-stripped comparison).
#' @param max_records Integer cap on the final returned vector.
#' @param reference_length,max_length_ratio See
#'   `.search_species_accessions()`. Length filtering is skipped entirely
#'   when `reference_length` is not a usable value (see
#'   `.valid_reference_length()`).
#' @return Character vector of accessions (possibly empty; never `NA`;
#'   never containing duplicates).
#' @noRd
.filter_and_cap_accessions <- function(accs, lens, exclude, max_records,
                                       reference_length, max_length_ratio) {
  strip_v <- function(x) sub("\\.[0-9]+$", "", x)
  exclude_stripped <- strip_v(exclude)

  keep <- !is.na(accs) & !strip_v(accs) %in% exclude_stripped

  if (.valid_reference_length(reference_length)) {
    lo <- reference_length / max_length_ratio
    hi <- reference_length * max_length_ratio
    keep <- keep & !is.na(lens) & lens >= lo & lens <= hi
  }

  accs <- accs[keep]
  unique(accs)[seq_len(min(max_records, length(unique(accs))))]
}

#' BLAST a flagged sequence against a specific comparison set of accessions
#'
#' Implements Option A of `ecosystem_docs/REENTRY_PROMPT_
#' investigate_flagged_accession_prefilter_group_posthoc.md` (Question 1):
#' replaces the original `pwalign::pairwiseAlignment(type = "local")`-based
#' comparison with `blast_sequences()`'s own underlying mechanism -- the
#' SAME family of evidence that originally made `MZ605481` a confirmed
#' `candidate_mislabel` in the first place (20 independent, coverage-safe
#' *Cyprinus carpio* hits at genuine 100% identity). The real
#' coverage-blindness bug the pairwise-alignment path had (a short query
#' vs. a much longer reference, e.g. a full mitogenome, can find a tiny
#' spuriously-perfect local-alignment fragment) is exactly what BLAST's
#' own `query_coverage` already guards against by construction.
#'
#' @section A real, live-found correction to the original design (2026-08-08):
#' The FIRST version of this function was a post-hoc filter -- BLAST the
#' flagged sequence against the SAME unrestricted database
#' `investigate_flagged_accession()` itself searches, take the top
#' `max_hits` ranked hits, then keep only whichever happen to also be in
#' `comparison_meta$accession`. A live test against the real `MZ605481`
#' case found this returns ZERO matches on both sides even though 30 real
#' conspecific accessions were independently confirmed to exist -- the
#' comparison-set accessions (found via `.search_species_accessions()`'s
#' own, separate NCBI organism-name search) simply never appeared among
#' BLAST's own top-ranked hits for this query, an independent sample from
#' GenBank's full catalog with no guaranteed overlap. This is now fixed
#' via NCBI's `ENTREZ_QUERY` mechanism (`method = "remote"` only): the
#' BLAST search SPACE itself is restricted to exactly the comparison-set
#' accessions, so BLAST computes a real alignment against every one of
#' them directly, rather than hoping they surface unprompted in an
#' unrestricted top-N. `method = "local"` has no `ENTREZ_QUERY`-equivalent
#' restriction available via `rBLAST`, so it falls back to the original,
#' weaker post-hoc-filter approach -- flagged in its own roxygen as a real,
#' known limitation, not silently downgraded.
#'
#' @param flagged_seq Character scalar, the flagged accession's own sequence.
#' @param comparison_meta data.frame(accession, sequence, create_date) --
#'   typically `.fetch_reference_accession_records()`'s own output. Only
#'   `accession`/`create_date` are used here (BLAST needs no local sequence
#'   content for the comparison side); a `sequence` column, if present, is
#'   ignored.
#' @param method,database Passed through -- the SAME values
#'   `investigate_flagged_accession()`'s own re-BLAST step uses, so both
#'   comparisons search the identical database.
#' @param min_coverage Numeric (default `0.5`). Rows below this
#'   BLAST-computed query-coverage floor are retained in the output (never
#'   silently dropped) but marked `meets_min_coverage = FALSE`.
#' @param ncbi_api_key,verbose As in [investigate_flagged_accession()].
#' @return data.frame(accession, pident, coverage, meets_min_coverage,
#'   create_date), ordered with coverage-clearing rows first (by `pident`
#'   descending within each group). One row per `comparison_meta` accession
#'   BLAST actually returned an alignment for; an accession with no
#'   detectable similarity at all is honestly absent (not a row of `NA`s).
#' @noRd
.blast_against_comparison_set <- function(flagged_seq, comparison_meta,
                                          method = "remote", database = "nt",
                                          min_coverage = 0.5,
                                          ncbi_api_key = NULL, verbose = TRUE) {
  empty <- data.frame(
    accession = character(0L), pident = numeric(0L),
    coverage = numeric(0L), meets_min_coverage = logical(0L),
    create_date = character(0L), stringsAsFactors = FALSE
  )
  if (nrow(comparison_meta) == 0L) {
    return(empty)
  }

  strip_v <- function(x) sub("\\.[0-9]+$", "", x)
  comp_join <- strip_v(comparison_meta$accession)
  seq_df <- data.frame(
    asv_id = "flagged_query", sequence = flagged_seq,
    stringsAsFactors = FALSE
  )

  if (identical(method, "remote")) {
    entrez_query <- paste(sprintf("%s[ACCN]", comparison_meta$accession), collapse = " OR ")
    raw <- tryCatch(
      .blast_remote(
        seq_df,
        database = database, program = "blastn", megablast = FALSE,
        max_target_seqs = max(200L, nrow(comparison_meta) * 3L), batch_size = 1L,
        email = NULL, ncbi_api_key = ncbi_api_key, verbose = FALSE,
        entrez_query = entrez_query
      ),
      error = function(e) {
        if (verbose) {
          warning(sprintf(
            "Restricted BLAST comparison-set search failed: %s", conditionMessage(e)
          ), call. = FALSE)
        }
        NULL
      }
    )
    if (is.null(raw) || nrow(raw) == 0L) {
      return(empty)
    }
    hits <- data.frame(
      .join_acc = strip_v(raw$sacc), pident = raw$pident,
      query_coverage = raw$qcovs, stringsAsFactors = FALSE
    )
  } else {
    # No ENTREZ_QUERY-equivalent search-space restriction exists for a
    # local BLAST+ database via rBLAST -- fall back to the original
    # post-hoc filter (unrestricted search, then keep only hits whose
    # accession is in the comparison set). Weaker than the remote path
    # above: only finds a comparison accession if it also ranks among
    # BLAST's own top max_hits hits for this query.
    raw <- tryCatch(
      blast_sequences(
        seq_df,
        method = method, database = database,
        score_range = 100, min_score = 0, min_query_coverage = 0,
        max_hits = max(100L, nrow(comparison_meta) * 3L),
        max_target_seqs = max(200L, nrow(comparison_meta) * 5L),
        resolve_taxonomy = FALSE,
        ncbi_api_key = ncbi_api_key, verbose = FALSE
      ),
      error = function(e) {
        if (verbose) {
          warning(sprintf(
            "BLAST comparison-set search failed: %s", conditionMessage(e)
          ), call. = FALSE)
        }
        NULL
      }
    )
    if (is.null(raw) || !is.data.frame(raw) || nrow(raw) == 0L) {
      return(empty)
    }
    hits <- data.frame(
      .join_acc = strip_v(raw$accession), pident = raw$score,
      query_coverage = raw$query_coverage, stringsAsFactors = FALSE
    )
  }

  hits <- hits[hits$.join_acc %in% comp_join, , drop = FALSE]
  if (nrow(hits) == 0L) {
    return(empty)
  }

  # A comparison accession could in principle surface via more than one HSP/
  # hit -- keep only its own best (highest pident) row, matching this
  # function's one-row-per-comparison-accession contract.
  hits <- hits[order(-hits$pident), , drop = FALSE]
  hits <- hits[!duplicated(hits$.join_acc), , drop = FALSE]

  m <- match(hits$.join_acc, comp_join)
  out <- data.frame(
    accession = comparison_meta$accession[m],
    pident = hits$pident,
    coverage = ifelse(is.na(hits$query_coverage), NA_real_, hits$query_coverage / 100),
    create_date = comparison_meta$create_date[m],
    stringsAsFactors = FALSE
  )
  out$meets_min_coverage <- !is.na(out$coverage) & out$coverage >= min_coverage
  out[order(-out$meets_min_coverage, -out$pident), , drop = FALSE]
}

#' Fetch (or reuse a shared-batch cache of) comparison accessions for a species
#'
#' Implements Question 3, item 2 of the reentry prompt: shares
#' `.search_species_accessions()`/`.fetch_reference_accession_records()`
#' results across accessions in one `investigate_flagged_accessions()` batch
#' that share the same `listed_species` -- or, less obviously, the same
#' `disagreeing_taxon` -- so a species-level accession list is fetched from
#' NCBI at most ONCE per species per batch, not once per flagged accession.
#' A single-accession call (`shared_cache = NULL`) behaves exactly as
#' before: one fresh fetch, no memoization.
#'
#' The underlying species-level fetch is deliberately NOT exclusion-aware
#' (it fetches up to `max_related + 5L` candidates with no `exclude`), since
#' the correct exclusion set (the CURRENT flagged accession's own accession)
#' differs per caller even when the species is shared -- exclusion and the
#' `max_related` truncation both happen after the (possibly cached) fetch,
#' cheaply, on the already-in-memory result.
#'
#' @section Cache key includes `reference_length` (2026-08-08):
#' Live testing (see `.search_species_accessions()`'s own `@section
#' Length-ratio pre-filter`) found the length-ratio pre-filter is required
#' for correctness, not optional -- but that filter depends on the CALLING
#' accession's own sequence length, which differs per flagged accession even
#' when `species` is shared. The batch-sharing cache is therefore keyed on
#' `(species, reference_length)`, not `species` alone -- two flagged
#' accessions of the same species only share one NCBI fetch if their
#' sequences are also (exactly) the same length. This is a real, honest
#' narrowing of the sharing benefit `investigate_flagged_accessions()`
#' otherwise advertises (Question 3, item 2) in exchange for correctness --
#' documented here rather than silently accepted.
#'
#' @param species Character scalar.
#' @param exclude_accession Character scalar. Excluded from the returned set
#'   (version-suffix-stripped comparison) -- typically the flagged accession
#'   currently being investigated.
#' @param max_related Integer. Final cap on rows returned, applied AFTER
#'   exclusion.
#' @param reference_length,max_length_ratio Passed to
#'   `.search_species_accessions()` -- see that function's own
#'   documentation.
#' @param shared_cache Environment or `NULL`. When supplied, must have a
#'   `$species_meta` list slot (a named list, cache key -> fetched
#'   data.frame) -- read from and written to across calls sharing the same
#'   environment. `NULL` (default) disables sharing entirely.
#' @param ncbi_api_key,verbose As in [investigate_flagged_accession()].
#' @return data.frame(accession, sequence, organism, create_date) -- same
#'   shape as `.fetch_reference_accession_records()`'s own output.
#' @noRd
.get_species_comparison_meta <- function(species, exclude_accession, max_related,
                                         reference_length = NULL, max_length_ratio = 3,
                                         ncbi_api_key, verbose, shared_cache = NULL) {
  strip_v <- function(x) sub("\\.[0-9]+$", "", x)
  cache_key <- paste(species, reference_length %||% "NA", sep = "||")

  cached <- if (!is.null(shared_cache)) shared_cache$species_meta[[cache_key]] else NULL

  if (is.null(cached)) {
    ids <- .search_species_accessions(
      species,
      exclude = character(0L), max_records = max_related + 5L,
      reference_length = reference_length, max_length_ratio = max_length_ratio,
      ncbi_api_key = ncbi_api_key, verbose = verbose
    )
    cached <- if (length(ids) > 0L) {
      .fetch_reference_accession_records(
        ids,
        want_sequence = TRUE, ncbi_api_key = ncbi_api_key, verbose = verbose
      )
    } else {
      data.frame(
        accession = character(0L), sequence = character(0L),
        organism = character(0L), create_date = character(0L),
        stringsAsFactors = FALSE
      )
    }
    if (!is.null(shared_cache)) shared_cache$species_meta[[cache_key]] <- cached
  } else if (verbose) {
    message(sprintf(
      "Reusing %d NCBI accession(s) already fetched for '%s' earlier in this batch.",
      nrow(cached), species
    ))
  }

  out <- cached[strip_v(cached$accession) != strip_v(exclude_accession), , drop = FALSE]
  utils::head(out, max_related)
}

#' Build the one narrative summary shared by every printed investigation
#'
#' Extracted so a cache HIT (no recomputation) can print the identical
#' summary a fresh computation would have, without duplicating this logic.
#' Reports ONLY comparisons that cleared `min_coverage` in the headline
#' mean/range, and always states how many were excluded as
#' too-short-to-be-meaningful, rather than silently computing statistics
#' over spurious short-fragment matches.
#' @noRd
.print_investigation_summary <- function(result, min_coverage) {
  .summarize_comparison <- function(df, label) {
    n_total <- nrow(df)
    n_ok <- sum(df$meets_min_coverage)
    cat(sprintf(
      "   %d real accession(s) found; %d cleared the %.0f%% coverage floor.\n",
      n_total, n_ok, min_coverage * 100
    ))
    if (n_ok > 0L) {
      ok <- df[df$meets_min_coverage, , drop = FALSE]
      cat(sprintf(
        "   identity (coverage >= %.0f%% only): mean %.2f%%, range %.2f-%.2f%%\n",
        min_coverage * 100, mean(ok$pident), min(ok$pident), max(ok$pident)
      ))
    } else if (n_total > 0L) {
      cat(sprintf(
        "   No %s comparison reached %.0f%% coverage -- every alignment found was too\n",
        label, min_coverage * 100
      ))
      cat("   short relative to the query to be meaningful evidence either way (see\n")
      cat("   the full data frame's own `coverage` column for the actual values).\n")
    } else {
      cat("   (no real accessions found in NCBI to compare against)\n")
    }
  }

  cat("\n=================================================================\n")
  cat(sprintf("INVESTIGATION: %s (listed as %s)\n", result$accession, result$listed_species))
  cat("=================================================================\n\n")
  cat(sprintf("-- Self-consistency: other real '%s' accessions --\n", result$listed_species))
  .summarize_comparison(result$conspecific_comparison, "self-consistency")

  cat(sprintf(
    "\n-- Cross-taxon consistency: %s --\n",
    if (is.na(result$disagreeing_taxon)) "(none found)" else result$disagreeing_taxon
  ))
  .summarize_comparison(result$disagreeing_taxon_comparison, "cross-taxon")

  cat("\n(High cross-taxon identity + low/absent self-consistency, BOTH at\n")
  cat(" meaningful coverage, is the strongest evidence of a genuine mislabel.\n")
  cat(" High self-consistency alongside real cross-taxon similarity more likely\n")
  cat(" reflects thin coverage of RELATED taxa or a conserved marker region, not\n")
  cat(" a problem with this specific accession. If NEITHER comparison clears the\n")
  cat(" coverage floor, this function cannot support a conclusion either way --\n")
  cat(" that is a real, distinct outcome, not the same as 'no evidence found'.\n")
  cat(" See evaluate_reference_accessions()'s own @section Identity diagnostics.)\n")
  cat("=================================================================\n")
}

#' Core investigation logic, shared by the single- and batch-accession entry points
#'
#' Identical to what `investigate_flagged_accession()`'s body used to do
#' directly, extracted so `investigate_flagged_accessions()` (the batch
#' wrapper) can drive it with a shared `shared_cache` environment for
#' cross-accession NCBI-search reuse, and so both entry points can wrap it
#' with the identical persistent-cache read/write logic.
#' @noRd
.investigate_flagged_accession_core <- function(accession, species, max_related, method,
                                                database, score_range, min_score, max_hits,
                                                submission_window, min_coverage, ncbi_api_key,
                                                verbose, shared_cache = NULL,
                                                max_length_ratio = 3) {
  # ---- 1. The flagged accession's own record ---------------------------------
  own <- .fetch_reference_accession_records(accession,
    want_sequence = TRUE,
    ncbi_api_key = ncbi_api_key, verbose = verbose
  )
  if (nrow(own) == 0L || is.na(own$sequence) || !nzchar(own$sequence)) {
    stop(sprintf("Could not fetch a usable sequence for '%s' from NCBI.", accession),
      call. = FALSE
    )
  }
  if (is.null(species)) species <- own$organism
  if (is.na(species) || !nzchar(species)) {
    stop("No species could be determined for this accession -- pass `species` explicitly.",
      call. = FALSE
    )
  }
  if (verbose) message(sprintf("Investigating %s (listed species: %s)", accession, species))

  # Length-ratio pre-filter reference point -- see .search_species_
  # accessions()'s own @section Length-ratio pre-filter for why this is
  # required, not optional (found live 2026-08-08 against the real
  # MZ605481 case: a plain [Organism] search can be dominated by whole-
  # genome-assembly records tens of millions of bp long for a species with
  # a published reference genome).
  own_length <- nchar(own$sequence)

  # ---- 2. Self-consistency: other real accessions of the SAME species --------
  if (verbose) message(sprintf("Searching NCBI for other '%s' accessions...", species))
  conspecific_meta <- .get_species_comparison_meta(
    species,
    exclude_accession = accession, max_related = max_related,
    reference_length = own_length, max_length_ratio = max_length_ratio,
    ncbi_api_key = ncbi_api_key, verbose = verbose, shared_cache = shared_cache
  )
  if (verbose) {
    message(sprintf(
      "Found %d other real accession(s) of '%s'.",
      nrow(conspecific_meta), species
    ))
  }

  conspecific_comparison <- .blast_against_comparison_set(
    own$sequence, conspecific_meta,
    method = method, database = database,
    min_coverage = min_coverage, ncbi_api_key = ncbi_api_key, verbose = verbose
  )

  # ---- 3. Fresh re-BLAST to (re-)discover the top INDEPENDENT disagreeing
  # taxon, independence-filtered the same way evaluate_reference_
  # accessions() itself is -- the real lesson from PV382872: never trust
  # raw top hits without checking whether they're same-batch artifacts. ----
  if (verbose) message("Re-BLASTing to discover the top independent disagreeing taxon...")
  seq_df <- data.frame(asv_id = accession, sequence = own$sequence, stringsAsFactors = FALSE)
  hits <- blast_sequences(
    seq_df,
    method = method, database = database, score_range = score_range,
    min_score = min_score, max_hits = max_hits, resolve_taxonomy = TRUE,
    ncbi_api_key = ncbi_api_key, verbose = verbose
  )

  disagreeing_taxon <- NA_character_
  disagreeing_taxon_comparison <- data.frame(
    accession = character(0L), pident = numeric(0L), coverage = numeric(0L),
    meets_min_coverage = logical(0L), create_date = character(0L), stringsAsFactors = FALSE
  )

  if (is.data.frame(hits) && nrow(hits) > 0L) {
    strip_v <- function(x) sub("\\.[0-9]+$", "", x)
    hits <- hits[strip_v(hits$observation_id) != strip_v(hits$accession), , drop = FALSE]
  }

  if (is.data.frame(hits) && nrow(hits) > 0L) {
    hit_meta <- .fetch_reference_accession_records(
      unique(hits$accession),
      want_sequence = FALSE, ncbi_api_key = ncbi_api_key,
      verbose = verbose
    )
    own_lookup <- .build_submission_batch_lookup(
      data.frame(
        composite_id = accession, create_date = own$create_date,
        stringsAsFactors = FALSE
      )
    )
    hit_lookup <- .build_submission_batch_lookup(
      data.frame(
        composite_id = hit_meta$accession, create_date = hit_meta$create_date,
        stringsAsFactors = FALSE
      )
    )
    hits$is_independent <- vapply(hits$accession, function(a) {
      idx <- match(a, hit_lookup$composite_id)
      if (is.na(idx)) {
        return(TRUE)
      } # no create_date available -- can't prove same-batch
      !.same_submission_batch(
        own_lookup$acc_date, own_lookup$acc_prefix, own_lookup$acc_num,
        hit_lookup$acc_date[idx], hit_lookup$acc_prefix[idx], hit_lookup$acc_num[idx],
        submission_window
      )
    }, logical(1L))

    independent_hits <- hits[hits$is_independent, , drop = FALSE]
    if (nrow(independent_hits) > 0L) {
      independent_hits <- independent_hits[order(-independent_hits$score), , drop = FALSE]
      disagreeing_taxon <- independent_hits$species[1L]
      if (verbose) {
        message(sprintf(
          "Top independent disagreeing taxon: %s (%s, %.2f%% identity).",
          disagreeing_taxon, independent_hits$accession[1L], independent_hits$score[1L]
        ))
      }

      if (!is.na(disagreeing_taxon) && nzchar(disagreeing_taxon)) {
        disagreeing_meta <- .get_species_comparison_meta(
          disagreeing_taxon,
          exclude_accession = accession, max_related = max_related,
          reference_length = own_length, max_length_ratio = max_length_ratio,
          ncbi_api_key = ncbi_api_key, verbose = verbose, shared_cache = shared_cache
        )
        disagreeing_taxon_comparison <- .blast_against_comparison_set(
          own$sequence, disagreeing_meta,
          method = method, database = database,
          min_coverage = min_coverage, ncbi_api_key = ncbi_api_key, verbose = verbose
        )
      }
    } else if (verbose) {
      message(
        "No independent (non-same-submission-batch) BLAST hits found -- ",
        "every hit was excluded as a batch artifact, same lesson as PV382872."
      )
    }
  }

  list(
    accession = accession,
    listed_species = species,
    conspecific_comparison = conspecific_comparison,
    disagreeing_taxon = disagreeing_taxon,
    disagreeing_taxon_comparison = disagreeing_taxon_comparison
  )
}

#' Verdict class used to decide the persistent-cache TTL
#'
#' `"inconclusive_length_mismatch"` -- the real MZ605481 outcome: zero
#' comparisons on EITHER side cleared `min_coverage`, so the function could
#' not support a conclusion in either direction. This class expires and is
#' retried (new, shorter GenBank deposits for either species could
#' genuinely change the answer). Any other outcome (`"evaluated"`) is
#' cached indefinitely, matching `evaluate_reference_accessions()`'s own
#' asymmetric-TTL philosophy for a directly analogous reason.
#' @noRd
.investigate_verdict <- function(result) {
  ok_self <- sum(result$conspecific_comparison$meets_min_coverage, na.rm = TRUE)
  ok_cross <- sum(result$disagreeing_taxon_comparison$meets_min_coverage, na.rm = TRUE)
  if (ok_self == 0L && ok_cross == 0L) "inconclusive_length_mismatch" else "evaluated"
}

#' @noRd
.investigate_params_key <- function(max_related, method, database, score_range, min_score,
                                    max_hits, submission_window, min_coverage,
                                    max_length_ratio) {
  # Bump this any time internal computation logic changes without any
  # caller-visible parameter changing -- otherwise a cached row computed
  # under the OLD logic gets served as a "fresh" cache hit forever under an
  # unchanged params_key. Mirrors evaluate_reference_accessions()'s own
  # .EVAL_REF_ACC_VERSION convention. Bumped 2026-08-08 (v1 -> v2): a real
  # cache row computed under v1's logic could be a false
  # "inconclusive_length_mismatch" (the real MZ605481 bug -- see
  # .search_species_accessions()'s own @section Length-ratio pre-filter),
  # which v1's own asymmetric TTL would otherwise have kept serving as a
  # "fresh" cache hit for up to inconclusive_ttl_days.
  .INVESTIGATE_VERSION <- "v2_entrez_query_and_length_filter"
  paste(max_related, method, database, score_range, min_score, max_hits,
    submission_window, min_coverage, max_length_ratio, .INVESTIGATE_VERSION,
    sep = "|"
  )
}

#' Load the persistent per-(accession, species override) investigation cache
#' @noRd
.load_investigate_cache <- function(cache_dir) {
  empty <- data.frame(
    accession = character(0L), species_key = character(0L),
    verdict = character(0L), evaluated_at = as.POSIXct(character(0L)),
    params_key = character(0L), stringsAsFactors = FALSE
  )
  empty$result <- list()
  if (is.null(cache_dir)) {
    return(empty)
  }
  path <- file.path(cache_dir, "investigate_flagged_accession_cache.rds")
  if (!file.exists(path)) {
    return(empty)
  }
  cached <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(cached) || !is.data.frame(cached)) {
    return(empty)
  }

  # Same schema-mismatch defense as evaluate_reference_accessions()'s own
  # .load_reference_accession_cache() -- a cache file from an older package
  # version missing a column this version expects is discarded wholesale
  # rather than partially read.
  missing_cols <- setdiff(names(empty), names(cached))
  if (length(missing_cols) > 0L) {
    warning(sprintf(
      "investigate_flagged_accession(): cache at %s predates this package version (missing column(s): %s) -- starting a fresh cache.",
      path, paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
    return(empty)
  }
  cached
}

#' Persist the investigation cache
#' @noRd
.save_investigate_cache <- function(cache_dir, cache_df) {
  if (is.null(cache_dir)) {
    return(invisible(NULL))
  }
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  path <- file.path(cache_dir, "investigate_flagged_accession_cache.rds")
  saveRDS(cache_df, path)
  invisible(NULL)
}

#' Look up a single cached investigation result, applying the asymmetric TTL
#' @return A one-row data.frame (with `result` list-column), or `NULL` if no
#'   fresh cache entry exists.
#' @noRd
.lookup_investigate_cache <- function(cache, accession, species_key, params_key,
                                      inconclusive_ttl_days) {
  if (nrow(cache) == 0L) {
    return(NULL)
  }
  idx <- which(cache$accession == accession & cache$species_key == species_key &
    cache$params_key == params_key)
  if (length(idx) == 0L) {
    return(NULL)
  }
  row <- cache[idx[1L], , drop = FALSE]
  if (identical(row$verdict, "inconclusive_length_mismatch")) {
    age_days <- as.numeric(difftime(Sys.time(), row$evaluated_at, units = "days"))
    if (is.na(age_days) || age_days >= inconclusive_ttl_days) {
      return(NULL)
    }
  }
  row
}

#' Compute a verdict, write the result into the cache, and persist it
#' @return The updated in-memory `cache` data.frame (caller should keep
#'   threading this through subsequent calls in the same batch, rather than
#'   re-`.load_investigate_cache()`-ing from disk each time).
#' @noRd
.store_investigate_result <- function(cache_dir, cache, accession, species_key, params_key,
                                      result) {
  new_row <- data.frame(
    accession = accession, species_key = species_key,
    verdict = .investigate_verdict(result), evaluated_at = Sys.time(),
    params_key = params_key, stringsAsFactors = FALSE
  )
  new_row$result <- list(result)
  cache <- cache[!(cache$accession == accession & cache$species_key == species_key &
    cache$params_key == params_key), , drop = FALSE]
  cache <- rbind(cache, new_row[, names(cache), drop = FALSE])
  .save_investigate_cache(cache_dir, cache)
  cache
}

#' Deep-Dive Verification for a Single Flagged Reference Accession
#'
#' For ONE accession `evaluate_reference_accessions()` flagged (typically
#' `"incongruent"`), runs two targeted, more expensive comparisons than that
#' broad-scan function ever attempts -- deliberately meant to run only on
#' the small subset a caller has already decided is worth a closer look,
#' not at production scale.
#'
#' @section Why this exists (2026-08-07):
#' Manually reviewing `evaluate_reference_accessions()`'s real flagged
#' accessions by hand found that the raw top BLAST hits alone can be
#' actively misleading -- `PV382872`'s top hits (an eel, a catfish, a
#' parasitic isopod, all ~99.5% identity) looked like severe contamination
#' until direct verification showed every one was from the SAME real
#' submission batch as the query itself, correctly already excluded by
#' `evaluate_reference_accessions()`'s own independence filter, but
#' invisible without re-fetching the raw GenBank records by hand. This
#' function automates that verification step, applying the SAME
#' independence-filter logic (`.build_submission_batch_lookup()`/
#' `.same_submission_batch()`) so a caller doesn't have to re-derive it by
#' hand every time.
#'
#' @section The two comparisons:
#' \describe{
#'   \item{Self-consistency}{How well does the flagged accession match
#'     OTHER real GenBank accessions of its own listed species (searched
#'     directly by species name, not discovered via `blast_sequences()`'s
#'     own `score_range`/`max_hits` window, which can miss real conspecifics
#'     sitting just outside it)? High identity here is reassuring; low
#'     identity is a much stronger warning sign than
#'     `evaluate_reference_accessions()` alone can report, since it means
#'     the accession doesn't even resemble other deposits of its own
#'     claimed species.}
#'   \item{Cross-taxon consistency}{How well does the flagged accession
#'     match other real accessions of whichever taxon its top INDEPENDENT
#'     disagreeing BLAST hit belongs to (freshly re-discovered via a live
#'     BLAST call, independence-filtered the same way)? High identity here
#'     paired with low self-consistency above is the strongest evidence
#'     this function can produce for a genuine mislabel -- e.g. the real
#'     `MZ605481` case (self-consistency not yet checked at the time of
#'     writing; cross-taxon consistency to `Cyprinus carpio` was confirmed
#'     by hand at 100% identity across 20 independent real accessions).}
#' }
#'
#' @section Both comparisons now run via BLAST, not pairwise alignment (2026-08-08):
#' `MZ605481`'s own real motivating case came back inconclusive in BOTH
#' directions the first time this function shipped: 0 of 30+ candidate
#' accessions found via NCBI species search cleared a 50% coverage floor on
#' either side, because NCBI's `[Organism]`-based search returns records of
#' ANY length (most real GenBank deposits for both *Pseudorasbora parva*
#' and *Cyprinus carpio* are full ~16kb mitogenomes, against which a 173bp
#' amplicon can only ever find a small, non-meaningful local-alignment
#' fragment). The ORIGINAL evidence that made `MZ605481` a real
#' `candidate_mislabel` in the first place was never a pairwise alignment
#' at all -- it was a direct [blast_sequences()] call, which already
#' enforces `min_query_coverage` internally and found 20 independent,
#' coverage-safe *Cyprinus carpio* hits at genuine 100% identity. Both
#' comparisons here now reuse that proven mechanism (`.blast_against_
#' comparison_set()`, internal) instead of a hand-rolled
#' `pwalign::pairwiseAlignment()` loop -- see
#' `ecosystem_docs/REENTRY_PROMPT_investigate_flagged_accession_prefilter_group_posthoc.md`,
#' Question 1, Option A.
#'
#' @section Two more rounds of live testing found Option A alone still wasn't enough (2026-08-08, same day):
#' The FIRST shipped version of `.blast_against_comparison_set()` was a
#' post-hoc filter (unrestricted BLAST, then keep only hits that happen to
#' match the comparison set) -- live-tested against the real `MZ605481`
#' case and found to return ZERO matches on both sides, even though 30 real
#' conspecific accessions were independently confirmed to exist. Fixed by
#' switching to NCBI's `ENTREZ_QUERY` mechanism (`method = "remote"`),
#' which restricts the BLAST search SPACE itself to the comparison-set
#' accessions -- verified in isolation against one known-good accession
#' (`OP739039`, 100% identity/coverage recovered correctly). Re-running the
#' full `MZ605481` case with THAT fix still returned zero matches -- direct
#' inspection of the real candidate accessions (`.search_species_
#' accessions("Pseudorasbora parva")`'s own output) found the root cause
#' was one level further upstream than expected: 26 of 30 candidates were
#' whole-chromosome shotgun-assembly records 60-80+ million bp long
#' (`Pseudorasbora parva` has a published reference genome), and the one
#' real short candidate that DID have usable sequence content was an
#' entirely different gene (`COI`, not `12S`) -- neither BLAST restriction
#' mechanism can find a meaningful alignment against a candidate that
#' either isn't practically alignable at that scale or covers a
#' non-overlapping genomic region entirely. This is exactly the reentry
#' prompt's own originally-deferred "Option B" (length-ratio candidate
#' pre-filtering) -- deferred at design time as "cheaper but doesn't fully
#' solve the problem," now confirmed live to be a REQUIRED companion to
#' Option A, not an alternative to it. Implemented in
#' `.search_species_accessions()` (new `reference_length`/
#' `max_length_ratio` params, using NCBI's already-batched, free `slen`
#' ESummary field to filter BEFORE ever fetching full sequence content --
#' fetching a 70-million-bp record's full `GBSeq_sequence` is exactly what
#' was silently failing/returning `NA` for those chromosome accessions).
#'
#' @section Caching (2026-08-08):
#' Implements Question 3, item 1: a persistent, cross-call cache keyed on
#' `(accession, species override)`, mirroring
#' `evaluate_reference_accessions()`'s own asymmetric-TTL philosophy. A
#' result where NEITHER comparison cleared `min_coverage` on either side
#' (the real `MZ605481`-class `"inconclusive_length_mismatch"` outcome)
#' expires after `inconclusive_ttl_days` and is retried on the next call --
#' new, shorter GenBank deposits for either species could genuinely change
#' that answer. Any other result is cached indefinitely (a confident
#' self/cross-taxon comparison doesn't change once computed). A cache HIT
#' still prints the identical narrative summary a fresh call would (unless
#' `verbose = FALSE`), so this is safe to call repeatedly without losing the
#' printed output. Set `cache_dir = NULL` to disable caching entirely.
#'
#' @param accession Character scalar. The flagged accession to investigate.
#' @param species Character or `NULL` (default). The accession's own listed
#'   species -- if `NULL`, fetched from its real GenBank record.
#' @param max_related Integer (default `30L`). Caps how many conspecific/
#'   disagreeing-taxon accessions are fetched and compared against, for each
#'   of the two comparisons -- a deliberate bound, not exhaustive
#'   reference-database compilation (see [TaxaLikely::fetch_ncbi_reference_sequences()]
#'   for that).
#' @param method,database Passed to BOTH the disagreeing-taxon re-BLAST AND
#'   the two `.blast_against_comparison_set()` comparisons (self-consistency,
#'   cross-taxon) -- see [blast_sequences()].
#' @param score_range,min_score,max_hits Passed only to the disagreeing-taxon
#'   re-BLAST -- see [blast_sequences()]. The two comparison-set BLAST calls
#'   use their own internal, deliberately permissive values (see
#'   `.blast_against_comparison_set()`), since they exist to honestly report
#'   every comparison-set accession's real identity/coverage, not to apply a
#'   score-window cutoff.
#' @param submission_window Integer (default `5L`). Same-submission-batch
#'   independence-filter window, matching
#'   [evaluate_reference_accessions()]'s own default.
#' @param min_coverage Numeric (default `0.5`). Passed to
#'   `.blast_against_comparison_set()` -- see that function's own
#'   documentation. Comparisons below this floor are retained in the output
#'   (never silently dropped) but excluded from the printed headline
#'   mean/range.
#' @param max_length_ratio Numeric (default `3`). Passed to
#'   `.search_species_accessions()` -- REQUIRED for correctness, not an
#'   optional tuning knob (see that function's own `@section Length-ratio
#'   pre-filter`, added 2026-08-08 after live testing against the real
#'   `MZ605481` case found a plain NCBI organism-name search can be
#'   dominated by whole-genome-assembly records for a species with a
#'   published reference genome, leaving almost no length-comparable
#'   candidates in the raw result at all).
#' @param cache_dir Character or `NULL`. Default
#'   `tools::R_user_dir("TaxaMatch", "cache")`. Set `NULL` to disable
#'   caching entirely (every call re-investigates from scratch). See
#'   `@section Caching` above.
#' @param inconclusive_ttl_days Numeric (default `30`). See `@section
#'   Caching` above.
#' @param ncbi_api_key,verbose As in [evaluate_reference_accessions()].
#'
#' @return A list:
#'   \describe{
#'     \item{`accession`, `listed_species`}{As given/discovered.}
#'     \item{`conspecific_comparison`}{data.frame(accession, pident,
#'       coverage, meets_min_coverage, create_date) -- one row per real
#'       conspecific accession BLAST actually returned a hit for. ALWAYS
#'       check `coverage`/`meets_min_coverage` before trusting `pident` --
#'       a high `pident` at low coverage is not meaningful evidence of
#'       anything, see `min_coverage` above.}
#'     \item{`disagreeing_taxon`}{The species name of the top independent
#'       disagreeing BLAST hit, or `NA` if none found.}
#'     \item{`disagreeing_taxon_comparison`}{Same shape as
#'       `conspecific_comparison`, for `disagreeing_taxon`'s own other
#'       accessions.}
#'   }
#'   Also prints a narrative summary comparing the two, unless `verbose = FALSE`.
#'
#' @seealso [evaluate_reference_accessions()], [investigate_flagged_accessions()]
#'
#' @export
investigate_flagged_accession <- function(accession,
                                          species = NULL,
                                          max_related = 30L,
                                          method = c("remote", "local"),
                                          database = "nt",
                                          score_range = 8,
                                          min_score = 70,
                                          max_hits = 20L,
                                          submission_window = 5L,
                                          min_coverage = 0.5,
                                          max_length_ratio = 3,
                                          cache_dir = tools::R_user_dir("TaxaMatch", "cache"),
                                          inconclusive_ttl_days = 30,
                                          ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""),
                                          verbose = TRUE) {
  if (!is.character(accession) || length(accession) != 1L || is.na(accession) ||
    !nzchar(accession)) {
    stop("accession must be a single non-NA, non-blank character string.", call. = FALSE)
  }
  method <- match.arg(method)

  params_key <- .investigate_params_key(
    max_related, method, database, score_range,
    min_score, max_hits, submission_window, min_coverage,
    max_length_ratio
  )
  species_key <- if (is.null(species)) "" else species

  cache <- .load_investigate_cache(cache_dir)
  cache_row <- .lookup_investigate_cache(
    cache, accession, species_key, params_key,
    inconclusive_ttl_days
  )

  if (!is.null(cache_row)) {
    result <- cache_row$result[[1L]]
    if (verbose) {
      message(sprintf(
        "investigate_flagged_accession(): using cached result for %s (evaluated %s; verdict: %s).",
        accession, format(cache_row$evaluated_at), cache_row$verdict
      ))
      .print_investigation_summary(result, min_coverage)
    }
    return(result)
  }

  result <- .investigate_flagged_accession_core(
    accession, species, max_related, method, database, score_range, min_score, max_hits,
    submission_window, min_coverage, ncbi_api_key, verbose,
    shared_cache = NULL,
    max_length_ratio = max_length_ratio
  )

  if (verbose) .print_investigation_summary(result, min_coverage)

  .store_investigate_result(cache_dir, cache, accession, species_key, params_key, result)

  result
}

#' Deep-Dive Verification for a Batch of Flagged Reference Accessions
#'
#' The natural `investigate_flagged_accessions()` (plural) batch wrapper
#' [investigate_flagged_accession()]'s own docs point at (Question 3, item
#' 2): runs the identical per-accession investigation over a whole list,
#' but shares a single in-memory NCBI-search lookup across the batch (so a
#' `listed_species` or `disagreeing_taxon` repeated across several
#' independently-flagged accessions is only fetched from NCBI once, not once
#' per accession) and shares the same persistent cache
#' [investigate_flagged_accession()] itself uses -- calling this after
#' already having called [investigate_flagged_accession()] on some of the
#' same accessions (or vice versa) correctly reuses those cached results.
#'
#' @section Not the same as cluster-level mislabel detection:
#' This function shares WORK across a batch (search results, cache entries)
#' -- it does not look for cross-accession PATTERNS (e.g. several
#' independently-flagged accessions all disagreeing toward the same
#' species). That is a separate, higher-value, not-yet-designed idea (see
#' the reentry prompt's Question 3, item 3) -- deliberately out of scope
#' here.
#'
#' @param accessions Character vector of flagged accessions to investigate.
#'   Not deduplicated automatically (each is looked up in the persistent
#'   cache independently, so a duplicate is cheap -- a cache hit after the
#'   first occurrence -- rather than an error).
#' @param species Character vector the same length as `accessions`, or
#'   `NULL` (default, every accession's species is fetched from its own
#'   GenBank record). A single accession's own override may be `NA` to
#'   fall back to fetching that one accession's species while other
#'   elements stay overridden.
#' @param max_related,method,database,score_range,min_score,max_hits,submission_window,min_coverage,max_length_ratio,cache_dir,inconclusive_ttl_days,ncbi_api_key,verbose
#'   As in [investigate_flagged_accession()] -- applied uniformly across the
#'   whole batch (not per-accession).
#'
#' @return A named list (names = `accessions`), one element per accession,
#'   each in the same shape [investigate_flagged_accession()] returns.
#'
#' @seealso [investigate_flagged_accession()], [evaluate_reference_accessions()]
#'
#' @export
investigate_flagged_accessions <- function(accessions,
                                           species = NULL,
                                           max_related = 30L,
                                           method = c("remote", "local"),
                                           database = "nt",
                                           score_range = 8,
                                           min_score = 70,
                                           max_hits = 20L,
                                           submission_window = 5L,
                                           min_coverage = 0.5,
                                           max_length_ratio = 3,
                                           cache_dir = tools::R_user_dir("TaxaMatch", "cache"),
                                           inconclusive_ttl_days = 30,
                                           ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""),
                                           verbose = TRUE) {
  if (!is.character(accessions) || length(accessions) == 0L) {
    stop("accessions must be a non-empty character vector.", call. = FALSE)
  }
  if (any(is.na(accessions) | !nzchar(accessions))) {
    stop("accessions must contain no NA or blank values.", call. = FALSE)
  }
  if (!is.null(species) && length(species) != length(accessions)) {
    stop("species, if supplied, must be the same length as accessions.", call. = FALSE)
  }
  method <- match.arg(method)

  params_key <- .investigate_params_key(
    max_related, method, database, score_range,
    min_score, max_hits, submission_window, min_coverage,
    max_length_ratio
  )

  cache <- .load_investigate_cache(cache_dir)
  shared_cache <- new.env(parent = emptyenv())
  shared_cache$species_meta <- list()

  results <- vector("list", length(accessions))

  for (i in seq_along(accessions)) {
    acc <- accessions[i]
    sp <- if (is.null(species)) NULL else (if (is.na(species[i])) NULL else species[i])
    species_key <- if (is.null(sp)) "" else sp

    cache_row <- .lookup_investigate_cache(
      cache, acc, species_key, params_key,
      inconclusive_ttl_days
    )
    if (!is.null(cache_row)) {
      if (verbose) {
        message(sprintf(
          "investigate_flagged_accessions(): [%d/%d] %s -- using cached result (evaluated %s; verdict: %s).",
          i, length(accessions), acc, format(cache_row$evaluated_at), cache_row$verdict
        ))
        .print_investigation_summary(cache_row$result[[1L]], min_coverage)
      }
      results[[i]] <- cache_row$result[[1L]]
      next
    }

    if (verbose) {
      message(sprintf("investigate_flagged_accessions(): [%d/%d] %s", i, length(accessions), acc))
    }

    res <- .investigate_flagged_accession_core(
      acc, sp, max_related, method, database, score_range, min_score, max_hits,
      submission_window, min_coverage, ncbi_api_key, verbose,
      shared_cache = shared_cache,
      max_length_ratio = max_length_ratio
    )
    if (verbose) .print_investigation_summary(res, min_coverage)

    cache <- .store_investigate_result(cache_dir, cache, acc, species_key, params_key, res)
    results[[i]] <- res
  }

  names(results) <- accessions
  results
}

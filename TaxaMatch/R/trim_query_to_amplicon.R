#' Extract the amplicon from one sequence via primer matching, trying both strands
#'
#' Duplicated (algorithm unchanged) from
#' `TaxaLikely::.extract_amplicon_one()` (`TaxaLikely/R/trim_to_amplicon.R`)
#' -- TaxaMatch must not depend on TaxaLikely (the ecosystem's documented
#' dependency direction is TaxaMatch -> TaxaLikely, never the reverse), so
#' this ~50-line helper is duplicated rather than reached for via `:::`.
#' Mirrors the existing precedent between these exact two packages
#' (`.parse_lat_lon()`, `.build_submission_batch_lookup()`/
#' `.same_submission_batch()`).
#'
#' Added 2026-08-09 for `evaluate_reference_accessions(barcode_term =)`:
#' BLASTing a full-length over-length reference (e.g. a complete
#' mitogenome, ~16.5kb) against `nt` is dramatically more CPU-expensive
#' than BLASTing its short barcode region -- found to be the real root
#' cause of a live NCBI server-side CPU-budget rejection on a real,
#' large (1,183-accession) run, several of whose queries were full
#' mitogenomes (see `.blast_server_rejected()`'s own documentation for the
#' real captured case). Trimming to the relevant amplicon before
#' submission answers the identical taxonomic-congruence question this
#' function exists to evaluate -- the accession's own species-identity
#' signal lives in the short barcode region, not the rest of the genome --
#' at a small fraction of the BLAST cost.
#'
#' @param seq_char Character scalar, one DNA sequence.
#' @param fwd_pattern Character scalar, forward primer, 5'-3'.
#' @param rev_pattern_rc Character scalar, reverse-complement of the reverse
#'   primer (i.e. the pattern to search for on the same strand as `fwd_pattern`).
#' @param fwd_max_mm,rev_max_mm Integer. Max mismatches allowed for each primer.
#' @param min_len,max_len Integer. Plausible amplicon length range; a match
#'   implying a span outside this range is rejected.
#' @return List with `sequence` (character or `NA`), `trimmed` (logical),
#'   `note` (character).
#' @noRd
.extract_amplicon_one_tm <- function(seq_char, fwd_pattern, rev_pattern_rc,
                                     fwd_max_mm, rev_max_mm, min_len, max_len) {

  if (is.na(seq_char) || !nzchar(seq_char))
    return(list(sequence = NA_character_, trimmed = FALSE, note = "missing_sequence"))

  seq_upper <- toupper(seq_char)
  if (!grepl("^[ACGTRYSWKMBDHVN]+$", seq_upper))
    return(list(sequence = NA_character_, trimmed = FALSE, note = "non_iupac_dna_skipped"))

  dna_plus <- tryCatch(Biostrings::DNAString(seq_upper), error = function(e) NULL)
  if (is.null(dna_plus))
    return(list(sequence = NA_character_, trimmed = FALSE, note = "invalid_dna_string"))
  dna_minus <- Biostrings::reverseComplement(dna_plus)

  for (strand in c("sense", "antisense")) {
    subj <- if (strand == "sense") dna_plus else dna_minus

    # fixed = "subject": the primer's own IUPAC ambiguity codes are
    # interpreted (a degenerate primer base matches any compatible sequence
    # base), while ambiguity codes already present in the *subject* sequence
    # (e.g. runs of N in a draft assembly) are treated literally rather than
    # matching every primer base for free -- confirmed empirically (see the
    # TaxaLikely original) that fixed = FALSE (both interpreted) produces
    # spurious matches across long N-runs.
    fwd_hits <- Biostrings::matchPattern(fwd_pattern, subj,
                                          max.mismatch = fwd_max_mm, fixed = "subject")
    if (length(fwd_hits) == 0L) next

    rev_hits <- Biostrings::matchPattern(rev_pattern_rc, subj,
                                          max.mismatch = rev_max_mm, fixed = "subject")
    if (length(rev_hits) == 0L) next

    fwd_start <- min(Biostrings::start(fwd_hits))
    fwd_end   <- min(Biostrings::end(fwd_hits)[Biostrings::start(fwd_hits) == fwd_start])

    rev_starts <- Biostrings::start(rev_hits)
    downstream <- rev_starts[rev_starts > fwd_end]
    if (length(downstream) == 0L) next
    rev_end <- Biostrings::end(rev_hits)[which(rev_starts == min(downstream))[1L]]

    # Defensive bounds guard before subseq(): fwd_start/rev_end are ordinarily
    # guaranteed within [1, length(subj)] by construction (both come from
    # matchPattern() hits on subj itself), but a malformed/edge-case match
    # (e.g. a primer hit degenerate enough to make matchPattern's own
    # start/end bookkeeping inconsistent) can still slip through -- found via
    # a real production crash where one bad accession's amplicon_width passed
    # the plausibility check above but Biostrings::subseq() then threw
    # "Invalid sequence coordinates", killing the entire in-flight BLAST
    # chunk (200 accessions) instead of just skipping the one bad sequence.
    # Treat an out-of-bounds/inverted span the same as "not found" rather
    # than letting subseq() error -- this strand's match is unusable either
    # way.
    seq_len <- length(subj)
    if (fwd_start < 1L || rev_end > seq_len || fwd_start > rev_end) next

    amplicon_width <- rev_end - fwd_start + 1L
    if (amplicon_width < min_len || amplicon_width > max_len) next

    amplicon <- Biostrings::subseq(subj, start = fwd_start, end = rev_end)
    return(list(
      sequence = as.character(amplicon),
      trimmed  = TRUE,
      note     = paste0("extracted_via_primer_match_", strand, "_strand")
    ))
  }

  list(sequence = NA_character_, trimmed = FALSE, note = "primers_not_found_or_implausible_span")
}

#' Trim over-length query sequences to their amplicon region before BLAST
#'
#' Vectorised wrapper around `.extract_amplicon_one_tm()` -- resolves
#' `barcode_term` to a primer pair (`TaxaTools::resolve_barcode_primers()`)
#' and a length range (`TaxaTools::resolve_barcode_lengths()`), trims only
#' sequences exceeding `max_len`, and leaves everything else (already
#' barcode-length sequences, and any over-length sequence whose primer
#' sites can't be found) untouched -- this function only ever shortens a
#' query, never discards or errors on one it can't trim.
#'
#' @param sequences Character vector of DNA sequences.
#' @param barcode_term Character. Passed to `TaxaTools::resolve_barcode_primers()`
#'   and `TaxaTools::resolve_barcode_lengths()`.
#' @param max_mismatch_rate Numeric in `[0, 1)`, default `0.15`.
#' @param verbose Logical, default `TRUE`.
#' @return Character vector, same length as `sequences` -- trimmed where
#'   possible, unchanged otherwise.
#' @noRd
.trim_queries_to_amplicon <- function(sequences, barcode_term,
                                      max_mismatch_rate = 0.15, verbose = TRUE) {
  if (!requireNamespace("Biostrings", quietly = TRUE))
    stop("Package 'Biostrings' is required for barcode_term trimming. ",
        "Install it with: BiocManager::install('Biostrings')", call. = FALSE)

  primer_info <- TaxaTools::resolve_barcode_primers(barcode_term)
  lens        <- TaxaTools::resolve_barcode_lengths(barcode_term)
  max_len     <- lens[["max_bp"]]
  min_len     <- lens[["min_bp"]]

  widths <- nchar(sequences)
  needs_trim <- !is.na(widths) & widths > max_len

  if (verbose)
    message(sprintf(
      "evaluate_reference_accessions(barcode_term = '%s'): %d of %d query sequence(s) exceed %d bp and will be checked for the amplicon region.",
      paste(barcode_term, collapse = "/"), sum(needs_trim), length(sequences), max_len
    ))

  if (!any(needs_trim)) return(sequences)

  rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(primer_info$rev)))
  fwd_max_mm <- floor(nchar(primer_info$fwd) * max_mismatch_rate)
  rev_max_mm <- floor(nchar(primer_info$rev) * max_mismatch_rate)

  # The plausibility check on a MATCHED span (forward-primer-start to
  # reverse-primer-end, i.e. INCLUDING both primers) must not reuse
  # min_len/max_len as-is -- those come from TaxaTools::resolve_barcode_lengths(),
  # a general marker-length window meant for filtering raw sequence widths, not
  # primer-to-primer span. `primer_info$amplicon_range` (from
  # TaxaTools::barcode_primer_defaults) is the literature-reported *variable
  # region* length, i.e. EXCLUDING primers (confirmed empirically 2026-08-10:
  # two real fish mitogenomes, both distinct species, both gave an identical
  # real full span of 221bp for MiFish-U -- primer_info$amplicon_range is
  # 163-185bp, 221bp minus the 48bp of primer length lands at 173bp, squarely
  # inside that range). Using min_len/max_len (130-210bp) directly rejected
  # every real, correctly-found MiFish-U hit as "implausible" (221 > 210) --
  # a systematic ~11bp miscalibration, not real primer absence, and the root
  # cause of a real 92/92 extraction failure this fix was built to close. Falls
  # back to min_len/max_len when a registered primer set has no amplicon_range.
  if (!is.null(primer_info$amplicon_range)) {
    primer_total_len <- nchar(primer_info$fwd) + nchar(primer_info$rev)
    span_min <- primer_info$amplicon_range[1] + primer_total_len
    span_max <- primer_info$amplicon_range[2] + primer_total_len
  } else {
    span_min <- min_len
    span_max <- max_len
  }

  out <- sequences
  n_trimmed <- 0L
  fail_notes <- character(0L)
  for (i in which(needs_trim)) {
    # tryCatch, not just the bounds guard inside .extract_amplicon_one_tm()
    # itself: a real production run crashed an entire 200-accession BLAST
    # chunk on one accession's coordinate math (IRanges "Invalid sequence
    # coordinates" from Biostrings::subseq()), with no per-accession
    # isolation -- this restores the guarantee this function's own roxygen
    # already documents ("this function only ever shortens a query, never
    # discards or errors on one it can't trim"): any unforeseen extraction
    # failure degrades to leaving that one sequence untrimmed, exactly like
    # a normal "primers not found" result, instead of aborting the caller.
    result <- tryCatch(
      .extract_amplicon_one_tm(
        seq_char = sequences[i], fwd_pattern = primer_info$fwd, rev_pattern_rc = rev_rc,
        fwd_max_mm = fwd_max_mm, rev_max_mm = rev_max_mm, min_len = span_min, max_len = span_max
      ),
      error = function(e) {
        list(sequence = NA_character_, trimmed = FALSE,
             note = paste0("extraction_error: ", conditionMessage(e)))
      }
    )
    if (result$trimmed) {
      out[i] <- result$sequence
      n_trimmed <- n_trimmed + 1L
    } else {
      fail_notes <- c(fail_notes, result$note)
    }
  }

  if (verbose) {
    message(sprintf(
      "evaluate_reference_accessions(): extracted the amplicon from %d of %d over-length query sequence(s); the rest are checked against the record's own annotated feature table next (barcode_term auto-trim), or BLASTed at full length otherwise.",
      n_trimmed, sum(needs_trim)
    ))
    # Surfaces WHY extraction failed for the rest -- "primers_not_found_or_
    # implausible_span" (real absence/mismatch of the primer sites, or a
    # too-long/short implied product) is a materially different situation
    # from "non_iupac_dna_skipped"/"invalid_dna_string" (a data-quality
    # problem upstream of this function, e.g. non-ACGT characters slipping
    # through), which .extract_amplicon_one_tm() already distinguishes via
    # its own `note` field but this wrapper previously discarded entirely --
    # a 0-of-N result gave no way to tell which case was happening.
    if (length(fail_notes) > 0L) {
      tally <- sort(table(fail_notes), decreasing = TRUE)
      message(sprintf(
        "  reason breakdown: %s",
        paste(sprintf("%s=%d", names(tally), as.integer(tally)), collapse = ", ")
      ))
    }
  }

  out
}

#' Bridge TaxaTools' marker-family barcode_term keys onto
#' check_marker_mismatch()'s own marker vocabulary
#'
#' `check_marker_mismatch()`'s `.resolve_marker_pattern()` (`R/
#' check_marker_mismatch.R`) already resolves a marker string like `"12S"`,
#' `"18S_2"`, or `"COI-Leray"` directly, via its own exact-match-then-
#' substring-match fallback against `.MARKER_ANNOTATION_PATTERNS`. A
#' MiFish/Teleo-style `barcode_term` (the primer SET name, e.g.
#' `"MiFishU"`) never contains the literal substring `"12S"` even though it
#' targets that exact marker, so it would otherwise fall through to that
#' function's own last-resort literal-string fallback and never match real
#' `"12S ribosomal RNA"` annotation text. This is a small, additive bridge
#' between two vocabularies that already exist elsewhere in this package
#' (`TaxaTools::barcode_length_defaults`'s own marker-family keys on one
#' side, `.MARKER_ANNOTATION_PATTERNS` on the other) -- it does NOT add a
#' new qualifier-matching regex of its own; every barcode_term not covered
#' here still reaches `.resolve_marker_pattern()`'s own existing fallback
#' unchanged.
#' @noRd
.MIFISH_STYLE_TO_MARKER <- c(mifish = "12S", teleo = "12S")

#' @noRd
.resolve_expected_marker <- function(barcode_term) {
  bt  <- barcode_term[1L]
  key <- tolower(trimws(bt))
  for (nm in names(.MIFISH_STYLE_TO_MARKER)) {
    if (startsWith(key, nm) || grepl(nm, key, fixed = TRUE))
      return(.MIFISH_STYLE_TO_MARKER[[nm]])
  }
  bt
}

#' Feature-table-guided extraction fallback for a query still over-length after primer trimming
#'
#' The second-line rescue for a query `.trim_queries_to_amplicon()` could
#' not shorten (no primer match, or an implausible matched span): before
#' submitting it to BLAST at full length, check the accession's OWN
#' annotated GBSeq feature table for a feature whose `/gene` or `/product`
#' qualifier matches the marker `barcode_term` implies, and extract that
#' feature's coordinate span (plus `margin` bp of context on each side, so
#' primer-adjacent flanking sequence -- useful for a later primer-based
#' re-trim attempt -- survives) instead of the whole record.
#'
#' Reuses `check_marker_mismatch()`'s own fetch/matching internals
#' (`.fetch_marker_annotation()`, `.resolve_marker_pattern()`,
#' `.MARKER_ANNOTATION_PATTERNS`) directly, per this feature's own design
#' doc -- no second fetcher, no new qualifier vocabulary. `.
#' fetch_marker_annotation()` batches its own `rentrez::entrez_fetch()`
#' call across every accession passed to it in one round trip (2026-08-08),
#' so calling it once per chunk here (never per-accession) keeps this
#' mechanism's real NCBI cost to one cheap `efetch`, nothing like BLAST.
#'
#' Extraction uses plain `substr()` on the already-fetched full nucleotide
#' string (GenBank feature coordinates are 1-based and inclusive, and index
#' directly into `GBSeq_sequence`) -- no `Biostrings` needed for this step.
#' Deliberately does NOT reverse-complement a feature on the minus strand:
#' `blast_sequences()` never sets an explicit strand (see that function's
#' own `megablast` documentation), so remote/local `blastn` already searches
#' both strands regardless of which orientation the extracted subsequence
#' happens to be in -- orientation therefore does not affect correctness
#' here, only, in principle, which strand a hit's alignment coordinates are
#' reported against (not consumed by anything in this package).
#'
#' Per-accession `tryCatch()` isolation, matching the same pattern
#' `.trim_queries_to_amplicon()`'s own loop already established
#' (2026-08-30) -- one accession's malformed interval data must never abort
#' the whole fallback pass.
#'
#' @param accessions Character vector of accessions still over-length after
#'   primer trimming, in the same order as `sequences`.
#' @param sequences Character vector, same length/order as `accessions` --
#'   each accession's own (still full-length or primer-trim-unchanged)
#'   sequence.
#' @param barcode_term Character. Resolved to a marker via
#'   `.resolve_expected_marker()` above, then to a matching regex via
#'   `.resolve_marker_pattern()`.
#' @param margin Integer (default `100L`). Extra bp kept on each side of the
#'   matched feature's own coordinate span.
#' @param ncbi_api_key,verbose As in `evaluate_reference_accessions()`.
#' @return Character vector, same length/order as `sequences` -- the
#'   extracted feature region (plus margin) where a matching, coordinate-
#'   bearing annotation was found; unchanged (same value as `sequences`)
#'   otherwise. Never discards or errors -- an accession this fallback can't
#'   rescue is left exactly as it was handed in, for the caller's next stage
#'   (the `max_query_len` hard cap) to decide.
#' @noRd
.extract_feature_table_fallback <- function(accessions, sequences, barcode_term,
                                            margin = 100L, ncbi_api_key = NULL,
                                            verbose = TRUE) {
  out <- sequences
  if (length(accessions) == 0L) return(out)

  marker  <- .resolve_expected_marker(barcode_term)
  pattern <- .resolve_marker_pattern(marker)

  ann <- tryCatch(
    .fetch_marker_annotation(accessions, ncbi_api_key = ncbi_api_key, verbose = verbose),
    error = function(e) NULL
  )

  n_rescued <- 0L
  if (!is.null(ann) && nrow(ann) > 0L) {
    for (i in seq_along(accessions)) {
      acc   <- accessions[i]
      seq_i <- sequences[i]
      if (is.na(seq_i) || !nzchar(seq_i)) next

      # extract_one() wraps the actual logic in its OWN function so that
      # return(NULL) below returns from extract_one() alone -- return()
      # inside a bare tryCatch({...}) block (no enclosing function of its
      # own) would otherwise return from .extract_feature_table_fallback()
      # ITSELF, silently abandoning every remaining accession still to be
      # processed in this loop. A real bug caught by this file's own tests
      # (a "no match" or "out-of-bounds span" outcome for accession i was
      # returning NULL for the WHOLE function instead of just leaving
      # sequence i unrescued) before this fix.
      extract_one <- function() {
        sub_ann <- ann[!is.na(ann$accession) & ann$accession == acc &
                       !is.na(ann$feature_from) & !is.na(ann$feature_to), , drop = FALSE]
        if (nrow(sub_ann) == 0L) return(NULL)

        is_match <- (!is.na(sub_ann$gene) & grepl(pattern, sub_ann$gene, ignore.case = TRUE)) |
          (!is.na(sub_ann$product) & grepl(pattern, sub_ann$product, ignore.case = TRUE))
        sub_ann <- sub_ann[is_match, , drop = FALSE]
        if (nrow(sub_ann) == 0L) return(NULL)

        seq_len <- nchar(seq_i)
        span_lo <- min(sub_ann$feature_from, sub_ann$feature_to)
        span_hi <- max(sub_ann$feature_from, sub_ann$feature_to)
        # Bounds guard before substr(), same convention as
        # .extract_amplicon_one_tm()'s own 2026-08-30 fix: an inverted or
        # out-of-range span degrades to "not rescued" rather than producing
        # a nonsensical (or, for substr(), silently empty/truncated) result.
        from <- max(1L, span_lo - margin)
        to   <- min(seq_len, span_hi + margin)
        if (!is.finite(from) || !is.finite(to) || from >= to) return(NULL)

        substr(seq_i, from, to)
      }
      rescued <- tryCatch(extract_one(), error = function(e) NULL)

      if (!is.null(rescued) && nzchar(rescued)) {
        out[i] <- rescued
        n_rescued <- n_rescued + 1L
      }
    }
  }

  if (verbose)
    message(sprintf(
      "evaluate_reference_accessions(): feature-table fallback rescued %d of %d still-over-length query sequence(s) via the record's own GBSeq annotation (marker '%s'); the rest are BLASTed at full length, subject to max_query_len.",
      n_rescued, length(accessions), marker
    ))

  out
}

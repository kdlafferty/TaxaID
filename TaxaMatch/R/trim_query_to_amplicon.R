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
    result <- .extract_amplicon_one_tm(
      seq_char = sequences[i], fwd_pattern = primer_info$fwd, rev_pattern_rc = rev_rc,
      fwd_max_mm = fwd_max_mm, rev_max_mm = rev_max_mm, min_len = span_min, max_len = span_max
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
      "evaluate_reference_accessions(): extracted the amplicon from %d of %d over-length query sequence(s); the rest are BLASTed at full length (primer site(s) not found).",
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

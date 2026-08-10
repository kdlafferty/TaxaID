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

  out <- sequences
  n_trimmed <- 0L
  for (i in which(needs_trim)) {
    result <- .extract_amplicon_one_tm(
      seq_char = sequences[i], fwd_pattern = primer_info$fwd, rev_pattern_rc = rev_rc,
      fwd_max_mm = fwd_max_mm, rev_max_mm = rev_max_mm, min_len = min_len, max_len = max_len
    )
    if (result$trimmed) {
      out[i] <- result$sequence
      n_trimmed <- n_trimmed + 1L
    }
  }

  if (verbose)
    message(sprintf(
      "evaluate_reference_accessions(): extracted the amplicon from %d of %d over-length query sequence(s); the rest are BLASTed at full length (primer site(s) not found).",
      n_trimmed, sum(needs_trim)
    ))

  out
}

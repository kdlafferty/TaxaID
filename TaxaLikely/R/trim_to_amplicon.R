utils::globalVariables(c("sequence"))

# ==============================================================================
# trim_to_amplicon() -- in-silico PCR amplicon extraction for over-length
# reference sequences (e.g. full mitogenomes) that would otherwise be
# discarded outright by build_sequence_matrix()'s min_seq_len/max_seq_len
# filter.
# ==============================================================================

#' Extract the amplicon region from over-length reference sequences (in-silico PCR)
#'
#' GenBank mixes short, purpose-cut barcode submissions with much longer
#' sequences (full mitochondrial genomes, whole-genome scaffolds, full
#' ribosomal operons) that happen to contain the target locus somewhere
#' inside them. [build_sequence_matrix()]'s `min_seq_len`/`max_seq_len`
#' filter excludes these outright -- correct for well-sampled species, but
#' for a poorly-sampled species whose only GenBank record is over-length,
#' exclusion throws away the only genuine reference data available for it.
#'
#' `trim_to_amplicon()` locates the forward and reverse primer-binding sites
#' within each over-length sequence and extracts just the amplicon between
#' them -- the same result a real PCR reaction targeting that marker would
#' have produced -- so the sequence can still contribute real same-species
#' training data instead of being dropped.
#'
#' Sequences already within `[min_len, max_len]` are left completely
#' unchanged (most purpose-cut barcode submissions have already had their
#' primers trimmed off at deposition, so attempting primer matching on them
#' would often fail even though the sequence is perfectly usable). Only
#' sequences longer than `max_len` are searched for primer sites.
#'
#' @section Failure mode:
#' When a primer site cannot be found within tolerance on either strand, or
#' the two matched sites imply an implausible amplicon length (outside
#' `[min_len, max_len]` -- e.g. a spurious match pairing far from the real
#' target), the sequence is left unchanged (still over-length) and flagged in
#' `amplicon_trim_note`. It will still be excluded by
#' [build_sequence_matrix()]'s own length filter, exactly as it would be
#' without ever calling this function -- this function only ever adds
#' sequences that would otherwise be lost, never removes ones that would
#' otherwise be kept.
#'
#' @section Pipeline placement:
#' Standalone stage, run by the caller between
#' [fetch_ncbi_reference_sequences()]/[read_reference_fasta()] and
#' [build_sequence_matrix()]:
#' \preformatted{
#' reference_df <- fetch_ncbi_reference_sequences(...)
#' reference_df <- trim_to_amplicon(reference_df, barcode_term = "MiFishU")
#' ref_matrix   <- build_sequence_matrix(reference_df, ...)
#' }
#'
#' @section Primer source and scope:
#' Primer sequences come from [TaxaTools::barcode_primer_defaults], populated
#' only for primer sets directly verified against their primary publication
#' -- currently MiFish-U and MiFish-E (12S; Miya et al. 2015). For any other
#' marker, either supply `primer_fwd`/`primer_rev` directly (from your own
#' wet-lab protocol or the relevant primer paper), or pre-trim sequences to
#' the amplicon region with the external CRABS tool
#' (\url{https://github.com/gjeunen/reference_database_creator}) before
#' calling [build_sequence_matrix()] -- see `read_crabs_output()`. This
#' function deliberately does not attempt to replicate CRABS's full
#' database-curation feature set (multi-database sourcing, dereplication
#' policy, taxonomic reconciliation); it does one narrow thing -- given a
#' sequence and a primer pair, extract the amplicon region or report failure.
#'
#' @param reference_df Data frame with at least `composite_id` and `sequence`
#'   columns (the same object produced by [fetch_ncbi_reference_sequences()]
#'   / [read_reference_fasta()] and consumed by [build_sequence_matrix()]).
#' @param primer_fwd,primer_rev Character scalars: forward and reverse primer
#'   sequences, 5' to 3', IUPAC-degenerate bases allowed. Supply both, or
#'   neither (to look up `barcode_term` in
#'   [TaxaTools::barcode_primer_defaults] instead).
#' @param barcode_term Character scalar naming a registered primer set (e.g.
#'   `"MiFishU"`), resolved via [TaxaTools::resolve_barcode_primers()]. Also
#'   used to auto-resolve `min_len`/`max_len` via
#'   [TaxaTools::resolve_barcode_lengths()] when those are not supplied
#'   directly.
#' @param min_len,max_len Integer. The plausible amplicon length range for
#'   this marker. Sequences at or below `max_len` are left untouched
#'   (assumed already barcode-length); an extracted amplicon outside
#'   `[min_len, max_len]` is treated as an implausible match and rejected.
#'   Default `NULL` auto-resolves from `barcode_term` when supplied.
#' @param max_mismatch_rate Numeric in `[0, 1)` (default `0.15`). Maximum
#'   fraction of primer positions allowed to mismatch the sequence at the
#'   binding site (rounded down to an integer count of bases per primer).
#'   Accounts for real SNP variation at primer-binding sites; degenerate
#'   IUPAC bases in the primer itself are handled separately and do not
#'   count as mismatches when compatible with the sequence base.
#' @param verbose Logical (default `TRUE`). Print progress/summary messages.
#'
#' @return `reference_df` with `sequence` updated in place for successfully
#'   trimmed rows, plus two new columns:
#'   \describe{
#'     \item{`amplicon_trimmed`}{Logical. `TRUE` if this row's sequence was
#'       replaced with an extracted amplicon.}
#'     \item{`amplicon_trim_note`}{Character. One of
#'       `"within_length_range_no_trim_needed"`,
#'       `"extracted_via_primer_match_sense_strand"`,
#'       `"extracted_via_primer_match_antisense_strand"`,
#'       `"primers_not_found_or_implausible_span"`,
#'       `"non_iupac_dna_skipped"`, `"invalid_dna_string"`, or
#'       `"missing_sequence"`.}
#'   }
#'
#' @seealso [build_sequence_matrix()], [fetch_ncbi_reference_sequences()],
#'   [TaxaTools::barcode_primer_defaults]
#'
#' @examples
#' \dontrun{
#' # Requires Biostrings (Bioconductor)
#' ref_df <- fetch_ncbi_reference_sequences(
#'   taxa = "Rhacochilus", barcode_term = "MiFishU"
#' )
#' ref_df <- trim_to_amplicon(ref_df, barcode_term = "MiFishU")
#' table(ref_df$amplicon_trim_note)
#' }
#'
#' @export
trim_to_amplicon <- function(reference_df,
                              primer_fwd = NULL,
                              primer_rev = NULL,
                              barcode_term = NULL,
                              min_len = NULL,
                              max_len = NULL,
                              max_mismatch_rate = 0.15,
                              verbose = TRUE) {

  if (!is.data.frame(reference_df))
    stop("reference_df must be a data frame")

  needed <- c("composite_id", "sequence")
  missing_cols <- setdiff(needed, names(reference_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("reference_df is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))

  if (xor(is.null(primer_fwd), is.null(primer_rev)))
    stop("trim_to_amplicon: supply both primer_fwd and primer_rev, or neither (to resolve them from barcode_term)")

  if (is.null(primer_fwd)) {
    if (is.null(barcode_term))
      stop("trim_to_amplicon: supply barcode_term (to look up a registered primer pair via TaxaTools::resolve_barcode_primers()), or supply primer_fwd/primer_rev directly.")
    primer_info <- TaxaTools::resolve_barcode_primers(barcode_term)
    primer_fwd  <- primer_info$fwd
    primer_rev  <- primer_info$rev
  }

  if (is.null(min_len) || is.null(max_len)) {
    if (is.null(barcode_term))
      stop("trim_to_amplicon: supply min_len and max_len directly, or barcode_term to auto-resolve them -- these determine which sequences are already barcode-length (left untouched) versus over-length (checked for the amplicon region).")
  }
  lens    <- TaxaTools::resolve_barcode_lengths(barcode_term, min_len = min_len, max_len = max_len)
  min_len <- lens[["min_bp"]]
  max_len <- lens[["max_bp"]]

  if (!is.numeric(max_mismatch_rate) || length(max_mismatch_rate) != 1L ||
      is.na(max_mismatch_rate) || max_mismatch_rate < 0 || max_mismatch_rate >= 1)
    stop("max_mismatch_rate must be a single number in [0, 1)")

  if (!requireNamespace("Biostrings", quietly = TRUE))
    stop("Package 'Biostrings' is required. Install it with: BiocManager::install('Biostrings')")

  df     <- reference_df
  widths <- nchar(df$sequence)

  needs_trim <- !is.na(widths) & widths > max_len

  amplicon_trimmed   <- rep(FALSE, nrow(df))
  amplicon_trim_note <- rep("within_length_range_no_trim_needed", nrow(df))
  amplicon_trim_note[is.na(widths)] <- "missing_sequence"

  if (verbose)
    message(sprintf(
      "trim_to_amplicon: %d of %d sequence(s) exceed max_len (%d bp) and will be checked for the amplicon region.",
      sum(needs_trim, na.rm = TRUE), nrow(df), max_len
    ))

  primer_rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(primer_rev)))
  fwd_max_mm <- floor(nchar(primer_fwd) * max_mismatch_rate)
  rev_max_mm <- floor(nchar(primer_rev) * max_mismatch_rate)

  idx_to_check <- which(needs_trim)
  n_trimmed    <- 0L

  for (i in idx_to_check) {
    result <- .extract_amplicon_one(
      seq_char       = df$sequence[i],
      fwd_pattern    = primer_fwd,
      rev_pattern_rc = primer_rev_rc,
      fwd_max_mm     = fwd_max_mm,
      rev_max_mm     = rev_max_mm,
      min_len        = min_len,
      max_len        = max_len
    )
    amplicon_trim_note[i] <- result$note
    if (result$trimmed) {
      df$sequence[i]    <- result$sequence
      amplicon_trimmed[i] <- TRUE
      n_trimmed <- n_trimmed + 1L
    }
  }

  if (verbose)
    message(sprintf(
      "trim_to_amplicon: extracted the amplicon region from %d of %d over-length sequence(s); %d could not be trimmed (primer site(s) not found, or found an implausible span) and remain over-length -- these will still be excluded downstream by build_sequence_matrix()'s own min_seq_len/max_seq_len filter.",
      n_trimmed, length(idx_to_check), length(idx_to_check) - n_trimmed
    ))

  df$amplicon_trimmed   <- amplicon_trimmed
  df$amplicon_trim_note <- amplicon_trim_note
  df
}


#' Extract the amplicon from one sequence via primer matching, trying both strands
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
.extract_amplicon_one <- function(seq_char, fwd_pattern, rev_pattern_rc,
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
    # matching every primer base for free -- confirmed empirically that
    # fixed = FALSE (both interpreted) produces spurious matches across long
    # N-runs, which fixed = "subject" avoids.
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

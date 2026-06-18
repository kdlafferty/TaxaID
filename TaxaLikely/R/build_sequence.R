utils::globalVariables(c(
  "composite_id", "sequence", "distance", "p_match", "species"
))

# ==============================================================================
# MODULE B: REFERENCE MATRIX CONSTRUCTION
# ==============================================================================

#' Build a pairwise match-score matrix from reference sequences
#'
#' Aligns DNA sequences using `DECIPHER::AlignSeqs()`, computes pairwise
#' distances with `DECIPHER::DistanceMatrix()`, converts distances to match
#' scores (`p_match = 1 - distance`), and joins taxonomy metadata.  The
#' resulting data frame is the input to [flag_reference_errors()] and
#' [train_likelihood_model()].
#'
#' @section Requirements:
#' Packages `DECIPHER` and `Biostrings` must be installed
#' (`BiocManager::install("DECIPHER")`).  They are listed in `Suggests` because
#' they are only needed for this one function.
#'
#' @param reference_df Data frame with one row per reference sequence.  Must
#'   contain:
#'   \describe{
#'     \item{`composite_id`}{Unique sequence identifier (character).}
#'     \item{`sequence`}{DNA string (character, IUPAC alphabet accepted).}
#'     \item{rank columns}{One column per rank in `rank_system`
#'       (e.g., `genus`, `species`).}
#'   }
#' @param rank_system Character vector of rank names **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`). Default `NULL`
#'   auto-detects from columns in `reference_df`.
#' @param max_dist Numeric (default `0.25`).  Pairs with distance above this
#'   threshold are dropped to save memory.  Roughly, 0.25 ≈ 75% identity.
#'   The 75% identity threshold is a standard floor for retaining distantly
#'   related taxa in barcode reference databases.
#' @param min_seq_len Integer (default `100`).  Sequences shorter than this
#'   are discarded before alignment.
#' @param max_seq_len Integer (default `2000`).  Sequences longer than this
#'   are discarded before alignment.
#' @param filter_unnamed Logical (default `TRUE`).  If `TRUE`, sequences whose
#'   finest-rank taxonomy column (the last element of `rank_system`, typically
#'   `species`) is blank (`""`) or `NA` are removed before alignment.  Blank
#'   names produce spurious within-species pairs — two unidentified sequences
#'   both labelled `""` are classified as conspecific even though they may
#'   represent entirely different taxa.  In a broad 18S reference database this
#'   can account for the majority of apparent within-species pairs.  Set to
#'   `FALSE` only if blank finest-rank values are intentional.
#' @param max_seqs_per_taxon Integer or `NULL` (default `NULL`).  If supplied,
#'   at most this many sequences are retained per finest-rank taxon before
#'   alignment, chosen by random sampling using the current RNG state (set
#'   `set.seed()` before calling for reproducibility).  This prevents
#'   heavily-sequenced model organisms or domestic species from dominating
#'   the within-species distribution and thereby distorting model training.
#'   For typical vertebrate barcode databases a value of `10L`–`20L` is
#'   sufficient; the resulting within-species pair counts per taxon are at most
#'   `max_seqs_per_taxon * (max_seqs_per_taxon - 1) / 2`.  `NULL` disables
#'   the cap (current behaviour).
#'
#' @return A data frame with one row per sequence pair within `max_dist`:
#'   \describe{
#'     \item{`id_x`, `id_y`}{`composite_id` values for each pair member.}
#'     \item{`p_match`}{Match score (1 − distance), range (0, 1].}
#'     \item{`coverage`}{Alignment coverage: number of positions where both
#'       sequences contribute a non-gap character, divided by the shorter
#'       unaligned sequence length.  Range (0, 1].  Values near 1.0 indicate
#'       nearly complete overlap; values near 0.0 indicate highly gappy or
#'       partial alignments that produce unreliable match scores.  Use
#'       [calibrate_coverage_filter()] or [coverage_threshold()] to select a
#'       minimum coverage threshold before calling [train_likelihood_model()].}
#'     \item{`{rank}.x`, `{rank}.y`}{Taxonomy columns for each pair member.}
#'   }
#'
#' @seealso [flag_reference_errors()], [train_likelihood_model()]
#'
#' @examples
#' \dontrun{
#' # Requires DECIPHER + Biostrings (Bioconductor)
#' ref_matrix <- build_sequence_matrix(
#'   reference_df,
#'   rank_system       = c("family", "genus", "species"),
#'   filter_unnamed    = TRUE,   # drop blank/NA species (default)
#'   max_seqs_per_taxon = 20L    # cap per-species sequences before alignment
#' )
#' head(ref_matrix)
#' }
#'
#' @importFrom dplyr all_of distinct filter left_join mutate rename_with select
#' @export
build_sequence_matrix <- function(reference_df,
                                   rank_system        = NULL,
                                   max_dist           = 0.25,
                                   min_seq_len        = 100L,
                                   max_seq_len        = 2000L,
                                   filter_unnamed     = TRUE,
                                   max_seqs_per_taxon = NULL) {
  if (!is.data.frame(reference_df))
    stop("reference_df must be a data frame")

  needed <- c("composite_id", "sequence")
  missing_cols <- setdiff(needed, names(reference_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("reference_df is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))

  if (!is.logical(filter_unnamed) || length(filter_unnamed) != 1L || is.na(filter_unnamed))
    stop("filter_unnamed must be TRUE or FALSE")

  if (!is.null(max_seqs_per_taxon)) {
    if (!is.numeric(max_seqs_per_taxon) || length(max_seqs_per_taxon) != 1L ||
        is.na(max_seqs_per_taxon) || max_seqs_per_taxon < 2L)
      stop("max_seqs_per_taxon must be NULL or an integer >= 2")
    max_seqs_per_taxon <- as.integer(max_seqs_per_taxon)
  }

  if (!requireNamespace("DECIPHER",   quietly = TRUE))
    stop("Package 'DECIPHER' is required. Install it with: BiocManager::install('DECIPHER')")
  if (!requireNamespace("Biostrings", quietly = TRUE))
    stop("Package 'Biostrings' is required. Install it with: BiocManager::install('Biostrings')")

  names(reference_df) <- tolower(names(reference_df))

  # Auto-detect rank_system from reference_df columns
  if (is.null(rank_system) || length(rank_system) == 0L) {
    rank_system <- TaxaTools::detect_ranks(reference_df, warn = FALSE)
    if (length(rank_system) == 0L) {
      # Fallback to standard trio
      fallback <- c("family", "genus", "species")
      rank_system <- fallback[fallback %in% names(reference_df)]
    }
    if (length(rank_system) == 0L)
      stop("rank_system could not be auto-detected. reference_df has no recognized taxonomy columns.")
    message("build_sequence_matrix: auto-detected rank_system: ",
            paste(rank_system, collapse = ", "))
  }

  rank_cols <- tolower(rank_system)
  missing_ranks <- setdiff(rank_cols, names(reference_df))
  if (length(missing_ranks) > 0L)
    stop(sprintf("rank_system columns not found in reference_df (after lowercasing): %s",
                 paste(missing_ranks, collapse = ", ")))

  # ---- 1. CLEAN & DEDUPLICATE -----------------------------------------------
  df <- reference_df |>
    dplyr::filter(!is.na(sequence), nchar(sequence) > 0L) |>
    dplyr::distinct(composite_id, .keep_all = TRUE)

  if (nrow(df) < 2L)
    stop("Fewer than 2 valid sequences in reference_df after deduplication")

  # ---- 1b. IUPAC DNA FILTER --------------------------------------------------
  # Biostrings::DNAStringSet() throws a cryptic lookup-table error if a sequence
  # contains non-IUPAC-DNA characters (e.g., 'E', 'F', 'I', 'L' — amino acid
  # codes returned when an accession resolves to a protein record or a corrupt
  # NCBI entry).  Filter these out with a clear message before hitting Biostrings.
  valid_iupac <- "^[ACGTRYSWKMBDHVNacgtryswkmbdhvn-]+$"
  is_valid    <- grepl(valid_iupac, df$sequence)
  n_invalid   <- sum(!is_valid)
  if (n_invalid > 0L) {
    bad_ids <- head(df$composite_id[!is_valid], 5L)
    warning(sprintf(
      "build_sequence_matrix: removed %d sequence(s) with non-IUPAC DNA characters %s(likely protein accessions or corrupt records).",
      n_invalid,
      sprintf("(e.g. %s) ", paste(bad_ids, collapse = ", "))
    ), call. = FALSE)
    df <- df[is_valid, , drop = FALSE]
  }

  if (nrow(df) < 2L)
    stop("Fewer than 2 valid DNA sequences in reference_df after IUPAC filter")

  # ---- 1c. FILTER UNNAMED FINEST-RANK TAXA ------------------------------------
  # Pairs where the finest-rank label is blank or NA are not valid within-species
  # training pairs.  In broad 18S reference databases, blank species names can
  # account for the majority of apparent within-species pairs.
  finest_rank <- rank_cols[length(rank_cols)]
  if (filter_unnamed && finest_rank %in% names(df)) {
    finest_vals <- df[[finest_rank]]
    is_named    <- !is.na(finest_vals) & nchar(trimws(finest_vals)) > 0L
    n_unnamed   <- sum(!is_named)
    if (n_unnamed > 0L) {
      message(sprintf(
        "build_sequence_matrix: removed %d sequence(s) with blank/NA '%s' (filter_unnamed = TRUE).",
        n_unnamed, finest_rank
      ))
      df <- df[is_named, , drop = FALSE]
    }
    if (nrow(df) < 2L)
      stop("Fewer than 2 sequences remained after filtering unnamed sequences")
  }

  # ---- 1d. THIN TO max_seqs_per_taxon -----------------------------------------
  # Randomly subsample sequences per finest-rank taxon before alignment to
  # prevent heavily-sequenced species from dominating the within-species
  # distribution.  Uses the caller's RNG state; call set.seed() beforehand for
  # reproducibility.
  if (!is.null(max_seqs_per_taxon) && finest_rank %in% names(df)) {
    finest_vals <- df[[finest_rank]]
    unique_taxa <- unique(finest_vals)
    over_cap    <- unique_taxa[
      vapply(unique_taxa, function(tx) sum(finest_vals == tx), integer(1L)) > max_seqs_per_taxon
    ]
    if (length(over_cap) > 0L) {
      keep_rows <- unlist(lapply(unique_taxa, function(tx) {
        rows <- which(finest_vals == tx)
        if (length(rows) > max_seqs_per_taxon) sample(rows, max_seqs_per_taxon) else rows
      }), use.names = FALSE)
      df <- df[sort(keep_rows), , drop = FALSE]
      message(sprintf(
        "build_sequence_matrix: capped %d taxon/taxa to <= %d sequences per '%s'.",
        length(over_cap), max_seqs_per_taxon, finest_rank
      ))
    }
    if (nrow(df) < 2L)
      stop("Fewer than 2 sequences remained after thinning to max_seqs_per_taxon")
  }

  # ---- 2. LENGTH FILTER -------------------------------------------------------
  dna <- Biostrings::DNAStringSet(df$sequence)
  names(dna) <- df$composite_id

  widths    <- Biostrings::width(dna)
  valid_idx <- widths >= min_seq_len & widths <= max_seq_len
  n_dropped <- sum(!valid_idx)

  if (n_dropped > 0L)
    message(sprintf("Dropped %d sequence(s) outside length range [%d, %d]",
                    n_dropped, min_seq_len, max_seq_len))

  dna <- dna[valid_idx]
  df  <- df[valid_idx, , drop = FALSE]

  if (length(dna) < 2L)
    stop(sprintf(
      "Fewer than 2 sequences remained after length filtering [%d, %d]",
      min_seq_len, max_seq_len
    ))

  # ---- 3. ALIGNMENT & DISTANCE MATRIX ----------------------------------------
  t0 <- proc.time()[["elapsed"]]
  message("Aligning sequences with DECIPHER...")
  aligned <- DECIPHER::AlignSeqs(dna, processors = NULL, verbose = FALSE)
  message(sprintf("Alignment complete (%.1fs)", proc.time()[["elapsed"]] - t0))

  t1 <- proc.time()[["elapsed"]]
  message("Computing pairwise distance matrix...")
  dist_m <- DECIPHER::DistanceMatrix(
    aligned,
    type                 = "matrix",
    includeTerminalGaps  = FALSE,
    processors           = NULL,
    verbose              = FALSE
  )

  message(sprintf("Distance matrix complete (%.1fs)", proc.time()[["elapsed"]] - t1))

  # Sparse extraction: only materialise pairs within max_dist (avoids N² intermediate)
  idx <- which(dist_m < max_dist & row(dist_m) != col(dist_m), arr.ind = TRUE)

  # ---- 3b. PAIRWISE ALIGNMENT COVERAGE ---------------------------------------
  # Coverage = number of positions where both sequences contribute a non-gap
  # character, divided by the shorter unaligned sequence length.  A score
  # computed over a short overlap is unreliable even when the matched bases are
  # identical.  Pre-computing per-sequence gap masks (O(n × aln_width)) and
  # looking up per sparse pair (O(pairs × aln_width)) is cheaper than
  # re-parsing the alignment string for every pair individually.
  aln_str     <- as.character(aligned)     # named char vec of aligned sequences
  gap_masks   <- lapply(
    aln_str,
    function(s) strsplit(s, "", fixed = TRUE)[[1L]] != "-"
  )
  orig_widths <- vapply(
    aln_str,
    function(s) nchar(gsub("-", "", s, fixed = TRUE)),
    integer(1L)
  )
  seq_names   <- names(aligned)

  coverage_vals <- vapply(seq_len(nrow(idx)), function(k) {
    nm_i    <- seq_names[idx[k, 1L]]
    nm_j    <- seq_names[idx[k, 2L]]
    overlap <- sum(gap_masks[[nm_i]] & gap_masks[[nm_j]])
    min_len <- min(orig_widths[[nm_i]], orig_widths[[nm_j]])
    if (min_len == 0L) NA_real_ else as.double(overlap) / min_len
  }, numeric(1L))

  dist_tbl <- data.frame(
    id_x     = rownames(dist_m)[idx[, 1L]],
    id_y     = colnames(dist_m)[idx[, 2L]],
    p_match  = 1 - dist_m[idx],
    coverage = coverage_vals,
    stringsAsFactors = FALSE
  )

  # ---- 4. MERGE TAXONOMY METADATA --------------------------------------------
  present_rank_cols <- intersect(rank_cols, names(df))
  lookup <- dplyr::select(df, composite_id, dplyr::all_of(present_rank_cols))

  out <- dist_tbl |>
    dplyr::left_join(lookup, by = c("id_x" = "composite_id")) |>
    dplyr::rename_with(~ paste0(., ".x"), dplyr::all_of(present_rank_cols)) |>
    dplyr::left_join(lookup, by = c("id_y" = "composite_id")) |>
    dplyr::rename_with(~ paste0(., ".y"), dplyr::all_of(present_rank_cols))

  message(sprintf("Matrix built: %d pairs within distance < %.2f",
                  nrow(out), max_dist))
  out
}

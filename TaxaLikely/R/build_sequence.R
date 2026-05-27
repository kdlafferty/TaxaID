utils::globalVariables(c(
  "composite_id", "sequence", "distance", "p_match"
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
#'
#' @return A data frame with one row per sequence pair within `max_dist`:
#'   \describe{
#'     \item{`id_x`, `id_y`}{`composite_id` values for each pair member.}
#'     \item{`p_match`}{Match score (1 − distance), range (0, 1].}
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
#'   rank_system = c("family", "genus", "species")
#' )
#' head(ref_matrix)
#' }
#'
#' @importFrom dplyr all_of distinct filter left_join mutate rename_with select
#' @export
build_sequence_matrix <- function(reference_df,
                                   rank_system = NULL,
                                   max_dist    = 0.25,
                                   min_seq_len = 100L,
                                   max_seq_len = 2000L) {
  if (!is.data.frame(reference_df))
    stop("reference_df must be a data frame")

  needed <- c("composite_id", "sequence")
  missing_cols <- setdiff(needed, names(reference_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("reference_df is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))

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
  dist_tbl <- data.frame(
    id_x    = rownames(dist_m)[idx[, 1L]],
    id_y    = colnames(dist_m)[idx[, 2L]],
    p_match = 1 - dist_m[idx],
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

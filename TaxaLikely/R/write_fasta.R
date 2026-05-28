#' Write a Reference Data Frame to FASTA Format
#'
#' Exports a `reference_df` (from [fetch_reference_sequences()] or
#' [read_reference_fasta()]) to a FASTA file compatible with BLAST, CRABS,
#' Obitools, and other external tools. Optionally writes a companion taxonomy
#' TSV in the same positional format accepted by
#' [read_reference_fasta()], making the export fully round-trippable.
#'
#' The FASTA header format is:
#' \code{>{composite_id} {rank1_value} {rank2_value} ...}
#' with taxonomy values joined by single spaces (missing ranks omitted).
#' This is the most widely compatible header format for downstream tools.
#'
#' The optional taxonomy TSV is a 2-column tab-delimited file (no header):
#' column 1 = `composite_id`, column 2 = semicolon-separated taxonomy values
#' in `rank_system` order. This file can be passed directly to
#' [read_reference_fasta()] to reload the reference.
#'
#' @param reference_df Data frame with columns `composite_id`, `sequence`, and
#'   at least one taxonomy column from `rank_system`.
#'   Output of [fetch_reference_sequences()], [read_reference_fasta()], or
#'   [read_crabs_output()].
#' @param file Character. Output path for the FASTA file
#'   (e.g., `"reference.fasta"`).
#' @param taxonomy_file Character or \code{NULL}.
#'   If not NULL, write a companion 2-column taxonomy TSV to this path.
#'   The file can be passed to [read_reference_fasta()] as `taxonomy_file`.
#' @param rank_system Character vector of taxonomy columns to include, coarse
#'   to fine. Defaults to all taxonomy-like columns found in `reference_df`
#'   (everything except `composite_id` and `sequence`).
#'
#' @return Invisibly returns `reference_df`. Called for its side-effect of
#'   writing files.
#'
#' @seealso [read_reference_fasta()], [fetch_reference_sequences()],
#'   [read_crabs_output()], [build_site_reference()]
#'
#' @examples
#' \dontrun{
#' ref <- fetch_reference_sequences(
#'   taxa        = "Fundulus",
#'   barcode_term = "MiFishU"
#' )
#' write_reference_fasta(ref, "fundulus_mifish.fasta",
#'                       taxonomy_file = "fundulus_mifish_taxonomy.tsv")
#'
#' # Round-trip: reload the same reference
#' ref2 <- read_reference_fasta("fundulus_mifish.fasta",
#'                               taxonomy_file = "fundulus_mifish_taxonomy.tsv",
#'                               rank_system   = c("family", "genus", "species"))
#' }
#'
#' @export
write_reference_fasta <- function(reference_df,
                                   file,
                                   taxonomy_file = NULL,
                                   rank_system   = NULL) {

  if (!is.data.frame(reference_df))
    stop("reference_df must be a data frame.", call. = FALSE)
  if (!all(c("composite_id", "sequence") %in% names(reference_df)))
    stop("reference_df must have 'composite_id' and 'sequence' columns.",
         call. = FALSE)
  if (!is.character(file) || length(file) != 1L || !nzchar(file))
    stop("file must be a single non-empty character path.", call. = FALSE)

  # Determine taxonomy columns
  non_tax_cols <- c("composite_id", "sequence")
  if (is.null(rank_system)) {
    rank_system <- setdiff(names(reference_df), non_tax_cols)
    if (length(rank_system) == 0L)
      stop("No taxonomy columns found in reference_df.", call. = FALSE)
  } else {
    missing <- setdiff(rank_system, names(reference_df))
    if (length(missing) > 0L)
      stop(sprintf(
        "rank_system column(s) not found in reference_df: %s",
        paste(missing, collapse = ", ")
      ), call. = FALSE)
  }

  # Build FASTA lines
  n <- nrow(reference_df)
  lines <- character(n * 2L)

  for (i in seq_len(n)) {
    # Header: accession + non-NA taxonomy values
    tax_vals <- vapply(rank_system, function(col) {
      v <- reference_df[[col]][i]
      if (is.na(v) || !nzchar(trimws(v))) "" else trimws(v)
    }, character(1L))
    tax_str <- paste(tax_vals[nchar(tax_vals) > 0L], collapse = " ")

    header <- if (nzchar(tax_str)) {
      paste0(">", reference_df$composite_id[i], " ", tax_str)
    } else {
      paste0(">", reference_df$composite_id[i])
    }

    lines[(i - 1L) * 2L + 1L] <- header
    lines[(i - 1L) * 2L + 2L] <- reference_df$sequence[i]
  }

  writeLines(lines, file)
  message(sprintf("Wrote %d sequences to %s", n, file))

  # Optionally write taxonomy TSV (positional format; readable by
  # read_reference_fasta(taxonomy_file=))
  if (!is.null(taxonomy_file)) {
    if (!is.character(taxonomy_file) || length(taxonomy_file) != 1L ||
        !nzchar(taxonomy_file))
      stop("taxonomy_file must be a single non-empty character path.",
           call. = FALSE)

    tax_strings <- vapply(seq_len(n), function(i) {
      vals <- vapply(rank_system, function(col) {
        v <- reference_df[[col]][i]
        if (is.na(v)) "" else trimws(v)
      }, character(1L))
      paste(vals, collapse = ";")
    }, character(1L))

    tsv_lines <- paste(reference_df$composite_id, tax_strings, sep = "\t")
    writeLines(tsv_lines, taxonomy_file)
    message(sprintf("Wrote taxonomy TSV (%d rows) to %s", n, taxonomy_file))
  }

  invisible(reference_df)
}

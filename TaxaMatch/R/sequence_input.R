# ==============================================================================
# read_sequence_table() — Ingest DADA2 sequence table or FASTA file
# ==============================================================================

# Non-abundance column names excluded from abundance_cols auto-detection.
# Module-level (not rebuilt inside .read_esv_dataframe() on every call) so
# it can be found and extended without hunting inside the function body as
# new provider formats are added. Entries must be lowercase, matched exactly
# against tolower(names(df)) -- see .read_esv_dataframe()'s auto-detect branch.
.non_abundance_col_names <- c(
  TaxaTools::standard_ranks,
  "sequence", "esv", "asv", "asv_id", "esv_id", "observation_id", "accession",
  "identifier", "pctmatch", "percmatch", "score", "numspp", "testid",
  "taxon_name", "taxon_name_rank"
)

#' Generate zero-padded ASV identifiers
#'
#' Shared by \code{.read_esv_dataframe()}, \code{.read_dada2_matrix()}, and
#' \code{.read_dna_stringset()} to keep zero-padding behavior consistent
#' across all three input paths.
#' @noRd
.generate_asv_ids <- function(n, id_prefix) {
  pad <- nchar(as.character(n))
  sprintf("%s_%0*d", id_prefix, pad, seq_len(n))
}

#' Build the core 4-column sequence table output (asv_id/sequence/length/abundance)
#'
#' Also warns (does not error) on sequences containing non-IUPAC nucleotide
#' characters, and on duplicate sequences -- both are common, easy-to-miss
#' data-quality issues in externally supplied FASTA/provider files.
#' @noRd
.build_core_seq_df <- function(asv_ids, sequences, abundances) {
  bad_chars <- !grepl("^[ACGTNacgtnRYSWKMBDHVryswkmbdhv-]*$", sequences)
  if (any(bad_chars)) {
    warning(sprintf(
      paste0(
        "%d sequence(s) contain characters outside the standard IUPAC ",
        "nucleotide alphabet; length/downstream BLAST results may be affected."
      ),
      sum(bad_chars)
    ), call. = FALSE)
  }
  dup_seq <- duplicated(sequences)
  if (any(dup_seq)) {
    warning(sprintf(
      paste0(
        "%d duplicate sequence(s) found (same DNA string, different entries); ",
        "each retains its own asv_id/abundance rather than being merged."
      ),
      sum(dup_seq)
    ), call. = FALSE)
  }
  data.frame(
    asv_id = asv_ids,
    sequence = sequences,
    length = nchar(sequences),
    abundance = abundances,
    stringsAsFactors = FALSE
  )
}

#' Read Sequence Data into a Tidy ASV Table
#'
#' Converts a DADA2 sequence table (matrix), a FASTA file, or a data frame
#' (e.g., from a sequencing provider's CSV) into a tidy data frame with one
#' row per unique sequence.
#'
#' @param input_data One of:
#'   \itemize{
#'     \item A DADA2 sequence table (matrix with samples as rows and DNA
#'       sequences as column names)
#'     \item A path to a FASTA file
#'     \item A \code{DNAStringSet} object from Biostrings
#'     \item A data frame containing at least a \code{sequence} column (e.g.,
#'       output from a sequencing provider). See Details for how abundance is
#'       computed.
#'   }
#' @param sequence_col For data frame input: name of the column containing
#'   DNA sequences. Default \code{"sequence"}. Matching is case-insensitive
#'   (all column names are lowercased internally for matching), though the
#'   returned columns other than the four core ones are lowercased in the
#'   output regardless of their original casing in \code{input_data}.
#' @param observation_id_col For data frame input: name of an existing observation/ESV
#'   identifier column to use as \code{asv_id}. If \code{NULL} (default),
#'   sequential IDs are generated using \code{id_prefix}.
#' @param abundance_cols For data frame input: character vector of column names
#'   containing per-sample read counts to sum for total abundance. If
#'   \code{NULL} (default), numeric columns that are not taxonomy or metadata
#'   are auto-detected against an internal exclusion list (case-insensitive
#'   exact match against standard taxonomy ranks plus common ID/score column
#'   names -- see \code{.non_abundance_col_names} in the package source for
#'   the exact list). If no abundance columns are found, abundance is set
#'   to 1 per row. A \code{message()} reports which columns were summed (or
#'   that none were found), so unexpected auto-detection results can be
#'   diagnosed without inspecting the code.
#' @param taxonomy Optional data frame with taxonomy for each sequence. Must
#'   contain a column named \code{"sequence"} (for DADA2/DNAStringSet input,
#'   matched against the sequence itself) or \code{"accession"} (for FASTA
#'   input, matched against the header's first whitespace-delimited token).
#'   See Details. Ignored for data frame input (taxonomy columns are
#'   retained directly).
#' @param header_format For FASTA input only: how to parse taxonomy from
#'   sequence headers. \code{"semicolon"} expects
#'   \code{accession;kingdom;phylum;class;order;family;genus;species}.
#'   \code{"none"} (default) does not parse headers.
#' @param id_prefix Character prefix for generated ASV identifiers.
#'   Default \code{"ASV"}.
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{asv_id}{Unique identifier (e.g., "ASV_001")}
#'     \item{sequence}{DNA sequence string}
#'     \item{length}{Sequence length in base pairs}
#'     \item{abundance}{Total read count across all samples}
#'   }
#'   If taxonomy is provided (via \code{taxonomy} argument, parsed from FASTA
#'   headers, or present in a data frame input), taxonomy columns are appended.
#'   For FASTA/\code{DNAStringSet} input with \code{header_format = "none"}
#'   (the default), an \code{accession} column is also added (the header's
#'   first whitespace-delimited token) -- this column drives taxonomy joining
#'   via the \code{taxonomy} argument's \code{"accession"} key.
#'
#' @details
#' **DADA2 input:** The standard DADA2 sequence table is a matrix where rows are
#' samples, columns are ASV sequences (the column names are the literal DNA
#' strings), and cells are integer read counts. \code{read_sequence_table()}
#' collapses across samples to get total abundance per unique sequence.
#' Rows are expected to be samples and columns sequences (DADA2's own
#' convention); a transposed OTU-table-style matrix (rows = OTUs/ASVs,
#' columns = samples, as used by QIIME2's biom format or mothur shared
#' files) is not auto-detected and will be misread.
#'
#' **FASTA input:** Accepts a file path (extensions .fasta, .fa, .fna, .fas) or
#' a \code{Biostrings::DNAStringSet} object. Abundance is set to 1 per sequence
#' unless the header contains abundance information (e.g., \code{;size=42}).
#' Sequences are not validated to contain only IUPAC nucleotide characters;
#' a \code{warning()} is issued (not an error) when non-IUPAC characters or
#' duplicate sequences are found.
#'
#' **Data frame input:** Accepts any data frame with a column containing DNA
#' sequences. Common sources include provider ASV/ESV tables with sample read
#' counts in separate columns (e.g. Jonah Ventures tab+taxa CSV files).
#' Abundance is computed by summing across \code{abundance_cols}. If not
#' specified, the function auto-detects numeric columns that are not standard
#' taxonomy or metadata columns -- see \code{@param abundance_cols} for the
#' auto-detection rule. Taxonomy columns (kingdom, phylum, class, order,
#' family, genus, species) and other non-numeric columns are retained in the
#' output.
#'
#' **Taxonomy:** Can be supplied three ways:
#' \enumerate{
#'   \item Via the \code{taxonomy} argument (data frame with a \code{sequence}
#'     or \code{accession} column for joining)
#'   \item Parsed from FASTA headers with \code{header_format = "semicolon"}
#'   \item Directly present in a data frame input (retained automatically)
#' }
#'
#' @examples
#' \dontrun{
#' seq_df <- read_sequence_table(seqtab_nochim)
#' # Or from FASTA:
#' seq_df <- read_sequence_table("sequences.fasta")
#' }
#'
#' @export
read_sequence_table <- function(input_data,
                                sequence_col = "sequence",
                                observation_id_col = NULL,
                                abundance_cols = NULL,
                                taxonomy = NULL,
                                header_format = "none",
                                id_prefix = "ASV") {
  # --- Input validation -------------------------------------------------------
  if (!is.character(id_prefix) || length(id_prefix) != 1L || is.na(id_prefix)) {
    stop("id_prefix must be a single non-NA character string")
  }
  if (!is.character(header_format) || length(header_format) != 1L) {
    stop("header_format must be a single character string")
  }
  header_format <- match.arg(header_format, c("none", "semicolon"))
  if (!is.null(taxonomy) && !is.data.frame(taxonomy)) {
    stop("taxonomy must be a data frame or NULL")
  }

  # --- Dispatch by input type -------------------------------------------------
  if (is.data.frame(input_data)) {
    result <- .read_esv_dataframe(
      input_data, sequence_col, observation_id_col,
      abundance_cols, id_prefix
    )
  } else if (is.matrix(input_data)) {
    result <- .read_dada2_matrix(input_data, id_prefix)
  } else if (is.character(input_data) && length(input_data) == 1L && !is.na(input_data)) {
    result <- .read_fasta_file(input_data, header_format, id_prefix)
  } else if (inherits(input_data, "DNAStringSet")) {
    result <- .read_dna_stringset(input_data, header_format, id_prefix)
  } else {
    stop(
      "input_data must be a data frame, a DADA2 sequence table (matrix), ",
      "a path to a FASTA file, or a Biostrings::DNAStringSet object"
    )
  }

  # --- Join external taxonomy if supplied (non-df inputs only) ----------------
  if (!is.null(taxonomy) && !is.data.frame(input_data)) {
    result <- .join_taxonomy(result, taxonomy)
  }

  result
}


# --- Internal: Data frame (ESV table from provider) ---------------------------

#' @noRd
.read_esv_dataframe <- function(esv_df, sequence_col, observation_id_col,
                                abundance_cols, id_prefix) {
  # Lowercase column names for matching (case-insensitive), while the
  # original esv_df columns retain their original casing throughout.
  orig_names <- names(esv_df)
  lc_names <- tolower(orig_names)

  # Find sequence column
  seq_idx <- match(tolower(sequence_col), lc_names)
  if (is.na(seq_idx)) {
    stop(sprintf("Column '%s' not found in data frame", sequence_col))
  }
  sequences <- as.character(esv_df[[seq_idx]])

  # Find or generate ASV IDs
  if (!is.null(observation_id_col)) {
    id_idx <- match(tolower(observation_id_col), lc_names)
    if (is.na(id_idx)) {
      stop(sprintf("Column '%s' not found in data frame", observation_id_col))
    }
    asv_ids <- as.character(esv_df[[id_idx]])
  } else {
    asv_ids <- .generate_asv_ids(nrow(esv_df), id_prefix)
  }

  if (!is.null(abundance_cols)) {
    # User-specified abundance columns
    abund_idx <- match(tolower(abundance_cols), lc_names)
    missing <- abundance_cols[is.na(abund_idx)]
    if (length(missing) > 0L) {
      stop(sprintf("Abundance columns not found: %s", paste(missing, collapse = ", ")))
    }
    abund_idx <- abund_idx[!is.na(abund_idx)]
  } else {
    # Auto-detect: numeric columns not in the known non-abundance set
    # (.non_abundance_col_names, module-level -- see its own definition for
    # the maintenance note on extending it for new provider formats)
    abund_idx <- which(
      vapply(esv_df, is.numeric, logical(1L)) &
        !lc_names %in% .non_abundance_col_names &
        !seq_along(lc_names) %in% c(seq_idx)
    )
    # Also exclude the observation_id column if provided
    if (!is.null(observation_id_col)) {
      id_idx_val <- match(tolower(observation_id_col), lc_names)
      abund_idx <- setdiff(abund_idx, id_idx_val)
    }
  }

  # Compute abundance
  if (length(abund_idx) > 0L) {
    abundances <- as.integer(rowSums(esv_df[, abund_idx, drop = FALSE], na.rm = TRUE))
    message(sprintf(
      "Summed abundance across %d sample column(s): %s",
      length(abund_idx), paste(orig_names[abund_idx], collapse = ", ")
    ))
  } else {
    abundances <- rep(1L, nrow(esv_df))
    message("No abundance columns detected. Setting abundance = 1 per row.")
  }

  # Build core output
  result <- .build_core_seq_df(asv_ids, sequences, abundances)

  # Retain taxonomy and other metadata columns (exclude sequence, ID, abundance)
  exclude_idx <- c(seq_idx, abund_idx)
  if (!is.null(observation_id_col)) {
    exclude_idx <- c(exclude_idx, match(tolower(observation_id_col), lc_names))
  }
  keep_idx <- setdiff(seq_along(orig_names), exclude_idx)

  if (length(keep_idx) > 0L) {
    extra <- esv_df[, keep_idx, drop = FALSE]
    # Lowercase the retained column names for consistency with the rest of
    # this package's column-naming convention (case-insensitive matching in,
    # lowercase out) -- deliberate, not an oversight.
    names(extra) <- tolower(names(extra))
    result <- cbind(result, extra)
  }

  result
}


# --- Internal: DADA2 matrix ---------------------------------------------------

#' @noRd
.read_dada2_matrix <- function(mat, id_prefix) {
  if (is.null(colnames(mat))) {
    stop("DADA2 sequence table must have DNA sequences as column names")
  }

  sequences <- colnames(mat)
  abundances <- as.integer(colSums(mat))

  .build_core_seq_df(.generate_asv_ids(length(sequences), id_prefix), sequences, abundances)
}


# --- Internal: FASTA file path ------------------------------------------------

#' @noRd
.read_fasta_file <- function(path, header_format, id_prefix) {
  if (!file.exists(path)) {
    stop(sprintf("FASTA file not found: %s", path))
  }

  .check_pkg("Biostrings", "BiocManager::install('Biostrings')")

  dna <- Biostrings::readDNAStringSet(path)
  .read_dna_stringset(dna, header_format, id_prefix)
}


# --- Internal: DNAStringSet object --------------------------------------------

#' @noRd
.read_dna_stringset <- function(dna, header_format, id_prefix) {
  sequences <- as.character(dna)
  headers <- names(dna)
  n <- length(sequences)

  # Try to extract abundance from headers (e.g., ";size=42")
  abundances <- vapply(headers, function(h) {
    m <- regexpr(";size=(\\d+)", h)
    if (m == -1L) {
      return(1L)
    }
    val <- suppressWarnings(as.integer(sub(";size=", "", regmatches(h, m))))
    if (is.na(val)) {
      warning(sprintf("Malformed ;size= value in header: %s. Using abundance = 1.", h))
      return(1L)
    }
    val
  }, integer(1L), USE.NAMES = FALSE)

  result <- .build_core_seq_df(.generate_asv_ids(n, id_prefix), sequences, abundances)

  # Parse taxonomy from semicolon-delimited headers if requested
  if (header_format == "semicolon") {
    tax <- .parse_semicolon_headers(headers)
    result <- cbind(result, tax)
  } else {
    # Use header as accession (first whitespace-delimited token)
    result$accession <- vapply(
      strsplit(headers, "\\s+"), `[`, character(1L), 1L
    )
  }

  result
}


# --- Internal: parse semicolon-delimited FASTA headers ------------------------
# Format: accession;kingdom;phylum;class;order;family;genus;species

#' @noRd
.parse_semicolon_headers <- function(headers) {
  if (length(headers) == 0L) {
    return(data.frame(accession = character(0), stringsAsFactors = FALSE))
  }
  parts <- strsplit(headers, ";")
  # Determine number of fields from first header
  n_fields <- length(parts[[1L]])

  if (n_fields < 2L) {
    warning("Semicolon-delimited headers have fewer than 2 fields. No taxonomy parsed.")
    return(data.frame(
      accession = vapply(parts, `[`, character(1L), 1L),
      stringsAsFactors = FALSE
    ))
  }

  # Standard rank names for positions 2..8
  rank_names <- TaxaTools::standard_ranks
  n_ranks <- min(n_fields - 1L, length(rank_names))
  n_cols <- 1L + n_ranks

  # Pre-allocated character matrix, filled row by row -- avoids the O(n^2)
  # do.call(rbind, lapply(...)) growth pattern for FASTA files with many
  # sequences. Rows shorter than n_cols (fewer semicolon-delimited fields
  # than expected) are left NA-padded on the right.
  mat <- matrix(NA_character_, nrow = length(parts), ncol = n_cols)
  for (i in seq_along(parts)) {
    p <- parts[[i]][seq_len(min(length(parts[[i]]), n_cols))]
    mat[i, seq_along(p)] <- p
  }

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  colnames(df) <- c("accession", rank_names[seq_len(n_ranks)])

  # Clean empty strings to NA
  df[] <- lapply(df, function(col) ifelse(trimws(col) == "", NA_character_, trimws(col)))

  df
}


# --- Internal: join external taxonomy to sequence table -----------------------

#' @noRd
.join_taxonomy <- function(seq_df, taxonomy) {
  tax_names <- tolower(names(taxonomy))
  names(taxonomy) <- tax_names

  # Try to join on sequence first, then accession

  if ("sequence" %in% tax_names && "sequence" %in% names(seq_df)) {
    merged <- merge(seq_df, taxonomy, by = "sequence", all.x = TRUE, sort = FALSE)
  } else if ("accession" %in% tax_names && "accession" %in% names(seq_df)) {
    merged <- merge(seq_df, taxonomy, by = "accession", all.x = TRUE, sort = FALSE)
  } else {
    warning(
      "taxonomy must contain a 'sequence' or 'accession' column for joining. ",
      "Taxonomy not joined."
    )
    return(seq_df)
  }

  # Restore original row order by asv_id. Relies on match() returning a
  # stable, deterministic ordering for repeated/tied asv_id values, which
  # base R guarantees (first-match position).
  merged <- merged[order(match(merged$asv_id, seq_df$asv_id)), ]
  rownames(merged) <- NULL
  merged
}


# ==============================================================================
# filter_sequences() — Filter ASVs by length and abundance
# ==============================================================================

#' Filter Sequences by Length and Abundance
#'
#' Removes sequences that fall outside acceptable length bounds or below a
#' minimum abundance threshold. Length bounds can be set automatically from
#' a barcode marker name or specified manually.
#'
#' @param seq_df Data frame from \code{\link{read_sequence_table}}, or any data
#'   frame with \code{sequence} (or \code{length}) and \code{abundance} columns.
#' @param barcode_term Character string identifying the barcode marker (e.g.,
#'   \code{"12S"}, \code{"COI"}, \code{"MiFish"}). Used to auto-detect length
#'   bounds. Ignored if both \code{min_length} and \code{max_length} are
#'   specified. Default \code{NULL}.
#' @param min_length Minimum sequence length in base pairs. Overrides
#'   \code{barcode_term} default. Default \code{NULL}.
#' @param max_length Maximum sequence length in base pairs. Overrides
#'   \code{barcode_term} default. Default \code{NULL}.
#' @param min_abundance Minimum total read count to retain a sequence.
#'   Sequences with fewer reads are removed. Default \code{2} (removes
#'   singletons).
#'
#' @return A filtered data frame (same structure as input). A message reports
#'   how many sequences were removed and why. An \code{attr(out,
#'   "report_params")} list (\code{min_length}, \code{max_length},
#'   \code{min_abundance}, \code{n_retained}) is also attached, mirroring
#'   \code{blast_sequences()}'s own \code{report_params} attribute, so
#'   downstream reporting functions can incorporate the filtering
#'   parameters into automated methods text.
#'
#' @details
#' Singletons (sequences observed only once across all samples) are commonly
#' removed in eDNA workflows because they are enriched for PCR/sequencing
#' errors. The default \code{min_abundance = 2} removes these. When
#' \code{seq_df} has no \code{abundance} column, abundance filtering is
#' silently skipped with a \code{message()} (not a warning or error).
#'
#' When \code{barcode_term} is supplied, length bounds are resolved from an
#' internal lookup table covering common eDNA markers (12S, 16S, COI, ITS,
#' etc.). These are intentionally broad ranges that exclude obvious non-target
#' amplicons while retaining genuine length variation.
#'
#' The length filter operates on \code{seq_df$length} if present, computing
#' it from \code{seq_df$sequence} otherwise. If \code{length} was
#' pre-computed by an upstream step from a different string (e.g. a
#' provider's reported length that includes alignment gaps), the filter is
#' applied to that value, not to \code{nchar(sequence)} -- verify the two
#' agree when using a provider-supplied data frame directly (not one
#' produced by \code{read_sequence_table()}, which always derives
#' \code{length} from \code{sequence} itself).
#'
#' @examples
#' \dontrun{
#' filtered <- filter_sequences(seq_df,
#'   barcode_term = "MiFishU",
#'   min_abundance = 2
#' )
#' }
#'
#' @export
filter_sequences <- function(seq_df,
                             barcode_term = NULL,
                             min_length = NULL,
                             max_length = NULL,
                             min_abundance = 2L) {
  # --- Input validation -------------------------------------------------------
  if (!is.data.frame(seq_df)) {
    stop("seq_df must be a data frame")
  }
  if (!is.null(min_abundance) &&
    (!is.numeric(min_abundance) || length(min_abundance) != 1L || is.na(min_abundance))) {
    stop("min_abundance must be a single numeric value or NULL")
  }

  # Guard against NA sequences before nchar() is called
  if ("sequence" %in% names(seq_df)) {
    na_seq <- is.na(seq_df$sequence)
    if (any(na_seq)) {
      warning(sprintf("filter_sequences: %d row(s) have NA sequences; removing.", sum(na_seq)))
      seq_df <- seq_df[!na_seq, , drop = FALSE]
    }
  }

  # Derive length if not present
  if (!"length" %in% names(seq_df)) {
    if ("sequence" %in% names(seq_df)) {
      seq_df$length <- nchar(seq_df$sequence)
    } else {
      stop("seq_df must contain a 'length' or 'sequence' column")
    }
  }

  n_start <- nrow(seq_df)

  # --- Length filtering -------------------------------------------------------
  do_length <- !is.null(barcode_term) || !is.null(min_length) || !is.null(max_length)
  len_range <- NULL

  if (do_length) {
    len_range <- TaxaTools::resolve_barcode_lengths(barcode_term, min_length, max_length)
    keep_len <- seq_df$length >= len_range[1L] & seq_df$length <= len_range[2L]
    n_len_removed <- sum(!keep_len)
    seq_df <- seq_df[keep_len, ]
  } else {
    n_len_removed <- 0L
  }

  # --- Abundance filtering ----------------------------------------------------
  if (!is.null(min_abundance) && "abundance" %in% names(seq_df)) {
    keep_abund <- seq_df$abundance >= min_abundance
    n_abund_removed <- sum(!keep_abund)
    seq_df <- seq_df[keep_abund, ]
  } else {
    n_abund_removed <- 0L
    if (!is.null(min_abundance) && !"abundance" %in% names(seq_df)) {
      message("No 'abundance' column found; abundance filtering skipped.")
    }
  }

  # --- Report -----------------------------------------------------------------
  n_end <- nrow(seq_df)
  parts <- character(0L)
  if (n_len_removed > 0L) {
    parts <- c(parts, sprintf(
      "%d outside length range %d-%d bp",
      n_len_removed, len_range[1L], len_range[2L]
    ))
  }
  if (n_abund_removed > 0L) {
    parts <- c(parts, sprintf(
      "%d below min abundance %d",
      n_abund_removed, as.integer(min_abundance)
    ))
  }

  if (length(parts) > 0L) {
    message(sprintf(
      "Filtered %d of %d sequences: %s. %d retained.",
      n_start - n_end, n_start, paste(parts, collapse = "; "), n_end
    ))
  } else {
    message(sprintf("No sequences filtered. All %d retained.", n_end))
  }

  rownames(seq_df) <- NULL

  # Mirrors blast_sequences()'s report_params attribute, letting a future
  # report_filter() (or report_match()) incorporate filtering parameters
  # into automated methods text.
  attr(seq_df, "report_params") <- list(
    min_length    = if (!is.null(len_range)) len_range[1L] else NULL,
    max_length    = if (!is.null(len_range)) len_range[2L] else NULL,
    min_abundance = min_abundance,
    n_retained    = n_end
  )

  seq_df
}

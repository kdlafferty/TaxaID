utils::globalVariables(c("abundance", "length"))

# ==============================================================================
# read_sequence_table() — Ingest DADA2 sequence table or FASTA file
# ==============================================================================

#' Read Sequence Data into a Tidy ASV Table
#'
#' Converts a DADA2 sequence table (matrix), a FASTA file, or a data frame
#' (e.g., from a sequencing provider's CSV) into a tidy data frame with one
#' row per unique sequence.
#'
#' @param data One of:
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
#'   DNA sequences. Default \code{"sequence"}.
#' @param observation_id_col For data frame input: name of an existing observation/ESV
#'   identifier column to use as \code{asv_id}. If \code{NULL} (default),
#'   sequential IDs are generated using \code{id_prefix}.
#' @param abundance_cols For data frame input: character vector of column names
#'   containing per-sample read counts to sum for total abundance. If
#'   \code{NULL} (default), numeric columns that are not taxonomy or metadata
#'   are auto-detected. If no abundance columns are found, abundance is set
#'   to 1 per row.
#' @param taxonomy Optional data frame with taxonomy for each sequence. Must
#'   contain a column matching sequences (for DADA2 input) or sequence
#'   identifiers (for FASTA input). See Details. Ignored for data frame input
#'   (taxonomy columns are retained directly).
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
#'
#' @details
#' **DADA2 input:** The standard DADA2 sequence table is a matrix where rows are
#' samples, columns are ASV sequences (the column names are the literal DNA
#' strings), and cells are integer read counts. \code{read_sequence_table()}
#' collapses across samples to get total abundance per unique sequence.
#'
#' **FASTA input:** Accepts a file path (extensions .fasta, .fa, .fna, .fas) or
#' a \code{Biostrings::DNAStringSet} object. Abundance is set to 1 per sequence
#' unless the header contains abundance information (e.g., \code{;size=42}).
#'
#' **Data frame input:** Accepts any data frame with a column containing DNA
#' sequences. Common sources include Jonah Ventures tab+taxa CSV files, or any
#' provider's ESV/ASV table. Abundance is computed by summing across
#' \code{abundance_cols}. If not specified, the function auto-detects numeric
#' columns that are not standard taxonomy or metadata columns. Taxonomy columns
#' (kingdom, phylum, class, order, family, genus, species) and other non-numeric
#' columns are retained in the output.
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
read_sequence_table <- function(data,
                                sequence_col = "sequence",
                                observation_id_col = NULL,
                                abundance_cols = NULL,
                                taxonomy = NULL,
                                header_format = "none",
                                id_prefix = "ASV") {
  # --- Input validation -------------------------------------------------------
  if (!is.character(id_prefix) || length(id_prefix) != 1L || is.na(id_prefix))
    stop("id_prefix must be a single non-NA character string")
  if (!is.character(header_format) || length(header_format) != 1L)
    stop("header_format must be a single character string")
  header_format <- match.arg(header_format, c("none", "semicolon"))
  if (!is.null(taxonomy) && !is.data.frame(taxonomy))
    stop("taxonomy must be a data frame or NULL")

  # --- Dispatch by input type -------------------------------------------------
  if (is.data.frame(data)) {
    result <- .read_esv_dataframe(data, sequence_col, observation_id_col,
                                  abundance_cols, id_prefix)
  } else if (is.matrix(data)) {
    result <- .read_dada2_matrix(data, id_prefix)
  } else if (is.character(data) && length(data) == 1L && !is.na(data)) {
    result <- .read_fasta_file(data, header_format, id_prefix)
  } else if (inherits(data, "DNAStringSet")) {
    result <- .read_dna_stringset(data, header_format, id_prefix)
  } else {
    stop(
      "data must be a data frame, a DADA2 sequence table (matrix), ",
      "a path to a FASTA file, or a Biostrings::DNAStringSet object"
    )
  }

  # --- Join external taxonomy if supplied (non-df inputs only) ----------------
  if (!is.null(taxonomy) && !is.data.frame(data)) {
    result <- .join_taxonomy(result, taxonomy)
  }

  result
}


# --- Internal: Data frame (ESV table from provider) ---------------------------

.read_esv_dataframe <- function(df, sequence_col, observation_id_col,
                                abundance_cols, id_prefix) {
  # Lowercase column names for matching
  orig_names <- names(df)
  lc_names   <- tolower(orig_names)

  # Find sequence column
  seq_idx <- match(tolower(sequence_col), lc_names)
  if (is.na(seq_idx))
    stop(sprintf("Column '%s' not found in data frame", sequence_col))
  sequences <- as.character(df[[seq_idx]])

  # Find or generate ASV IDs
  if (!is.null(observation_id_col)) {
    id_idx <- match(tolower(observation_id_col), lc_names)
    if (is.na(id_idx))
      stop(sprintf("Column '%s' not found in data frame", observation_id_col))
    asv_ids <- as.character(df[[id_idx]])
  } else {
    n <- nrow(df)
    pad <- nchar(as.character(n))
    asv_ids <- sprintf("%s_%0*d", id_prefix, pad, seq_len(n))
  }

  # Determine abundance columns
  # Known non-abundance columns: taxonomy, metadata, sequence, IDs, scores
  non_abundance_names <- c(
    TaxaTools::standard_ranks,
    "sequence", "esv", "asv", "asv_id", "esv_id", "observation_id", "accession",
    "identifier", "pctmatch", "percmatch", "score", "numspp", "testid",
    "taxon_name", "taxon_name_rank"
  )

  if (!is.null(abundance_cols)) {
    # User-specified abundance columns
    abund_idx <- match(tolower(abundance_cols), lc_names)
    missing <- abundance_cols[is.na(abund_idx)]
    if (length(missing) > 0L)
      stop(sprintf("Abundance columns not found: %s", paste(missing, collapse = ", ")))
    abund_idx <- abund_idx[!is.na(abund_idx)]
  } else {
    # Auto-detect: numeric columns not in the known non-abundance set
    abund_idx <- which(
      vapply(df, is.numeric, logical(1L)) &
        !lc_names %in% non_abundance_names &
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
    abundances <- as.integer(rowSums(df[, abund_idx, drop = FALSE], na.rm = TRUE))
    message(sprintf("Summed abundance across %d sample columns", length(abund_idx)))
  } else {
    abundances <- rep(1L, nrow(df))
    message("No abundance columns detected. Setting abundance = 1 per row.")
  }

  # Build core output
  result <- data.frame(
    asv_id    = asv_ids,
    sequence  = sequences,
    length    = nchar(sequences),
    abundance = abundances,
    stringsAsFactors = FALSE
  )

  # Retain taxonomy and other metadata columns (exclude sequence, ID, abundance)
  exclude_idx <- c(seq_idx, abund_idx)
  if (!is.null(observation_id_col)) {
    exclude_idx <- c(exclude_idx, match(tolower(observation_id_col), lc_names))
  }
  keep_idx <- setdiff(seq_along(orig_names), exclude_idx)

  if (length(keep_idx) > 0L) {
    extra <- df[, keep_idx, drop = FALSE]
    # Lowercase the retained column names for consistency
    names(extra) <- tolower(names(extra))
    result <- cbind(result, extra)
  }

  result
}


# --- Internal: DADA2 matrix ---------------------------------------------------

.read_dada2_matrix <- function(mat, id_prefix) {
  if (is.null(colnames(mat)))
    stop("DADA2 sequence table must have DNA sequences as column names")

  sequences <- colnames(mat)
  abundances <- as.integer(colSums(mat))

  n <- length(sequences)
  pad <- nchar(as.character(n))

  data.frame(
    asv_id    = sprintf("%s_%0*d", id_prefix, pad, seq_len(n)),
    sequence  = sequences,
    length    = nchar(sequences),
    abundance = abundances,
    stringsAsFactors = FALSE
  )
}


# --- Internal: FASTA file path ------------------------------------------------

.read_fasta_file <- function(path, header_format, id_prefix) {
  if (!file.exists(path))
    stop(sprintf("FASTA file not found: %s", path))

  if (!requireNamespace("Biostrings", quietly = TRUE))
    stop(
      "Package 'Biostrings' is required to read FASTA files. ",
      "Install with: BiocManager::install('Biostrings')"
    )

  dna <- Biostrings::readDNAStringSet(path)
  .read_dna_stringset(dna, header_format, id_prefix)
}


# --- Internal: DNAStringSet object --------------------------------------------

.read_dna_stringset <- function(dna, header_format, id_prefix) {
  sequences <- as.character(dna)
  headers   <- names(dna)
  n <- length(sequences)
  pad <- nchar(as.character(n))

  # Try to extract abundance from headers (e.g., ";size=42")
  abundances <- vapply(headers, function(h) {
    m <- regexpr(";size=(\\d+)", h)
    if (m == -1L) return(1L)
    val <- suppressWarnings(as.integer(sub(";size=", "", regmatches(h, m))))
    if (is.na(val)) {
      warning(sprintf("Malformed ;size= value in header: %s. Using abundance = 1.", h))
      return(1L)
    }
    val
  }, integer(1L), USE.NAMES = FALSE)

  result <- data.frame(
    asv_id    = sprintf("%s_%0*d", id_prefix, pad, seq_len(n)),
    sequence  = sequences,
    length    = nchar(sequences),
    abundance = abundances,
    stringsAsFactors = FALSE
  )

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

  mat <- do.call(rbind, lapply(parts, function(p) {
    # Pad short headers with NA
    out <- rep(NA_character_, 1L + n_ranks)
    out[seq_along(p[seq_len(1L + n_ranks)])] <- p[seq_len(min(length(p), 1L + n_ranks))]
    out
  }))

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  colnames(df) <- c("accession", rank_names[seq_len(n_ranks)])

  # Clean empty strings to NA
  df[] <- lapply(df, function(col) ifelse(trimws(col) == "", NA_character_, trimws(col)))

  df
}


# --- Internal: join external taxonomy to sequence table -----------------------

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

  # Restore original row order by asv_id
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
#'   how many sequences were removed and why.
#'
#' @details
#' Singletons (sequences observed only once across all samples) are commonly
#' removed in eDNA workflows because they are enriched for PCR/sequencing
#' errors. The default \code{min_abundance = 2} removes these.
#'
#' When \code{barcode_term} is supplied, length bounds are resolved from an
#' internal lookup table covering common eDNA markers (12S, 16S, COI, ITS,
#' etc.). These are intentionally broad ranges that exclude obvious non-target
#' amplicons while retaining genuine length variation.
#'
#' @examples
#' \dontrun{
#' filtered <- filter_sequences(seq_df, barcode_term = "MiFishU",
#'                              min_abundance = 2)
#' }
#'
#' @export
filter_sequences <- function(seq_df,
                             barcode_term = NULL,
                             min_length = NULL,
                             max_length = NULL,
                             min_abundance = 2L) {
  # --- Input validation -------------------------------------------------------
  if (!is.data.frame(seq_df))
    stop("seq_df must be a data frame")
  if (!is.null(min_abundance) &&
      (!is.numeric(min_abundance) || length(min_abundance) != 1L || is.na(min_abundance)))
    stop("min_abundance must be a single numeric value or NULL")

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
  }

  # --- Report -----------------------------------------------------------------
  n_end <- nrow(seq_df)
  parts <- character(0L)
  if (n_len_removed > 0L)
    parts <- c(parts, sprintf("%d outside length range %d-%d bp",
                              n_len_removed, len_range[1L], len_range[2L]))
  if (n_abund_removed > 0L)
    parts <- c(parts, sprintf("%d below min abundance %d",
                              n_abund_removed, as.integer(min_abundance)))

  if (length(parts) > 0L) {
    message(sprintf(
      "Filtered %d of %d sequences: %s. %d retained.",
      n_start - n_end, n_start, paste(parts, collapse = "; "), n_end
    ))
  } else {
    message(sprintf("No sequences filtered. All %d retained.", n_end))
  }

  rownames(seq_df) <- NULL
  seq_df
}



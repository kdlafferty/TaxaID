# ==============================================================================
# read_crabs_output() -- Load a CRABS internal-format reference database
# ==============================================================================

#' Read a CRABS-formatted reference database
#'
#' Reads the internal output format produced by CRABS (Creating Reference
#' databases for Amplicon-Based Sequencing; Jeunen et al. 2023), a
#' widely-used eDNA reference database builder. CRABS outputs a single
#' tab-delimited file with no header row and 11 fixed columns, with missing
#' ranks represented as the literal string \code{"NA"}.
#'
#' @section CRABS column format:
#' CRABS internal format is a headerless tab-delimited file with exactly 11
#' columns in this fixed order:
#' \preformatted{
#'   accession | taxid_string | ncbi_tax_number | kingdom | phylum | class |
#'   order | family | genus | species | sequence
#' }
#' Generate this file with \code{crabs db_download}, \code{crabs db_import},
#' and \code{crabs db_merge}.
#'
#' @section Complementary role with TaxaLikely quality tools:
#' CRABS handles efficient sequence retrieval and bulk quality filters at the
#' database-building stage (e.g., length range, primer trimming, taxonomic
#' scope, exact dereplication). TaxaLikely catches mislabeling errors that
#' CRABS cannot detect: sequences where the taxonomic label is wrong but the
#' sequence is otherwise valid.  These errors inflate within-species distance
#' estimates and produce unreliable likelihoods.  After loading a CRABS
#' database with this function, run [flag_reference_errors()] on the output
#' of [build_sequence_matrix()] to identify and remove them before training
#' the likelihood model.
#'
#' @param file Character scalar. Path to the CRABS internal-format file.
#' @param rank_system Character vector of ranks to include, \strong{coarse to
#'   fine} (e.g., \code{c("family", "genus", "species")}). Must be a subset
#'   of the seven CRABS taxonomy columns: \code{kingdom}, \code{phylum},
#'   \code{class}, \code{order}, \code{family}, \code{genus}, \code{species}.
#'   Default \code{NULL} auto-detects from the file: all columns that have at
#'   least one non-\code{NA} value are included.  For likelihood model
#'   training, \code{c("family", "genus", "species")} is typically sufficient.
#' @param max_n_bases Integer or \code{NULL} (default \code{NULL}). Drop
#'   sequences longer than this many bases.  Useful for removing chimeric or
#'   incorrectly-assembled entries that CRABS length filters may have missed.
#'   \code{NULL} retains all lengths.
#' @param require_species Logical (default \code{TRUE}). When \code{TRUE},
#'   rows with a missing or invalid species name are dropped.  Validity is
#'   checked by [TaxaTools::is_valid_species_name()], which rejects
#'   \code{sp.}, \code{cf.}, \code{aff.}, and \code{uncultured} names.  Set
#'   to \code{FALSE} to retain genus-level-only references.
#' @param dereplicate Logical (default \code{FALSE}). When \code{TRUE},
#'   exact-duplicate sequences within the same species are collapsed to one
#'   representative (first accession retained).  CRABS itself offers primer-
#'   trimmed dereplication; this option works on the raw sequence column and
#'   is a complement, not a replacement.
#'
#' @return A data frame (\code{reference_df}) with columns:
#' \describe{
#'   \item{\code{composite_id}}{Accession string (version suffix stripped).}
#'   \item{rank columns}{One column per rank in \code{rank_system}.}
#'   \item{\code{sequence}}{DNA sequence string.}
#' }
#' Ready for input to [build_sequence_matrix()].
#'
#' @seealso [read_reference_fasta()] for FASTA + separate taxonomy table,
#'   [fetch_reference_sequences()] for downloading from NCBI,
#'   [build_sequence_matrix()], [flag_reference_errors()]
#'
#' @examples
#' \dontrun{
#' ref <- read_crabs_output(
#'   file        = "mifish_12S_crabs.tsv",
#'   rank_system = c("family", "genus", "species"),
#'   max_n_bases = 250,
#'   dereplicate = TRUE
#' )
#'
#' # Standard TaxaLikely workflow continues here
#' ref_matrix <- build_sequence_matrix(ref)
#' errors     <- flag_reference_errors(ref_matrix)
#' clean_mat  <- remove_flagged_references(ref_matrix, errors)
#' model      <- train_likelihood_model(clean_mat)
#' }
#'
#' @export
read_crabs_output <- function(file,
                              rank_system     = NULL,
                              max_n_bases     = NULL,
                              require_species = TRUE,
                              dereplicate     = FALSE) {

  # --- Validate inputs --------------------------------------------------------
  if (!is.character(file) || length(file) != 1L)
    stop("file must be a single file path")
  if (!file.exists(file))
    stop(sprintf("File not found: %s", file))
  if (file.info(file)$size == 0L)
    stop(sprintf("CRABS file is empty (0 bytes): %s", file))
  if (!is.null(max_n_bases) &&
      (!is.numeric(max_n_bases) || length(max_n_bases) != 1L || max_n_bases < 1L))
    stop("max_n_bases must be a positive integer or NULL")
  if (!is.logical(require_species) || length(require_species) != 1L ||
      is.na(require_species))
    stop("require_species must be TRUE or FALSE")
  if (!is.logical(dereplicate) || length(dereplicate) != 1L || is.na(dereplicate))
    stop("dereplicate must be TRUE or FALSE")

  crabs_tax_ranks <- c("kingdom", "phylum", "class", "order",
                       "family", "genus", "species")

  if (!is.null(rank_system)) {
    rank_system <- tolower(trimws(rank_system))
    bad <- setdiff(rank_system, crabs_tax_ranks)
    if (length(bad) > 0L)
      stop(sprintf(
        "rank_system contains ranks not in CRABS format: %s\nValid ranks: %s",
        paste(bad, collapse = ", "),
        paste(crabs_tax_ranks, collapse = ", ")
      ))
  }

  # --- Read file --------------------------------------------------------------
  crabs_col_names <- c("accession", "taxid_string", "ncbi_tax_number",
                       "kingdom", "phylum", "class", "order",
                       "family", "genus", "species", "sequence")

  # na.strings = character(0L): do not auto-convert; we handle literal "NA" below
  # so that we can distinguish missing taxonomy from genuinely empty fields
  df <- tryCatch(
    utils::read.table(
      file, sep = "\t", header = FALSE, col.names = crabs_col_names,
      quote = "", comment.char = "", stringsAsFactors = FALSE,
      fill = TRUE, na.strings = character(0L)
    ),
    error = function(e)
      stop(sprintf("Failed to read CRABS file '%s': %s",
                   basename(file), conditionMessage(e)))
  )

  if (nrow(df) == 0L) {
    warning(sprintf("CRABS file contained no rows: %s", basename(file)))
    return(data.frame(composite_id = character(0L), sequence = character(0L),
                      stringsAsFactors = FALSE))
  }

  message(sprintf("Read %d rows from %s", nrow(df), basename(file)))

  # Convert literal "NA" strings to NA in taxonomy columns
  for (col in crabs_tax_ranks) {
    df[[col]][df[[col]] == "NA"] <- NA_character_
  }

  # --- Auto-detect rank_system ------------------------------------------------
  if (is.null(rank_system)) {
    has_data    <- vapply(crabs_tax_ranks,
                          function(r) any(!is.na(df[[r]])), logical(1L))
    rank_system <- crabs_tax_ranks[has_data]
    if (length(rank_system) == 0L)
      stop("No taxonomy columns have non-NA values. Is this a valid CRABS file?")
    message(sprintf("Auto-detected rank_system: %s",
                    paste(rank_system, collapse = ", ")))
  }

  # --- Build composite_id (accession with version suffix stripped) ------------
  df$composite_id <- sub("\\.[0-9]+$", "", trimws(df$accession))

  # --- Drop rows with missing or empty sequence --------------------------------
  has_seq  <- !is.na(df$sequence) & nzchar(trimws(df$sequence))
  n_no_seq <- sum(!has_seq)
  if (n_no_seq > 0L) {
    message(sprintf("%d row(s) dropped: missing sequence", n_no_seq))
    df <- df[has_seq, , drop = FALSE]
  }

  if (nrow(df) == 0L) {
    warning("No rows with a valid sequence remain")
    return(data.frame(composite_id = character(0L), sequence = character(0L),
                      stringsAsFactors = FALSE))
  }

  # --- max_n_bases filter -----------------------------------------------------
  if (!is.null(max_n_bases)) {
    n_before <- nrow(df)
    df       <- df[nchar(df$sequence) <= as.integer(max_n_bases), , drop = FALSE]
    n_drop   <- n_before - nrow(df)
    if (n_drop > 0L)
      message(sprintf("%d sequence(s) dropped: > %d bases", n_drop, max_n_bases))
  }

  # --- require_species filter -------------------------------------------------
  if (require_species) {
    n_before <- nrow(df)
    keep     <- !is.na(df$species) & TaxaTools::is_valid_species_name(df$species)
    df       <- df[keep, , drop = FALSE]
    n_drop   <- n_before - nrow(df)
    if (n_drop > 0L)
      message(sprintf("%d row(s) dropped: invalid or missing species name", n_drop))
  }

  # --- dereplicate: collapse exact-duplicate sequences within species ----------
  if (dereplicate && nrow(df) > 0L) {
    n_before <- nrow(df)
    # Use a separator that cannot appear in a species name or DNA sequence
    dup_key  <- paste(df$species, df$sequence, sep = "|||")
    df       <- df[!duplicated(dup_key), , drop = FALSE]
    n_drop   <- n_before - nrow(df)
    if (n_drop > 0L)
      message(sprintf("%d exact duplicate sequence(s) removed within species",
                      n_drop))
  }

  if (nrow(df) == 0L) {
    warning("No sequences remained after all filters")
    return(data.frame(composite_id = character(0L), sequence = character(0L),
                      stringsAsFactors = FALSE))
  }

  # --- Assemble reference_df --------------------------------------------------
  keep_cols    <- c("composite_id", rank_system, "sequence")
  reference_df <- df[, keep_cols, drop = FALSE]
  row.names(reference_df) <- NULL

  finest_rank <- rank_system[length(rank_system)]
  n_unique    <- length(unique(stats::na.omit(reference_df[[finest_rank]])))
  message(sprintf("read_crabs_output: %d sequences, %d unique %s",
                  nrow(reference_df), n_unique, finest_rank))
  reference_df
}

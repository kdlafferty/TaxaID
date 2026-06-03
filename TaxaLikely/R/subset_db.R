#' Subset a Large Local Reference Database by Taxon
#'
#' Filters a large local FASTA + taxonomy file to a user-supplied taxon list,
#' returning a \code{reference_df} ready for [build_sequence_matrix()] or
#' [train_likelihood_model()].  The taxonomy file is parsed first to identify
#' matching sequence IDs; the FASTA is then streamed record-by-record, keeping
#' only those IDs.  Peak memory scales with the number of matching sequences,
#' not the total database size, making this suitable for multi-gigabyte
#' databases such as SILVA SSU, MIDORI2, or Greengenes2.
#'
#' @section Supported database formats:
#' \describe{
#'   \item{SILVA}{Download \code{SILVA_*_SSURef_NR99.fasta.gz} and the
#'     companion taxonomy TSV from \url{https://www.arb-silva.de/download/}.
#'     SILVA taxonomy strings use prefix-style (\code{d__}, \code{p__}, \ldots)
#'     and are auto-detected.  SILVA sequences span 16S/18S/23S rRNA and are
#'     the standard reference for microbial amplicon eDNA.}
#'   \item{MIDORI2}{Download the FASTA (\code{MIDORI2_UNIQ_NUC_*_QIIME.fasta})
#'     and its companion \code{_taxon.tsv} from
#'     \url{https://www.reference-midori.info/}.  MIDORI2 covers COI and a
#'     range of nuclear markers for metazoan eDNA; the full COI release is ~4 GB.}
#'   \item{GTDB}{GTDB taxonomy differs from NCBI for bacteria and archaea.
#'     Export GTDB-formatted 16S sequences + taxonomy via QIIME 2 (\code{qiime
#'     tools export}) or download pre-built QIIME2 classifiers and extract
#'     the FASTA + TSV.  GTDB taxonomy strings use \code{d__}/\code{p__}
#'     prefix-style and are auto-detected.}
#'   \item{Greengenes2}{Available as QIIME 2 artifacts from
#'     \url{http://ftp.microbio.me/greengenes_release/}.  Export the FASTA +
#'     taxonomy TSV with \code{qiime tools export} before calling this function.
#'     Greengenes2 (2022+) uses GTDB-derived taxonomy.}
#'   \item{RDP}{Download FASTA + lineage file from
#'     \url{https://rdp.cme.msu.edu/misc/resources.jsp}.  RDP lineage files
#'     are tab-delimited with a multi-column hierarchy; reformat to a 2-column
#'     (ID TAB taxonomy string) TSV before use, or load as a data frame and
#'     pass via \code{taxonomy}.}
#'   \item{CRUX or custom FASTA}{If you already have a data frame of taxonomy
#'     (e.g., from [read_reference_fasta()]), pass it via \code{taxonomy}
#'     instead of \code{taxonomy_file}.  For CRABS internal-format files use
#'     [read_crabs_output()] directly.}
#' }
#'
#' @section ID matching:
#' FASTA header IDs are extracted as the first whitespace-delimited token after
#' \code{>} (e.g., \code{AB353770.1} from \code{>AB353770.1 Bacteria;...}).
#' Version suffixes (\code{.1}, \code{.2}) are stripped from taxonomy TSV IDs
#' before matching, consistent with the behaviour of
#' \code{.parse_taxonomy_tsv()}.  If IDs still fail to match after stripping,
#' inspect the first few lines of both files for format discrepancies.
#'
#' @param fasta_path Character. Path to the FASTA file.  Plain text and
#'   \code{.gz}-compressed files are both supported.
#' @param taxa Character vector. Taxon names to retain (e.g.,
#'   \code{c("Fundulidae", "Gobiidae")} for family-level filtering, or
#'   \code{c("Fundulus", "Gambusia")} for genus-level).
#' @param rank Character scalar. The rank at which \code{taxa} are defined;
#'   must be one of the values in \code{rank_system}
#'   (e.g., \code{"genus"}, \code{"family"}).
#' @param rank_system Character vector, coarse to fine (default
#'   \code{c("family", "genus", "species")}).  Must include \code{rank}.
#' @param taxonomy_file Character or \code{NULL}. Path to a 2-column taxonomy
#'   TSV (sequence ID TAB taxonomy string) in QIIME2/RESCRIPt, SILVA, MIDORI2,
#'   or GTDB format.  Prefix-style (\code{k__}, \code{d__}) and positional
#'   semicolon formats are both auto-detected.  Exactly one of
#'   \code{taxonomy_file} or \code{taxonomy} must be supplied.
#' @param taxonomy Data frame or \code{NULL}. Pre-parsed taxonomy with a
#'   \code{composite_id} column plus one column per rank in \code{rank_system}.
#'   Exactly one of \code{taxonomy} or \code{taxonomy_file} must be supplied.
#' @param max_n_bases Integer or \code{NULL}. Drop sequences longer than this
#'   many bases after extraction (useful for removing genomic contaminants from
#'   amplicon databases).
#' @param require_species Logical (default \code{FALSE}). If \code{TRUE}, drop
#'   sequences with \code{NA} in the \code{species} column.  Requires
#'   \code{"species"} to be in \code{rank_system}.
#'
#' @return A \code{reference_df}: a data frame with columns
#'   \code{composite_id}, plus one column per rank in \code{rank_system}, plus
#'   \code{sequence}.  Ready for [build_sequence_matrix()] or
#'   [write_reference_fasta()].
#'
#' @seealso [read_reference_fasta()] for smaller databases where loading the
#'   entire file at once is practical; [read_crabs_output()] for CRABS
#'   internal-format databases; [build_sequence_matrix()] for the next step.
#'
#' @examples
#' \dontrun{
#' # Filter a local SILVA SSU database to two fish families
#' ref <- subset_local_database(
#'   fasta_path    = "SILVA_138.1_SSURef_NR99.fasta.gz",
#'   taxa          = c("Fundulidae", "Gobiidae"),
#'   rank          = "family",
#'   rank_system   = c("family", "genus", "species"),
#'   taxonomy_file = "silva_taxonomy.tsv"
#' )
#'
#' # Filter MIDORI2 COI to a genus; drop sequences > 700 bp
#' ref <- subset_local_database(
#'   fasta_path    = "MIDORI2_UNIQ_NUC_GB260_COI_QIIME.fasta",
#'   taxa          = "Thunnus",
#'   rank          = "genus",
#'   rank_system   = c("family", "genus", "species"),
#'   taxonomy_file = "MIDORI2_UNIQ_NUC_GB260_COI_QIIME_taxon.tsv",
#'   max_n_bases   = 700L,
#'   require_species = TRUE
#' )
#'
#' # Use a pre-parsed taxonomy data frame (e.g., from a custom database)
#' ref <- subset_local_database(
#'   fasta_path  = "custom_db.fasta",
#'   taxa        = c("Salmo", "Oncorhynchus"),
#'   rank        = "genus",
#'   rank_system = c("family", "genus", "species"),
#'   taxonomy    = my_tax_df   # must have composite_id + rank columns
#' )
#'
#' # Continue with the standard workflow
#' ref_matrix <- build_sequence_matrix(ref)
#' model      <- train_likelihood_model(ref_matrix)
#' }
#'
#' @export
subset_local_database <- function(fasta_path,
                                   taxa,
                                   rank,
                                   rank_system     = c("family", "genus", "species"),
                                   taxonomy_file   = NULL,
                                   taxonomy        = NULL,
                                   max_n_bases     = NULL,
                                   require_species = FALSE) {

  # ---- Input validation -------------------------------------------------------

  if (!is.character(fasta_path) || length(fasta_path) != 1L || !nzchar(fasta_path))
    stop("fasta_path must be a single non-empty file path.", call. = FALSE)
  if (!file.exists(fasta_path))
    stop(sprintf("fasta_path not found: %s", fasta_path), call. = FALSE)
  if (!is.character(taxa) || length(taxa) == 0L)
    stop("taxa must be a non-empty character vector.", call. = FALSE)
  if (!is.character(rank) || length(rank) != 1L || !nzchar(rank))
    stop("rank must be a single non-empty character scalar.", call. = FALSE)
  if (!rank %in% rank_system)
    stop(sprintf("rank '%s' is not in rank_system (%s).",
                 rank, paste(rank_system, collapse = ", ")), call. = FALSE)
  if (!xor(is.null(taxonomy_file), is.null(taxonomy)))
    stop("Supply exactly one of taxonomy_file or taxonomy (not both, not neither).",
         call. = FALSE)
  if (!is.null(max_n_bases)) {
    if (!is.numeric(max_n_bases) || length(max_n_bases) != 1L || is.na(max_n_bases))
      stop("max_n_bases must be a single numeric value or NULL.", call. = FALSE)
  }
  if (!is.logical(require_species) || length(require_species) != 1L ||
      is.na(require_species))
    stop("require_species must be TRUE or FALSE.", call. = FALSE)
  if (isTRUE(require_species) && !"species" %in% rank_system)
    stop("require_species = TRUE requires 'species' to be in rank_system.",
         call. = FALSE)

  rank_cols <- rank_system

  # ---- Parse taxonomy ---------------------------------------------------------

  if (!is.null(taxonomy_file)) {
    if (!is.character(taxonomy_file) || length(taxonomy_file) != 1L)
      stop("taxonomy_file must be a single file path.", call. = FALSE)
    if (!file.exists(taxonomy_file))
      stop(sprintf("taxonomy_file not found: %s", taxonomy_file), call. = FALSE)
    message("Parsing taxonomy file...")
    taxonomy <- .parse_taxonomy_tsv(taxonomy_file, rank_cols)
  }

  if (!is.data.frame(taxonomy))
    stop("taxonomy must be a data frame.", call. = FALSE)
  if (!"composite_id" %in% names(taxonomy))
    stop("taxonomy must contain a 'composite_id' column.", call. = FALSE)
  missing_cols <- setdiff(rank_cols, names(taxonomy))
  if (length(missing_cols) > 0L)
    stop(sprintf("taxonomy is missing rank column(s): %s.",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)

  # ---- Filter taxonomy to requested taxa --------------------------------------

  message(sprintf("Filtering taxonomy: %d unique taxon(s) at rank '%s'...",
                  length(unique(trimws(taxa))), rank))

  taxa_clean <- unique(trimws(taxa[!is.na(taxa) & nzchar(trimws(taxa))]))
  in_target  <- !is.na(taxonomy[[rank]]) & taxonomy[[rank]] %in% taxa_clean
  sub_tax    <- taxonomy[in_target, , drop = FALSE]

  if (nrow(sub_tax) == 0L)
    stop(
      sprintf(
        "No taxonomy entries matched %d taxon(s) at rank '%s'. ",
        length(taxa_clean), rank
      ),
      "Check taxon spellings and that rank_system matches the database.",
      call. = FALSE
    )

  message(sprintf("  Matched %d taxonomy entries.", nrow(sub_tax)))

  # ---- Build O(1) lookup set from matched IDs --------------------------------

  keep_env <- new.env(hash = TRUE, parent = emptyenv(),
                      size = nrow(sub_tax) + 1L)
  for (id in sub_tax$composite_id) {
    assign(id, TRUE, envir = keep_env)
  }

  # ---- Stream FASTA -----------------------------------------------------------

  message(sprintf("Streaming FASTA: %s", basename(fasta_path)))

  is_gz <- grepl("\\.gz$", fasta_path, ignore.case = TRUE)
  con   <- if (is_gz) gzfile(fasta_path, open = "r") else file(fasta_path, open = "r")
  on.exit(close(con), add = TRUE)

  # Collect matching records in a list (avoids O(n^2) vector growing)
  records       <- list()
  current_id    <- NULL
  current_seq   <- character(0L)
  in_target_seq <- FALSE
  chunk_size    <- 5000L

  .save_record <- function() {
    if (!in_target_seq || is.null(current_id)) return()
    seq <- paste(current_seq, collapse = "")
    if (!is.null(max_n_bases) && nchar(seq) > max_n_bases) return()
    records[[length(records) + 1L]] <<- list(
      composite_id = current_id,
      sequence     = seq
    )
  }

  while (length(lines <- readLines(con, n = chunk_size, warn = FALSE)) > 0L) {
    for (line in lines) {
      if (startsWith(line, ">")) {
        .save_record()
        header        <- sub("^>", "", line)
        current_id    <- strsplit(header, "\\s+", perl = TRUE)[[1L]][1L]
        in_target_seq <- exists(current_id, envir = keep_env, inherits = FALSE)
        current_seq   <- character(0L)
      } else if (in_target_seq) {
        current_seq <- c(current_seq, trimws(line))
      }
    }
  }
  .save_record()  # flush last record

  n_extracted <- length(records)
  message(sprintf("  Extracted %d sequence(s).", n_extracted))

  if (n_extracted == 0L) {
    warning(
      "No sequences extracted. Verify that FASTA header IDs match ",
      "the composite_id values in the taxonomy file.",
      call. = FALSE
    )
    empty <- data.frame(composite_id = character(0L),
                         stringsAsFactors = FALSE)
    for (rc in rank_cols) empty[[rc]] <- character(0L)
    empty$sequence <- character(0L)
    return(empty)
  }

  # ---- Assemble and join -------------------------------------------------------

  seq_df <- data.frame(
    composite_id = vapply(records, `[[`, character(1L), "composite_id"),
    sequence     = vapply(records, `[[`, character(1L), "sequence"),
    stringsAsFactors = FALSE
  )

  keep_cols <- intersect(c("composite_id", rank_cols), names(sub_tax))
  result    <- merge(seq_df, sub_tax[, keep_cols, drop = FALSE],
                     by = "composite_id", all.x = TRUE, sort = FALSE)

  # Canonical column order: composite_id, ranks (coarse→fine), sequence
  col_order <- c("composite_id", rank_cols, "sequence")
  result    <- result[, col_order[col_order %in% names(result)], drop = FALSE]
  row.names(result) <- NULL

  # ---- Optional post-filters --------------------------------------------------

  if (isTRUE(require_species)) {
    n_before <- nrow(result)
    result   <- result[!is.na(result$species), , drop = FALSE]
    n_dropped <- n_before - nrow(result)
    if (n_dropped > 0L)
      message(sprintf(
        "  require_species: dropped %d sequence(s) with no species annotation.",
        n_dropped
      ))
  }

  message(sprintf("subset_local_database: returning %d sequence(s).", nrow(result)))
  result
}

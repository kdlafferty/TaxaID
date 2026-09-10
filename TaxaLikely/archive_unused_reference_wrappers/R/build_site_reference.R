#' Build a Site-Specific DNA Reference Library
#'
#' High-level wrapper that downloads reference sequences for a list of expected
#' taxa, audits taxonomic completeness against NCBI barcodes, and exports the
#' curated reference as a FASTA file. Designed to work with a taxa list from
#' \pkg{TaxaExpect} (e.g., the plausible genera from
#' \code{estimate_kernel_priors()}'s \code{$priors} output) or any
#' user-supplied list.
#'
#' This function is the site-specific analog of a CRABS workflow:
#' \enumerate{
#'   \item \strong{Fetch} - downloads sequences from NCBI for `taxa` using
#'     [fetch_ncbi_reference_sequences()].
#'   \item \strong{Audit} - queries NCBI to identify which described species
#'     under each genus have no barcode sequences at all (truly unreferenced).
#'   \item \strong{Export} - writes a FASTA + companion taxonomy TSV to
#'     `output_dir` for use with external tools (BLAST, QIIME 2, Obitools).
#' }
#'
#' @section Reference-quality screening (2026-09-08):
#' This function no longer offers a built-in mislabel-flagging step (the
#' `flag_errors` parameter it previously had called TaxaLikely's own
#' `flag_reference_errors()`, retired this date -- see that function's
#' former documentation in `NAME_CHANGE_HISTORY.md`). Screen `$reference_df`
#' yourself before training, via `TaxaMatch::corroborate_references_locally()`
#' + `TaxaMatch::evaluate_reference_accessions()` (more precise, similar or
#' lower cost) -- see `train_likelihood_model()`'s own `@section` on this for
#' the exact pattern.
#'
#' The key output is \code{$unreferenced}: species expected at your site that
#' cannot be detected by any classifier because they have no reference barcodes
#' in NCBI. Pass this vector directly to
#' \code{TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)} to account for
#' them as ghost hypotheses in the posterior (the LLM-shortcut pipeline's own
#' parameter for exactly this shape -- a flat character vector of names, not
#' a species/genus/family data frame). For the full Bayesian pipeline instead,
#' run the vector through \code{TaxaTools::fill_higher_ranks()} first, then
#' \code{TaxaLikely::expand_unreferenced_hypotheses()}.
#'
#' @section Size warnings:
#' Reference libraries for species-rich groups (e.g., tropical invertebrates,
#' plants) can contain tens of thousands of sequences. Use `max_sequences` and
#' `max_per_species` to bound download volume. For a site with ~50 expected
#' genera and 5 sequences per species, 500--2000 sequences is typical.
#'
#' @param taxa Character vector of taxon names (species, genera, families, or
#'   orders). These are the taxa expected at your site; each is searched
#'   individually in NCBI nucleotide.
#' @param barcode_term Character scalar or vector of marker/primer names
#'   (e.g., \code{"MiFishU"}, \code{c("COI", "Co1")}).
#' @param rank_system Character vector of taxonomy ranks, coarse to fine.
#'   Default \code{c("family", "genus", "species")}.
#' @param output_dir Character or \code{NULL}. If provided, write
#'   \code{reference.fasta} and \code{reference_taxonomy.tsv} to this
#'   directory. The directory is created if it does not exist.
#' @param audit_coverage Logical (default \code{TRUE}). Query NCBI to identify
#'   described species with no barcode sequences (truly unreferenced taxa)?
#'   Requires internet access and takes ~0.3 s per genus.
#' @param max_sequences Integer (default \code{5000L}). Safety limit on total
#'   sequences downloaded. Sequences are subsampled proportionally across taxa
#'   when the total exceeds this.
#' @param max_per_species Integer or \code{NULL} (default \code{5L}). Maximum
#'   sequences per species (stratified downsampling).
#' @param species_list Character vector or \code{NULL}. Additional species names
#'   to include in the coverage audit (e.g., species from TaxaExpect priors not
#'   captured by genus-level `taxa`). Passed to [audit_barcode_coverage()].
#' @param max_date Character or \code{NULL} (e.g., \code{"2024/12/31"}).
#'   Restricts NCBI queries to sequences deposited on or before this date.
#'   Use to match the state of GenBank when your study was conducted.
#' @param ncbi_api_key Character or \code{NULL}. NCBI API key (increases rate
#'   limit from 3 to 10 requests/s). Also read from the \code{ENTREZ_KEY}
#'   environment variable.
#' @param cache_dir Character path (default \code{tempdir()}). Per-taxon
#'   downloads are cached here, enabling resumable fetching across sessions.
#'   Set to a persistent path for cross-session caching.
#'
#' @return A named list with components:
#' \describe{
#'   \item{\code{$reference_df}}{Data frame of downloaded reference sequences.
#'     Columns: `composite_id`, `sequence`, plus taxonomy columns from
#'     `rank_system`. Ready for [build_sequence_matrix()] or
#'     [train_likelihood_model()] (screen for reference-quality issues first --
#'     see the "Reference-quality screening" section above).}
#'   \item{\code{$census}}{Data frame from [audit_barcode_coverage()] if
#'     \code{audit_coverage = TRUE}: one row per genus with columns
#'     `group`, `total`, `in_reference`, `has_seqs_not_in_ref`,
#'     `unreferenced`, `is_complete`.}
#'   \item{\code{$unreferenced}}{Character vector of species names with no
#'     barcode sequences in NCBI (from [audit_barcode_coverage()]), or
#'     \code{character(0)} if audit was skipped. Pass directly to
#'     \code{TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)}.}
#' }
#' If \code{output_dir} is specified, \code{reference.fasta} and
#' \code{reference_taxonomy.tsv} are written there.
#'
#' @seealso [fetch_ncbi_reference_sequences()], [write_reference_fasta()],
#'   [audit_barcode_coverage()], [build_sequence_matrix()],
#'   [train_likelihood_model()]
#'
#' @examples
#' \dontrun{
#' # Taxa list from TaxaExpect (genera expected at your site)
#' site_genera <- c("Fundulus", "Gambusia", "Lepomis", "Micropterus")
#'
#' lib <- build_site_reference(
#'   taxa = site_genera,
#'   barcode_term = "MiFishU",
#'   output_dir = "site_reference/",
#'   max_date = "2024/12/31"
#' )
#'
#' # Inspect coverage gaps
#' lib$census
#' lib$unreferenced # species with NO barcode in NCBI
#'
#' # Pass unreferenced species to the LLM-shortcut pipeline directly
#' llm_posteriors <- TaxaAssign::assign_taxa_llm(
#'   match_df          = match_data,
#'   unreferenced_taxa = lib$unreferenced
#' )
#'
#' # Train model on the downloaded reference
#' ref_matrix <- build_sequence_matrix(lib$reference_df,
#'   rank_system = c("family", "genus", "species")
#' )
#' model <- train_likelihood_model(ref_matrix)
#' }
#'
#' @export
build_site_reference <- function(taxa,
                                 barcode_term,
                                 rank_system = c("family", "genus", "species"),
                                 output_dir = NULL,
                                 audit_coverage = TRUE,
                                 max_sequences = 5000L,
                                 max_per_species = 5L,
                                 species_list = NULL,
                                 max_date = NULL,
                                 ncbi_api_key = NULL,
                                 cache_dir = tempdir()) {
  # ---- Input validation -------------------------------------------------------

  if (!is.character(taxa) || length(taxa) == 0L) {
    stop("taxa must be a non-empty character vector.", call. = FALSE)
  }
  if (!is.character(barcode_term) || length(barcode_term) == 0L) {
    stop("barcode_term must be a non-empty character vector.", call. = FALSE)
  }
  if (!is.null(output_dir)) {
    if (!is.character(output_dir) || length(output_dir) != 1L || !nzchar(output_dir)) {
      stop("output_dir must be a single non-empty character path.", call. = FALSE)
    }
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  }

  message(sprintf(
    "Building site reference: %d taxon(s), marker '%s'",
    length(taxa), paste(barcode_term, collapse = "/")
  ))

  # ---- Step 1: Fetch reference sequences -------------------------------------

  message("Step 1/2: Fetching reference sequences from NCBI...")
  reference_df <- fetch_ncbi_reference_sequences(
    taxa            = taxa,
    barcode_term    = barcode_term,
    rank_system     = rank_system,
    max_per_species = max_per_species,
    max_sequences   = max_sequences,
    max_date        = max_date,
    ncbi_api_key    = ncbi_api_key,
    cache_dir       = cache_dir
  )

  if (nrow(reference_df) == 0L) {
    stop(
      "No sequences downloaded. Check taxon names, barcode_term, and NCBI connectivity.",
      call. = FALSE
    )
  }

  message(sprintf(
    "  Downloaded %d sequences for %d unique species.",
    nrow(reference_df),
    length(unique(stats::na.omit(reference_df$species)))
  ))

  # ---- Step 2: Audit coverage -------------------------------------------------

  census <- data.frame(stringsAsFactors = FALSE)
  unreferenced <- character(0L)

  if (isTRUE(audit_coverage)) {
    message("Step 2/2: Auditing barcode coverage in NCBI...")
    if (!"genus" %in% names(reference_df)) {
      warning("Column 'genus' not found in reference_df; coverage audit skipped.",
        call. = FALSE
      )
    } else {
      cov_result <- audit_barcode_coverage(
        match_df     = reference_df,
        barcode_term = barcode_term,
        species_list = species_list,
        max_date     = max_date,
        ncbi_api_key = ncbi_api_key
      )
      census <- cov_result$census
      unreferenced <- cov_result$unreferenced
      message(sprintf(
        "  %d species unreferenced (no barcode in NCBI) across %d genus(es).",
        length(unreferenced),
        nrow(census)
      ))
    }
  } else {
    message("Step 2/2: Skipping coverage audit (audit_coverage = FALSE).")
  }

  # ---- Export ----------------------------------------------------------------

  if (!is.null(output_dir)) {
    fasta_path <- file.path(output_dir, "reference.fasta")
    tsv_path <- file.path(output_dir, "reference_taxonomy.tsv")
    write_reference_fasta(reference_df,
      file = fasta_path,
      taxonomy_file = tsv_path,
      rank_system = rank_system
    )
    message(sprintf("Saved reference library to: %s", output_dir))
  }

  # ---- Return ----------------------------------------------------------------

  list(
    reference_df = reference_df,
    census       = census,
    unreferenced = unreferenced
  )
}

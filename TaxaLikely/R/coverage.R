utils::globalVariables(c(
  "group", "total", "in_reference", "has_seqs_not_in_ref", "has_predicted_only",
  "unreferenced", "is_complete",
  "constraint_applied", "is_forbidden", "join_name", "join_rank", "join_status",
  "score_likelihood", "score_likelihood_mean"
))

# Internal helper: normalise species strings to "Genus species" (first 2 words)
.first_two_words <- function(x) {
  vapply(strsplit(trimws(x), "\\s+"), function(w) {
    paste(w[seq_len(min(2L, length(w)))], collapse = " ")
  }, character(1L))
}

# Internal helper: build deterministic checkpoint path for audit_barcode_coverage()
# Signature encodes genera (count + sum of nchar), barcode_term, len_range, max_date,
# and target_rank so that changed parameters start fresh without collisions.
#' @noRd
.coverage_checkpoint_path <- function(genera, barcode_term, len_range,
                                       max_date, target_rank, cache_dir) {
  safe_bc  <- gsub("[^A-Za-z0-9]", "_", paste(barcode_term, collapse = "_"))
  date_sfx <- gsub("[^0-9A-Za-z]", "", if (is.null(max_date)) "X" else max_date)
  n_gen    <- length(genera)
  gen_sum  <- sum(nchar(genera))
  # _v2: records now include has_predicted_only / predicted_only_names fields;
  # old checkpoints (v1) are incompatible and will be ignored automatically.
  file.path(cache_dir,
            sprintf("coverage_%s_%s_d%s_n%d_s%d_l%d_%d_v2_ckpt.rds",
                    target_rank, safe_bc, date_sfx,
                    n_gen, gen_sum,
                    len_range[1L], len_range[2L]))
}


# ==============================================================================
# MODULE G: REFERENCE COVERAGE AUDIT
# ==============================================================================

#' Audit reference database taxonomic completeness via NCBI taxonomy
#'
#' For each group at `target_rank` (e.g., each genus) in the reference
#' database, queries the NCBI taxonomy database to count how many accepted
#' species exist, then compares with the species present in your reference.
#' Returns a census summary and a vector of unreferenced species -- taxa known to
#' exist at NCBI but absent from your reference.
#'
#' Unreferenced species inform the H2 (unreferenced species) hypothesis: genera
#' with many unreferenced species have higher H2 probability mass.  Fully-sampled
#' genera can have their H2
#' hypothesis suppressed via [apply_coverage_constraints()].
#'
#' @section Scope:
#' This function is designed for DNA sequence reference databases and queries
#' NCBI taxonomy to enumerate described species. It is not appropriate for
#' acoustic or image reference data, where coverage is determined by whether a
#' species appears in the model training set rather than in NCBI.
#' For barcode-specific coverage (checking NCBI nucleotide for sequence
#' availability), use [audit_barcode_coverage()] instead.
#'
#' @param reference_df Data frame containing at least two columns: one named
#'   `target_rank` (e.g., `"genus"`) and one named `"species"`.
#' @param target_rank Character scalar -- the rank to audit (default `"genus"`).
#'   Must be a column in `reference_df`.
#' @param ncbi_api_key Optional NCBI API key string (increases rate limit from
#'   3 to 10 requests/second).  Can also be set via the `ENTREZ_KEY`
#'   environment variable before calling this function.
#'
#' @return A named list:
#'   \describe{
#'     \item{`census`}{Data frame with one row per group: `group`, `total`
#'       (true species count per NCBI), `have` (in reference), `missing_count`,
#'       and `is_complete` (logical).}
#'     \item{`unreferenced`}{Character vector of species names present at NCBI but
#'       absent from the reference.}
#'   }
#'
#' @note Requires an internet connection and the `rentrez` package.  NCBI
#'   enforces rate limits (3 req/s without an API key; 10 req/s with one).
#'   Wrap the call in `tryCatch()` for batch processing of large databases.
#'
#' @seealso [apply_coverage_constraints()]
#'
#' @examples
#' \dontrun{
#' cov <- audit_reference_coverage(reference_df, target_rank = "genus")
#' cov$census
#' cov$unreferenced
#' }
#'
#' @importFrom dplyr bind_rows filter pull
#' @export
audit_reference_coverage <- function(reference_df,
                                     target_rank  = "genus",
                                     ncbi_api_key = NULL) {
  if (!is.data.frame(reference_df))
    stop("reference_df must be a data frame")
  names(reference_df) <- tolower(names(reference_df))
  target_rank <- tolower(target_rank)

  if (!target_rank %in% names(reference_df))
    stop(sprintf("Column '%s' not found in reference_df", target_rank))
  if (!"species" %in% names(reference_df))
    stop("Column 'species' not found in reference_df")

  groups <- unique(stats::na.omit(reference_df[[target_rank]]))
  groups <- groups[nchar(trimws(groups)) > 0L]

  if (length(groups) == 0L) {
    warning(sprintf("No valid groups found in column '%s'. Census skipped.",
                    target_rank))
    return(list(
      census = data.frame(group = character(), total = integer(),
                          have = integer(), missing_count = integer(),
                          is_complete = logical(), stringsAsFactors = FALSE),
      unreferenced = character(0L)
    ))
  }

  if (!requireNamespace("rentrez", quietly = TRUE))
    stop("Package 'rentrez' is required for audit_reference_coverage(). Install with: install.packages('rentrez')")

  if (!is.null(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  message(sprintf("Auditing %d %s group(s) against NCBI taxonomy...",
                  length(groups), target_rank))

  full_census <- vector("list", length(groups))
  names(full_census) <- groups

  for (i in seq_along(groups)) {
    grp <- groups[i]
    rec <- list(group = grp, total = NA_integer_, have = NA_integer_,
                missing_count = NA_integer_, missing_names = character(0L))

    tryCatch({
      # Step 1: resolve genus name to NCBI taxonomy UID
      # Normalise hyphens: "Pseudo-nitzschia"[Genus] returns 0 hits; space-separated works.
      uid_res <- rentrez::entrez_search(
        db   = "taxonomy",
        term = sprintf('"%s"[Genus]', gsub("-", " ", grp))
      )

      if (length(uid_res$ids) > 0L) {
        genus_uid <- uid_res$ids[1L]

        # Step 2: find all species-rank taxa in this genus's NCBI subtree
        sp_res <- rentrez::entrez_search(
          db     = "taxonomy",
          term   = sprintf("txid%s[Subtree] AND species[Rank]", genus_uid),
          retmax = 10000L
        )

        true_sp <- character(0L)
        if (length(sp_res$ids) > 0L) {
          sp_summ <- rentrez::entrez_summary(db = "taxonomy", id = sp_res$ids)
          # entrez_summary returns a single esummary or a list of them
          if (inherits(sp_summ, "esummary")) {
            true_sp <- sp_summ$scientificname
          } else {
            true_sp <- vapply(sp_summ, `[[`, character(1L), "scientificname")
          }
        }

        we_have <- reference_df |>
          dplyr::filter(.data[[target_rank]] == grp) |>
          dplyr::pull(species) |>
          unique()

        # Normalise to "Genus species" (first two words) before comparing
        clean_true <- .first_two_words(true_sp)
        clean_have <- .first_two_words(we_have)
        missing     <- setdiff(clean_true, clean_have)

        rec <- list(
          group         = grp,
          total         = length(clean_true),
          have          = length(clean_have),
          missing_count = length(missing),
          missing_names = missing
        )
      }
    }, error = function(e) NULL)

    full_census[[i]] <- rec
  }

  census_df <- dplyr::bind_rows(lapply(full_census, function(x) {
    data.frame(
      group         = x$group,
      total         = x$total,
      have          = x$have,
      missing_count = x$missing_count,
      is_complete   = !is.na(x$missing_count) && x$missing_count == 0L,
      stringsAsFactors = FALSE
    )
  }))

  all_unreferenced <- unlist(lapply(full_census, `[[`, "missing_names"))
  all_unreferenced <- all_unreferenced[!is.na(all_unreferenced) & nchar(all_unreferenced) > 0L]
  names(all_unreferenced) <- NULL

  list(census = census_df, unreferenced = all_unreferenced)
}


# ==============================================================================
# MODULE G2: BARCODE-SPECIFIC COVERAGE AUDIT
# ==============================================================================

#' Identify unreferenced species for barcode-based taxonomic assignment
#'
#' An **unreferenced species** is a described taxon that has **no barcode sequence**
#' for the target marker in any reference database.  Because TaxaMatch can
#' only return taxa that have reference sequences, an unreferenced species can never
#' appear as a named match candidate -- even if it is the true source of the
#' observed sequence.  Adding unreferenced species as explicit hypotheses allows the
#' LLM (via [TaxaAssign::assign_taxa_llm()]) to evaluate their geographic
#' plausibility alongside the named match candidates.
#'
#' **Example:** a 12S eDNA read from *Fundulus parvipinnis* (no reference
#' sequence) matches most closely to *Fundulus lima* (has reference).
#' Without unreferenced species insertion, *F. parvipinnis* can never be the top hypothesis.
#' With unreferenced species insertion, the LLM recognises that *F. parvipinnis* is the
#' native Southern California congener and ranks it above *F. lima*.
#'
#' ## Unreferenced species definition
#' For each genus represented in `match_df`, the function:
#' \enumerate{
#'   \item Retrieves all described species in the genus (from NCBI taxonomy,
#'     or from a user-supplied `species_list`).
#'   \item Removes species already in `match_df` -- these have reference
#'     sequences by definition and are skipped (skip-list optimisation).
#'   \item For each remaining species, queries NCBI nucleotide with
#'     `retmax = 0` (count only) to check whether a barcode sequence exists.
#'   \item Species with **count = 0** are unreferenced.
#'   \item Species with **count > 0** but absent from `match_df` represent a
#'     reference completeness gap (reported separately in the census).
#' }
#'
#' ## Species list completeness
#' NCBI taxonomy is the default species source but is not exhaustive: some
#' described species appear only in GBIF, FishBase, WoRMS, or other
#' authorities.  Species absent from the chosen source are also unreferenced but
#' will be missed.  Supply a more complete list via `species_list` when
#' taxonomic completeness is critical (e.g. well-studied vertebrate genera).
#'
#' @param match_df Data frame with at least a `target_rank` column (e.g.
#'   `"genus"`) and a `"species"` column.  Species present in `match_df` are
#'   treated as a **skip-list**: they have reference sequences by definition
#'   and are excluded from the barcode-count queries.
#' @param barcode_term Character scalar or vector.  One or more marker search
#'   terms (e.g. `"12S"`, `c("12S", "MiFish")`).  Multiple terms are OR-ed.
#' @param species_list Optional character vector of binomial species names.
#'   If supplied, used instead of the NCBI taxonomy query to determine which
#'   species exist in each genus.  Useful when GBIF, FishBase, or WoRMS
#'   provides more complete coverage than NCBI taxonomy for your taxon group.
#'   Invalid names (sp., cf., uncultured, etc.) are silently dropped.
#' @param min_len Integer or NULL.  Minimum sequence length (`SLEN` filter).
#'   NULL uses a barcode-specific default (see Details).
#' @param max_len Integer or NULL.  Maximum sequence length.  NULL uses the
#'   barcode-specific default.
#' @param max_date Optional character scalar.  Restricts unreferenced species detection to
#'   sequences present in NCBI on or before this date, embedded as a
#'   `[PDAT]` range in the query term.  Format: `"YYYY"`, `"YYYY/MM"`, or
#'   `"YYYY/MM/DD"`.  NULL uses the current state of GenBank.  Set this to
#'   match the build date of your reference library.
#' @param target_rank Character scalar.  Rank column in `match_df` (default
#'   `"genus"`).
#' @param cache_dir Directory for per-genus checkpoints.  Default:
#'   `tools::R_user_dir("TaxaLikely", "cache")`.  Pass `NULL` to disable
#'   checkpointing.  If a checkpoint from a previous interrupted run is found
#'   (matched by call signature), processing resumes automatically from where
#'   it stopped.  The checkpoint is deleted on clean completion.
#' @param ncbi_api_key Optional NCBI API key.  Raises the rate limit from 3
#'   to 10 requests per second.  Can also be set via `ENTREZ_KEY` environment
#'   variable (`Sys.setenv(ENTREZ_KEY = "your_key")`; confirm with
#'   `Sys.getenv("ENTREZ_KEY")`).
#'
#' @details
#' ## Length defaults by barcode
#' \describe{
#'   \item{MiFish / 12S}{100--600 bp}
#'   \item{Teleo}{50--300 bp}
#'   \item{16S}{100--700 bp}
#'   \item{COI}{300--900 bp}
#'   \item{CytB}{200--900 bp}
#'   \item{ITS2}{100--600 bp}
#'   \item{ITS}{100--900 bp}
#'   \item{rbcL}{400--800 bp}
#'   \item{matK}{600--1100 bp}
#'   \item{18S}{100--2000 bp}
#'   \item{trnL}{10--300 bp}
#'   \item{(unrecognised)}{100--2000 bp (fallback, with message)}
#' }
#'
#' ## API strategy (reverse search)
#' Species enumeration uses the NCBI taxonomy subtree (three taxonomy API
#' calls per genus) when `species_list` is NULL.  Barcode availability is
#' checked via a **reverse search**: one genus-level NCBI nucleotide query
#' (capped at `max_nuccore` hits) followed by a batched `entrez_summary`
#' on the nuccore records to retrieve title and taxid simultaneously, then
#' a batched taxonomy `entrez_summary` to resolve species names.  This
#' requires only ~4 fixed API calls per genus regardless of how many
#' candidate species exist, and is substantially faster than per-species
#' `retmax = 0` queries for species-rich genera.  The date filter is
#' embedded directly in the query term as a `[PDAT]` range.  Sequences
#' with a `"PREDICTED:"` title prefix (typically `XR_`/`XM_` RefSeq
#' accessions) are classified separately; see `exclude_predicted`.
#'
#' @return A named list:
#' \describe{
#'   \item{`census`}{Data frame, one row per genus: `group`, `total`
#'     (described species), `in_reference` (in `match_df`),
#'     `has_seqs_not_in_ref` (experimental barcode sequences exist in NCBI
#'     but not in the reference -- a completeness gap),
#'     `has_predicted_only` (only computationally predicted sequences found;
#'     `NA` when classification was not performed),
#'     `unreferenced` (no barcode sequences found; when `exclude_predicted
#'     = TRUE` (default), predicted-only species are included here),
#'     `is_complete` (TRUE when both gaps are zero).}
#'   \item{`unreferenced`}{Character vector of unreferenced species names, suitable for
#'     `TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)`.}
#' }
#'
#' @note Requires an internet connection and the `rentrez` package.  NCBI
#'   enforces rate limits (3 req/s without an API key; 10 req/s with one).
#'
#' @param max_nuccore Integer.  Maximum NCBI nucleotide IDs fetched per genus
#'   for the reverse barcode check.  Default 5000; increase for extremely
#'   sequence-rich genera if some represented species are suspected to be missed.
#' @param exclude_predicted Logical.  If \code{TRUE} (default), computationally
#'   predicted sequences (NCBI title prefix \code{"PREDICTED:"}, typically
#'   \code{XR_} and \code{XM_} RefSeq accessions) are excluded from the barcode
#'   check.  Predicted sequences are absent from curated databases (SILVA, PR2,
#'   MIDORI) used by metabarcoding labs and do not represent experimentally
#'   validated barcodes — counting them inflates \code{has_seqs_not_in_ref} and
#'   incorrectly suppresses unreferenced-species hypotheses for those taxa.
#'   Set \code{FALSE} only if you explicitly need to count predicted sequences.
#'   Mirrors the \code{blacklist_regex = "predicted"} default in
#'   [fetch_reference_sequences()].
#'
#' @seealso [audit_reference_coverage()], [apply_coverage_constraints()]
#'
#' @examples
#' \dontrun{
#' cov <- audit_barcode_coverage(
#'   reference_df,
#'   barcode_term = "MiFishU",
#'   target_rank  = "genus",
#'   max_date     = "2024/06/01"
#' )
#' cov$census
#' cov$unreferenced
#' }
#'
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done
#' @importFrom dplyr bind_rows filter pull
#' @export
audit_barcode_coverage <- function(match_df,
                                   barcode_term,
                                   species_list      = NULL,
                                   min_len           = NULL,
                                   max_len           = NULL,
                                   max_date          = NULL,
                                   target_rank       = "genus",
                                   cache_dir         = tools::R_user_dir("TaxaLikely", "cache"),
                                   ncbi_api_key      = NULL,
                                   max_nuccore       = 5000L,
                                   exclude_predicted = TRUE) {

  .audit_barcode_coverage_new_(
    match_df = match_df, barcode_term = barcode_term, species_list = species_list,
    min_len = min_len, max_len = max_len, max_date = max_date,
    target_rank = target_rank, cache_dir = cache_dir,
    ncbi_api_key = ncbi_api_key, max_nuccore = max_nuccore,
    use_gbif = FALSE, version_tag = NULL,
    exclude_predicted = exclude_predicted
  )
}


# Legacy per-species implementation — retained for reference, not called.
# Superseded by the reverse-search approach in .audit_barcode_coverage_new_().
.audit_barcode_coverage_legacy_ <- function(match_df,
                                             barcode_term,
                                             species_list  = NULL,
                                             min_len       = NULL,
                                             max_len       = NULL,
                                             max_date      = NULL,
                                             target_rank   = "genus",
                                             cache_dir     = tools::R_user_dir("TaxaLikely", "cache"),
                                             ncbi_api_key  = NULL) {

  # ---- Input validation -------------------------------------------------------
  if (!is.data.frame(match_df))
    stop("match_df must be a data frame")
  if (!is.character(barcode_term) || length(barcode_term) == 0L ||
      any(is.na(barcode_term)) || any(!nzchar(trimws(barcode_term))))
    stop("barcode_term must be a non-empty character vector with no NA values")
  if (!is.null(max_date)) {
    if (!is.character(max_date) || length(max_date) != 1L || is.na(max_date))
      stop("max_date must be a single character string or NULL")
    if (!grepl("^\\d{4}(/\\d{2}(/\\d{2})?)?$", trimws(max_date)))
      stop("max_date must be in YYYY, YYYY/MM, or YYYY/MM/DD format")
  }
  if (!is.null(species_list)) {
    if (!is.character(species_list) || length(species_list) == 0L)
      stop("species_list must be a character vector of species names, or NULL")
    species_list <- unique(.first_two_words(
      trimws(species_list[TaxaTools::is_valid_species_name(trimws(species_list))])
    ))
  }

  names(match_df) <- tolower(names(match_df))
  target_rank     <- tolower(target_rank)

  if (!target_rank %in% names(match_df))
    stop(sprintf("Column '%s' not found in match_df", target_rank))
  if (!"species" %in% names(match_df))
    stop("Column 'species' not found in match_df")

  if (!requireNamespace("rentrez", quietly = TRUE))
    stop("Package 'rentrez' is required. Install with: install.packages('rentrez')")

  # ---- Setup ------------------------------------------------------------------
  if (!is.null(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  len_range  <- TaxaTools::resolve_barcode_lengths(barcode_term, min_len, max_len)
  term_label <- paste(barcode_term, collapse = "/")

  # Barcode [All Fields] OR clause (case-insensitive on NCBI side)
  barcode_clause <- if (length(barcode_term) == 1L) {
    sprintf("%s[All Fields]", barcode_term)
  } else {
    sprintf("(%s)", paste(sprintf("%s[All Fields]", barcode_term), collapse = " OR "))
  }

  # Date filter embedded in query term string as [PDAT] range.
  # Passing datetype/mindate/maxdate as separate API parameters causes silent
  # HTTP 500 failures on the NCBI nucleotide endpoint.  Embedding in the term
  # (as used by f_search_sequence_by_gene in the UBC workflow) is reliable.
  date_clause <- if (!is.null(max_date)) {
    sprintf(" AND (1985[PDAT] : %s[PDAT])", trimws(max_date))
  } else ""

  genera <- unique(stats::na.omit(match_df[[target_rank]]))
  genera <- genera[nchar(trimws(genera)) > 0L]

  if (length(genera) == 0L) {
    warning(sprintf("No valid groups found in column '%s'. Census skipped.", target_rank))
    return(list(
      census = data.frame(
        group = character(), total = integer(),
        in_reference = integer(), has_seqs_not_in_ref = integer(),
        unreferenced = integer(), is_complete = logical(),
        stringsAsFactors = FALSE
      ),
      unreferenced = character(0L)
    ))
  }

  # ---- Checkpoint setup -------------------------------------------------------
  checkpoint_path <- NULL
  prior_census    <- list()
  if (!is.null(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    checkpoint_path <- .coverage_checkpoint_path(
      genera, barcode_term, len_range, max_date, target_rank, cache_dir)
    if (file.exists(checkpoint_path)) {
      prior_census <- readRDS(checkpoint_path)
      n_done <- sum(genera %in% names(prior_census))
      message(sprintf(
        "  Resuming from checkpoint: %d/%d %s(s) already done.",
        n_done, length(genera), target_rank))
    }
  }

  message(sprintf(
    "Auditing %d %s(s) (barcode: '%s', length: %d-%d bp%s)...",
    length(genera), target_rank, term_label, len_range[1L], len_range[2L],
    if (nzchar(date_clause)) sprintf(", up to %s", trimws(max_date)) else ""
  ))

  # ---- Internal helper: count barcode seqs for one species (retmax=0) ---------
  # Returns NA_integer_ if all 3 attempts fail (exponential backoff).
  .count_seqs <- function(sp) {
    term <- sprintf('"%s"[Organism] AND %s AND %d:%d[SLEN]%s',
                    sp, barcode_clause, len_range[1L], len_range[2L], date_clause)
    for (attempt in seq_len(3L)) {
      res <- tryCatch(
        rentrez::entrez_search(db = "nuccore", term = term, retmax = 0L),
        error = function(e) NULL
      )
      if (!is.null(res) && !is.null(res$count))
        return(as.integer(res$count))
      Sys.sleep(attempt)   # backoff: 1 s, 2 s, 3 s
    }
    NA_integer_
  }

  # ---- Per-genus audit loop --------------------------------------------------
  full_census <- vector("list", length(genera))
  names(full_census) <- genera

  pb <- cli::cli_progress_bar("Auditing genera", total = length(genera))
  for (i in seq_along(genera)) {
    cli::cli_progress_update(id = pb)
    grp <- genera[i]

    # Resume from checkpoint
    if (grp %in% names(prior_census)) {
      full_census[[i]] <- prior_census[[grp]]
      next
    }

    rec <- list(
      group               = grp,
      total               = NA_integer_,
      in_reference        = NA_integer_,
      has_seqs_not_in_ref = NA_integer_,
      unreferenced_count         = NA_integer_,
      unreferenced_names         = character(0L)
    )

    # Reference species for this genus (skip-list: confirmed to have sequences)
    ref_sp <- tryCatch({
      x <- match_df |>
        dplyr::filter(.data[[target_rank]] == grp) |>
        dplyr::pull(species) |>
        unique()
      .first_two_words(x[TaxaTools::is_valid_species_name(x)])
    }, error = function(e) character(0L))

    # All described species for this genus
    # Try user-supplied list first; fall back to NCBI taxonomy if the list
    # has no entries for this genus (common when species_list comes from a
    # geographically restricted source like TaxaExpect/GBIF)
    all_sp <- character(0L)
    if (!is.null(species_list)) {
      all_sp <- species_list[startsWith(species_list, paste0(grp, " "))]
    }
    if (length(all_sp) == 0L) {
      # Query NCBI taxonomy subtree (3 lightweight calls; always reliable)
      all_sp <- tryCatch({
        uid_res <- rentrez::entrez_search(
          db   = "taxonomy",
          term = sprintf('"%s"[Genus]', grp)
        )
        if (length(uid_res$ids) == 0L) character(0L)
        else {
        genus_uid <- uid_res$ids[1L]
        Sys.sleep(.ncbi_delay())

        sp_res <- rentrez::entrez_search(
          db     = "taxonomy",
          term   = sprintf("txid%s[Subtree] AND species[Rank]", genus_uid),
          retmax = 10000L
        )
        if (length(sp_res$ids) == 0L) character(0L)
        else {
        Sys.sleep(.ncbi_delay())

        # Batch entrez_summary to avoid HTTP 413/414 on species-rich genera
        # (e.g. Ulva, Symbiodinium, Chlamydomonas). 200 IDs per request is safe.
        batch_size   <- 200L
        id_batches   <- split(sp_res$ids,
                              ceiling(seq_along(sp_res$ids) / batch_size))
        sp_summ_flat <- unlist(lapply(id_batches, function(batch) {
          Sys.sleep(.ncbi_delay())
          s <- tryCatch(
            rentrez::entrez_summary(db = "taxonomy", id = batch),
            error = function(e) {
              warning(sprintf("Taxonomy summary batch failed for '%s': %s",
                              grp, conditionMessage(e)))
              NULL
            }
          )
          if (is.null(s)) return(list())
          if (inherits(s, "esummary")) list(s) else as.list(s)
        }), recursive = FALSE)

        raw <- vapply(sp_summ_flat, `[[`, character(1L), "scientificname")
        raw <- .first_two_words(unique(raw[!is.na(raw)]))
        raw[TaxaTools::is_valid_species_name(raw)]
        } # close inner else
        } # close outer else
      }, error = function(e) {
        warning(sprintf("Taxonomy query failed for '%s': %s",
                        grp, conditionMessage(e)))
        character(0L)
      })
    }

    if (length(all_sp) == 0L) {
      full_census[[i]] <- rec
      # Do NOT save NA records to the checkpoint — genera with no NCBI result
      # (e.g. due to a transient HTTP error) should be retried on resume.
      if (i < length(genera)) Sys.sleep(.ncbi_delay())
      next
    }

    # Candidates: described species minus the reference skip-list
    candidates <- setdiff(all_sp, ref_sp)

    message(sprintf(
      "  '%s': %d described, %d in reference, checking %d candidates...",
      grp, length(all_sp), length(ref_sp), length(candidates)
    ))

    # Count barcode sequences per candidate using retmax=0.
    #   count = 0  → unreferenced (no sequence for this marker)
    #   count > 0  → has sequences but absent from reference (completeness gap)
    #   count = NA → all retries failed; treated conservatively as unreferenced
    has_seqs <- character(0L)
    unref_sp <- character(0L)
    n_failed <- 0L

    for (k in seq_along(candidates)) {
      sp    <- candidates[k]
      count <- .count_seqs(sp)

      if (is.na(count)) {
        n_failed <- n_failed + 1L
        unref_sp <- c(unref_sp, sp)   # conservative on failure
      } else if (count == 0L) {
        unref_sp <- c(unref_sp, sp)
      } else {
        has_seqs <- c(has_seqs, sp)
      }

      if (k %% 3L == 0L) Sys.sleep(.ncbi_delay())
    }

    if (n_failed > 0L)
      warning(sprintf(
        "%d of %d barcode queries failed for '%s' after 3 attempts (treated as unreferenced)",
        n_failed, length(candidates), grp
      ))

    rec <- list(
      group               = grp,
      total               = length(all_sp),
      in_reference        = length(ref_sp),
      has_seqs_not_in_ref = length(has_seqs),
      unreferenced_count  = length(unref_sp),
      unreferenced_names  = unref_sp
    )

    full_census[[i]] <- rec
    if (!is.null(checkpoint_path)) {
      prior_census[[grp]] <- rec
      saveRDS(prior_census, checkpoint_path)
    }
    if (i < length(genera)) Sys.sleep(.ncbi_delay())
  }
  cli::cli_progress_done(id = pb)

  # Delete checkpoint on clean completion
  if (!is.null(checkpoint_path) && file.exists(checkpoint_path))
    file.remove(checkpoint_path)

  # ---- Assemble output -------------------------------------------------------
  census_df <- dplyr::bind_rows(lapply(full_census, function(x) {
    data.frame(
      group               = x$group,
      total               = x$total,
      in_reference        = x$in_reference,
      has_seqs_not_in_ref = x$has_seqs_not_in_ref,
      unreferenced        = x$unreferenced_count,
      is_complete         = !is.na(x$has_seqs_not_in_ref) &&
                            !is.na(x$unreferenced_count) &&
                            x$has_seqs_not_in_ref == 0L &&
                            x$unreferenced_count == 0L,
      stringsAsFactors    = FALSE
    )
  }))

  all_unreferenced <- unlist(lapply(full_census, `[[`, "unreferenced_names"))
  all_unreferenced <- all_unreferenced[!is.na(all_unreferenced) & nchar(all_unreferenced) > 0L]
  names(all_unreferenced) <- NULL

  list(census = census_df, unreferenced = all_unreferenced)
}


# ==============================================================================
# INTERNAL HELPERS — reverse-search audit implementation
# ==============================================================================

# Resolve NCBI taxonomy UID for a genus name. Returns NA_character_ on failure.
#' @noRd
.genus_taxid <- function(grp) {
  search_grp <- gsub("-", " ", grp)   # handle hyphenated genera (e.g. Pseudo-nitzschia)
  tryCatch({
    res <- rentrez::entrez_search(db = "taxonomy",
                                  term = sprintf('"%s"[Genus]', search_grp))
    if (length(res$ids) == 0L) NA_character_ else res$ids[1L]
  }, error = function(e) NA_character_)
}

# Reverse barcode check: one genus-level nuccore search + batched elink to
# taxonomy + batched taxonomy summary.
#
# Replaces N per-species entrez_search calls with O(ceil(n_ids / 200)) elink
# calls regardless of how many candidate species exist.  The efficiency gain is
# largest for species-rich genera (Ulva, Chlamydomonas, Symbiodinium...).
#
# Returns list(sp_with_seqs, sp_unreferenced) where both are character vectors
# drawn from `candidates`.
#' @noRd
.reverse_barcode_check <- function(genus_uid, candidates,
                                    barcode_clause, len_range, date_clause,
                                    max_nuccore = 5000L) {
  empty <- list(sp_with_seqs      = character(0L),
                sp_predicted_only = character(0L),
                sp_unreferenced   = candidates)
  if (is.na(genus_uid) || length(candidates) == 0L) return(empty)

  # Step 1: one nuccore search for the entire genus — no predicted filter.
  # We classify experimental vs. predicted from the Title field in Step 2,
  # so a single search covers both categories without an extra API call.
  nuc_res <- tryCatch(
    rentrez::entrez_search(
      db     = "nuccore",
      term   = sprintf('txid%s[Organism:exp] AND %s AND %d:%d[SLEN]%s',
                       genus_uid, barcode_clause,
                       len_range[1L], len_range[2L], date_clause),
      retmax = max_nuccore
    ),
    error = function(e) NULL
  )
  if (is.null(nuc_res) || length(nuc_res$ids) == 0L) return(empty)
  Sys.sleep(.ncbi_delay())

  # Step 2: nuccore summaries → {title, taxid} per record.
  # title prefix "PREDICTED:" identifies computationally-annotated sequences
  # (XR_/XM_ RefSeq accessions) that are absent from curated barcode databases.
  # taxid links each sequence record to a species without a separate elink call.
  nuc_batches  <- split(nuc_res$ids, ceiling(seq_along(nuc_res$ids) / 200L))
  nuc_summ_flat <- unlist(lapply(nuc_batches, function(batch) {
    Sys.sleep(.ncbi_delay())
    s <- tryCatch(rentrez::entrez_summary(db = "nuccore", id = batch),
                  error = function(e) NULL)
    if (is.null(s)) return(list())
    if (inherits(s, "esummary")) list(s) else as.list(s)
  }), recursive = FALSE)
  if (length(nuc_summ_flat) == 0L) return(empty)

  titles <- vapply(nuc_summ_flat,
                   function(s) s[["title"]] %||% NA_character_, character(1L))
  taxids <- vapply(nuc_summ_flat,
                   function(s) as.character(s[["taxid"]] %||% NA_character_),
                   character(1L))
  is_pred <- startsWith(toupper(trimws(titles)), "PREDICTED")

  taxids_exp       <- unique(taxids[!is_pred & !is.na(taxids)])
  taxids_pred      <- unique(taxids[ is_pred & !is.na(taxids)])
  taxids_pred_only <- setdiff(taxids_pred, taxids_exp)

  all_taxids <- unique(c(taxids_exp, taxids_pred_only))
  if (length(all_taxids) == 0L) return(empty)
  Sys.sleep(.ncbi_delay())

  # Step 3: taxonomy names for relevant taxids (batched to avoid 414)
  tax_batches  <- split(all_taxids, ceiling(seq_along(all_taxids) / 200L))
  tax_summ_flat <- unlist(lapply(tax_batches, function(batch) {
    Sys.sleep(.ncbi_delay())
    s <- tryCatch(rentrez::entrez_summary(db = "taxonomy", id = batch),
                  error = function(e) NULL)
    if (is.null(s)) return(list())
    if (inherits(s, "esummary")) list(s) else as.list(s)
  }), recursive = FALSE)

  .sp_names <- function(taxid_vec, summ_list) {
    uid_map <- vapply(summ_list, function(s) as.character(s[["uid"]] %||% NA),
                      character(1L))
    nms <- vapply(summ_list, function(s) {
      if (!is.null(s[["rank"]]) && s[["rank"]] == "species")
        s[["scientificname"]] else NA_character_
    }, character(1L))
    matched <- nms[uid_map %in% taxid_vec]
    raw <- .first_two_words(unique(matched[!is.na(matched)]))
    raw[TaxaTools::is_valid_species_name(raw)]
  }

  sp_exp       <- .sp_names(taxids_exp,       tax_summ_flat)
  sp_pred_only <- setdiff(.sp_names(taxids_pred_only, tax_summ_flat), sp_exp)

  list(
    sp_with_seqs      = intersect(candidates, sp_exp),
    sp_predicted_only = intersect(candidates, sp_pred_only),
    sp_unreferenced   = setdiff(candidates, union(sp_exp, sp_pred_only))
  )
}

# Enumerate accepted species for a genus from the GBIF backbone.
# Requires rgbif (in TaxaFetch Imports; not in TaxaLikely — checked at runtime).
# Returns character(0L) on any failure so the caller can fall back to NCBI.
#' @noRd
.get_species_gbif <- function(grp) {
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    warning(sprintf("'rgbif' not installed; GBIF lookup skipped for '%s'", grp))
    return(character(0L))
  }
  tryCatch({
    bb <- rgbif::name_backbone(name = grp, rank = "genus", strict = FALSE)
    if (is.null(bb) || length(bb) == 0L || is.na(bb$usageKey[1L]) ||
        toupper(bb$rank[1L]) != "GENUS")
      return(character(0L))
    ch <- rgbif::name_usage(key = bb$usageKey[1L],
                             data = "children", limit = 1000L)$data
    if (is.null(ch) || nrow(ch) == 0L) return(character(0L))
    sp <- ch$scientificName[
      !is.na(ch$rank) & toupper(ch$rank) == "SPECIES" &
      !is.na(ch$taxonomicStatus) &
      toupper(ch$taxonomicStatus) %in% c("ACCEPTED", "DOUBTFUL")
    ]
    sp_clean <- .first_two_words(trimws(sp))
    sp_clean[TaxaTools::is_valid_species_name(sp_clean)]
  }, error = function(e) character(0L))
}

# Shared inner loop body used by both new draft functions.
# Handles species enumeration (GBIF or NCBI) + reverse barcode check + record
# assembly. Returns a census record list.
#' @noRd
.audit_one_genus_reverse <- function(grp, match_df, target_rank,
                                      species_list, use_gbif,
                                      barcode_clause, len_range, date_clause,
                                      max_nuccore, exclude_predicted = TRUE) {
  rec <- list(group = grp, total = NA_integer_, in_reference = NA_integer_,
              has_seqs_not_in_ref = NA_integer_, unreferenced_count = NA_integer_,
              unreferenced_names = character(0L))

  # Reference skip-list
  ref_sp <- tryCatch({
    x <- match_df |>
      dplyr::filter(.data[[target_rank]] == grp) |>
      dplyr::pull(species) |> unique()
    .first_two_words(x[TaxaTools::is_valid_species_name(x)])
  }, error = function(e) character(0L))

  # Get NCBI genus UID (needed for reverse barcode check in all paths)
  genus_uid <- .genus_taxid(grp)
  Sys.sleep(.ncbi_delay())

  # Species enumeration
  all_sp <- character(0L)

  # 1. User-supplied list takes priority
  if (!is.null(species_list))
    all_sp <- species_list[startsWith(species_list, paste0(grp, " "))]

  # 2. Primary source: GBIF or NCBI (per function choice)
  if (length(all_sp) == 0L) {
    if (use_gbif) {
      all_sp <- .get_species_gbif(grp)
    } else {
      # NCBI taxonomy subtree (same as v1, now with batch fix)
      if (!is.na(genus_uid)) {
        all_sp <- tryCatch({
          sp_res <- rentrez::entrez_search(
            db     = "taxonomy",
            term   = sprintf("txid%s[Subtree] AND species[Rank]", genus_uid),
            retmax = 10000L
          )
          if (length(sp_res$ids) == 0L) character(0L)
          else {
            Sys.sleep(.ncbi_delay())
            batches <- split(sp_res$ids,
                             ceiling(seq_along(sp_res$ids) / 200L))
            sp_flat <- unlist(lapply(batches, function(b) {
              Sys.sleep(.ncbi_delay())
              s <- tryCatch(rentrez::entrez_summary(db = "taxonomy", id = b),
                            error = function(e) NULL)
              if (is.null(s)) return(list())
              if (inherits(s, "esummary")) list(s) else as.list(s)
            }), recursive = FALSE)
            raw <- vapply(sp_flat, `[[`, character(1L), "scientificname")
            raw <- .first_two_words(unique(raw[!is.na(raw)]))
            raw[TaxaTools::is_valid_species_name(raw)]
          }
        }, error = function(e) {
          warning(sprintf("NCBI taxonomy query failed for '%s': %s",
                          grp, conditionMessage(e)))
          character(0L)
        })
      }
    }
  }

  # 3. Fallback: if GBIF returned nothing, try NCBI taxonomy
  if (length(all_sp) == 0L && use_gbif && !is.na(genus_uid)) {
    all_sp <- tryCatch({
      sp_res <- rentrez::entrez_search(
        db     = "taxonomy",
        term   = sprintf("txid%s[Subtree] AND species[Rank]", genus_uid),
        retmax = 10000L
      )
      if (length(sp_res$ids) == 0L) character(0L)
      else {
        Sys.sleep(.ncbi_delay())
        batches <- split(sp_res$ids, ceiling(seq_along(sp_res$ids) / 200L))
        sp_flat <- unlist(lapply(batches, function(b) {
          Sys.sleep(.ncbi_delay())
          s <- tryCatch(rentrez::entrez_summary(db = "taxonomy", id = b),
                        error = function(e) NULL)
          if (is.null(s)) return(list())
          if (inherits(s, "esummary")) list(s) else as.list(s)
        }), recursive = FALSE)
        raw <- vapply(sp_flat, `[[`, character(1L), "scientificname")
        raw <- .first_two_words(unique(raw[!is.na(raw)]))
        raw[TaxaTools::is_valid_species_name(raw)]
      }
    }, error = function(e) character(0L))
  }

  if (length(all_sp) == 0L) return(rec)  # NA record; caller will not checkpoint

  candidates <- setdiff(all_sp, ref_sp)
  message(sprintf("  '%s': %d described, %d in ref, %d candidates",
                  grp, length(all_sp), length(ref_sp), length(candidates)))

  # Reverse barcode check
  bc <- .reverse_barcode_check(genus_uid, candidates, barcode_clause,
                                len_range, date_clause, max_nuccore)

  # When exclude_predicted = TRUE (default), predicted-only species have no
  # experimentally-validated barcode and are treated as unreferenced for the
  # purpose of hypothesis expansion — they can appear as candidates because
  # they are absent from curated BLAST databases.  When FALSE, they are
  # counted as has_seqs_not_in_ref (suppressed from expansion).
  if (exclude_predicted) {
    unreferenced_names <- c(bc$sp_unreferenced, bc$sp_predicted_only)
  } else {
    unreferenced_names <- bc$sp_unreferenced
  }

  list(
    group                = grp,
    total                = length(all_sp),
    in_reference         = length(ref_sp),
    has_seqs_not_in_ref  = length(bc$sp_with_seqs) +
                             if (!exclude_predicted) length(bc$sp_predicted_only) else 0L,
    has_predicted_only   = length(bc$sp_predicted_only),
    predicted_only_names = bc$sp_predicted_only,
    unreferenced_count   = length(unreferenced_names),
    unreferenced_names   = unreferenced_names
  )
}


# ==============================================================================
# DRAFT: audit_barcode_coverage_gbif()
# Species enumeration: GBIF backbone (NCBI fallback for genera missing from GBIF)
# Barcode check:       reverse NCBI  (one genus-level nuccore search + elink)
# ==============================================================================

#' Audit barcode coverage — GBIF species list + reverse NCBI search (DRAFT)
#'
#' Experimental alternative to [audit_barcode_coverage()].  Uses the GBIF
#' backbone to enumerate described species per genus (no rate-limiting; often
#' more complete for marine invertebrates and algae) and replaces the N
#' per-species NCBI nucleotide queries with a single genus-level search plus
#' `elink` back to taxonomy.
#'
#' API calls per genus: ~3 fixed (genus taxid + nuccore search + elink +
#' taxonomy batch), regardless of the number of candidate species.
#' Compare with [audit_barcode_coverage()] (v1) and
#' [audit_barcode_coverage_ncbi()] (v3) for speed and robustness.
#'
#' @param match_df,barcode_term,species_list,min_len,max_len,max_date,target_rank,cache_dir,ncbi_api_key
#'   Same as [audit_barcode_coverage()].
#' @param max_nuccore Integer.  Maximum NCBI nucleotide IDs fetched per genus
#'   for the reverse check.  Default 5000; increase for extremely sequence-rich
#'   genera if some represented species are suspected to be missed.
#'
#' @return Same structure as [audit_barcode_coverage()].
#' @seealso [audit_barcode_coverage()]
#' @noRd
audit_barcode_coverage_gbif <- function(match_df,
                                         barcode_term,
                                         species_list      = NULL,
                                         min_len           = NULL,
                                         max_len           = NULL,
                                         max_date          = NULL,
                                         target_rank       = "genus",
                                         cache_dir         = tools::R_user_dir("TaxaLikely", "cache"),
                                         ncbi_api_key      = NULL,
                                         max_nuccore       = 5000L,
                                         exclude_predicted = TRUE) {

  .audit_barcode_coverage_new_(
    match_df = match_df, barcode_term = barcode_term, species_list = species_list,
    min_len = min_len, max_len = max_len, max_date = max_date,
    target_rank = target_rank, cache_dir = cache_dir,
    ncbi_api_key = ncbi_api_key, max_nuccore = max_nuccore,
    use_gbif = TRUE, version_tag = "gbif",
    exclude_predicted = exclude_predicted
  )
}


#' @rdname audit_barcode_coverage
#' @export
audit_barcode_coverage_ncbi <- function(match_df,
                                         barcode_term,
                                         species_list  = NULL,
                                         min_len       = NULL,
                                         max_len       = NULL,
                                         max_date      = NULL,
                                         target_rank   = "genus",
                                         cache_dir     = tools::R_user_dir("TaxaLikely", "cache"),
                                         ncbi_api_key  = NULL,
                                         max_nuccore   = 5000L) {
  .Deprecated("audit_barcode_coverage")
  audit_barcode_coverage(
    match_df = match_df, barcode_term = barcode_term, species_list = species_list,
    min_len = min_len, max_len = max_len, max_date = max_date,
    target_rank = target_rank, cache_dir = cache_dir,
    ncbi_api_key = ncbi_api_key, max_nuccore = max_nuccore
  )
}


# Shared scaffolding for audit_barcode_coverage() and audit_barcode_coverage_gbif().
# Handles validation, checkpoint, progress bar, and output assembly.
# use_gbif: selects GBIF vs NCBI species enumeration.
# version_tag: NULL = canonical checkpoint name; non-NULL = suffixed name.
#' @noRd
.audit_barcode_coverage_new_ <- function(match_df, barcode_term, species_list,
                                          min_len, max_len, max_date,
                                          target_rank, cache_dir, ncbi_api_key,
                                          max_nuccore, use_gbif, version_tag,
                                          exclude_predicted = TRUE) {
  # ---- Input validation ------------------------------------------------------
  if (!is.data.frame(match_df))
    stop("match_df must be a data frame")
  if (!is.character(barcode_term) || length(barcode_term) == 0L ||
      any(is.na(barcode_term)) || any(!nzchar(trimws(barcode_term))))
    stop("barcode_term must be a non-empty character vector with no NA values")
  if (!is.null(max_date)) {
    if (!is.character(max_date) || length(max_date) != 1L || is.na(max_date))
      stop("max_date must be a single character string or NULL")
    if (!grepl("^\\d{4}(/\\d{2}(/\\d{2})?)?$", trimws(max_date)))
      stop("max_date must be in YYYY, YYYY/MM, or YYYY/MM/DD format")
  }
  if (!is.null(species_list)) {
    if (!is.character(species_list) || length(species_list) == 0L)
      stop("species_list must be a character vector or NULL")
    species_list <- unique(.first_two_words(
      trimws(species_list[TaxaTools::is_valid_species_name(trimws(species_list))])
    ))
  }
  if (!requireNamespace("rentrez", quietly = TRUE))
    stop("Package 'rentrez' is required. Install with: install.packages('rentrez')")

  names(match_df) <- tolower(names(match_df))
  target_rank     <- tolower(target_rank)
  if (!target_rank %in% names(match_df))
    stop(sprintf("Column '%s' not found in match_df", target_rank))
  if (!"species" %in% names(match_df))
    stop("Column 'species' not found in match_df")

  if (!is.null(ncbi_api_key)) rentrez::set_entrez_key(ncbi_api_key)

  len_range      <- TaxaTools::resolve_barcode_lengths(barcode_term, min_len, max_len)
  term_label     <- paste(barcode_term, collapse = "/")
  barcode_clause <- if (length(barcode_term) == 1L)
    sprintf("%s[All Fields]", barcode_term)
  else
    sprintf("(%s)", paste(sprintf("%s[All Fields]", barcode_term), collapse = " OR "))
  date_clause <- if (!is.null(max_date))
    sprintf(" AND (1985[PDAT] : %s[PDAT])", trimws(max_date)) else ""

  genera <- unique(stats::na.omit(match_df[[target_rank]]))
  genera <- genera[nchar(trimws(genera)) > 0L]
  if (length(genera) == 0L) {
    warning(sprintf("No valid groups in column '%s'. Census skipped.", target_rank))
    return(list(
      census = data.frame(group = character(), total = integer(),
                          in_reference = integer(), has_seqs_not_in_ref = integer(),
                          unreferenced = integer(), is_complete = logical(),
                          stringsAsFactors = FALSE),
      unreferenced = character(0L)
    ))
  }

  # ---- Checkpoint (version-tagged or canonical) -------------------------------
  checkpoint_path <- NULL
  prior_census    <- list()
  if (!is.null(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    base_path <- .coverage_checkpoint_path(genera, barcode_term, len_range,
                                            max_date, target_rank, cache_dir)
    checkpoint_path <- if (is.null(version_tag)) base_path else
      sub("_ckpt\\.rds$", sprintf("_%s_ckpt.rds", version_tag), base_path)
    if (file.exists(checkpoint_path)) {
      prior_census <- readRDS(checkpoint_path)
      n_done <- sum(genera %in% names(prior_census))
      pfx <- if (is.null(version_tag)) "" else sprintf("[%s] ", version_tag)
      message(sprintf("  %sResuming: %d/%d %s(s) done.",
                      pfx, n_done, length(genera), target_rank))
    }
  }

  t_start <- proc.time()[["elapsed"]]
  pfx <- if (is.null(version_tag)) "" else sprintf("[%s] ", version_tag)
  message(sprintf(
    "%sAuditing %d %s(s) (barcode: '%s', length: %d-%d bp)...",
    pfx, length(genera), target_rank, term_label,
    len_range[1L], len_range[2L]))

  # ---- Per-genus loop --------------------------------------------------------
  full_census <- vector("list", length(genera))
  names(full_census) <- genera

  pb_label <- if (is.null(version_tag)) "Auditing genera" else
    sprintf("Auditing genera [%s]", version_tag)
  pb <- cli::cli_progress_bar(pb_label, total = length(genera))

  for (i in seq_along(genera)) {
    cli::cli_progress_update(id = pb)
    grp <- genera[i]

    if (grp %in% names(prior_census)) {
      full_census[[i]] <- prior_census[[grp]]
      next
    }

    rec <- .audit_one_genus_reverse(
      grp = grp, match_df = match_df, target_rank = target_rank,
      species_list = species_list, use_gbif = use_gbif,
      barcode_clause = barcode_clause, len_range = len_range,
      date_clause = date_clause, max_nuccore = max_nuccore,
      exclude_predicted = exclude_predicted
    )

    full_census[[i]] <- rec

    # Only checkpoint complete (non-NA) records
    if (!is.na(rec$total) && !is.null(checkpoint_path)) {
      prior_census[[grp]] <- rec
      saveRDS(prior_census, checkpoint_path)
    }

    if (i < length(genera)) Sys.sleep(.ncbi_delay())
  }
  cli::cli_progress_done(id = pb)

  elapsed <- proc.time()[["elapsed"]] - t_start
  pfx2 <- if (is.null(version_tag)) "" else sprintf("[%s] ", version_tag)
  message(sprintf("%sCompleted in %.1f min.", pfx2, elapsed / 60))

  if (!is.null(checkpoint_path) && file.exists(checkpoint_path))
    file.remove(checkpoint_path)

  # ---- Assemble output -------------------------------------------------------
  census_df <- dplyr::bind_rows(lapply(full_census, function(x) {
    data.frame(
      group               = x$group,
      total               = x$total,
      in_reference        = x$in_reference,
      has_seqs_not_in_ref = x$has_seqs_not_in_ref,
      has_predicted_only  = x$has_predicted_only  %||% NA_integer_,
      unreferenced        = x$unreferenced_count,
      is_complete         = !is.na(x$has_seqs_not_in_ref) &&
                            !is.na(x$unreferenced_count) &&
                            x$has_seqs_not_in_ref == 0L &&
                            x$unreferenced_count == 0L,
      stringsAsFactors    = FALSE
    )
  }))

  all_unreferenced <- unlist(lapply(full_census, `[[`, "unreferenced_names"))
  all_unreferenced <- all_unreferenced[!is.na(all_unreferenced) &
                                       nchar(all_unreferenced) > 0L]
  names(all_unreferenced) <- NULL
  list(census = census_df, unreferenced = all_unreferenced)
}


# ==============================================================================
# audit_acoustic_coverage()
# ==============================================================================

#' Audit Acoustic Reference Coverage for a Species List
#'
#' Checks which plausible species at a site are absent from an acoustic
#' classifier's known species list (e.g., BirdNET's built-in list or a
#' custom Xeno-canto model).  A species absent from the reference can never
#' appear as a scored candidate — it is an **unreferenced species** in the
#' acoustic context.
#'
#' This is the acoustic analog of [audit_barcode_coverage()], but far simpler:
#' no NCBI API calls are needed.  Coverage is determined by a plain set
#' membership check against `reference_species`.
#'
#' @section Scope:
#' Designed for acoustic (bird sound) and image (camera trap) data where the
#' classifier has a fixed known species list.  For DNA eDNA data, use
#' [audit_barcode_coverage()] instead (barcode sequence availability in NCBI
#' is the relevant coverage concept, not presence in a classifier list).
#'
#' @param plausible_species Character vector. Species expected to occur at the
#'   sampling site (e.g., from an LLM call, GBIF query, or expert list).
#'   Should be binomial scientific names.
#' @param reference_species Character vector. Species in the classifier's known
#'   list (e.g., the BirdNET species list, or the set of species used to train
#'   a custom Xeno-canto model).  Names are matched case-insensitively after
#'   trimming whitespace.
#' @param match_df Data frame or `NULL`. Optional.  If supplied, species already
#'   present in the match data (i.e., confirmed candidates from the classifier)
#'   are annotated as `in_match_data = TRUE` in the census output.  Use
#'   `TaxaMatch::standardize_match_data()` output or raw
#'   `TaxaMatch::read_birdnet_output()` output.
#'   The species column is auto-detected from `"species"` or `"taxon_name"`.
#'   Default `NULL`.
#' @param xc_recordings Logical. If `TRUE`, queries the Xeno-canto v2 API for
#'   the number of recordings available for each species in `plausible_species`
#'   and adds an `n_recordings` column to the census. Requires an internet
#'   connection; adds approximately 1 second per species. Default `FALSE`.
#'
#' @return A named list with two components:
#'   \describe{
#'     \item{`census`}{Data frame with one row per entry in `plausible_species`:
#'       \describe{
#'         \item{`species`}{Species name (from `plausible_species`).}
#'         \item{`in_reference`}{Logical. `TRUE` if the species is in
#'           `reference_species`.}
#'         \item{`unreferenced`}{Logical. `TRUE` if the species is absent from
#'           `reference_species` (can never appear as a candidate detection).}
#'         \item{`in_match_data`}{Logical.  `TRUE` if the species appeared in
#'           `match_df`.  `NA` when `match_df = NULL`.}
#'         \item{`n_recordings`}{Integer. Number of Xeno-canto recordings for
#'           the species. `NA` when `xc_recordings = FALSE` or the query fails.
#'           Even a species present in the BirdNET list may be poorly classified
#'           if it has very few training recordings.}
#'       }}
#'     \item{`unreferenced`}{Character vector of species names absent from
#'       `reference_species`.  Pass to `TaxaAssign::suggest_unreferenced_species()`
#'       as `unreferenced_taxa` to build H2 hypotheses for these species.}
#'   }
#'
#' @seealso [audit_barcode_coverage()], [apply_coverage_constraints()]
#'
#' @examples
#' plausible <- c("Turdus migratorius", "Setophaga petechia",
#'                "Limosa fedoa", "Selasphorus calliope")
#' birdnet_list <- c("Turdus migratorius", "Setophaga petechia",
#'                   "Turdus merula", "Corvus brachyrhynchos")
#'
#' result <- audit_acoustic_coverage(plausible, birdnet_list)
#' result$census
#' result$unreferenced  # c("Limosa fedoa", "Selasphorus calliope")
#'
#' @export
audit_acoustic_coverage <- function(plausible_species,
                                    reference_species,
                                    match_df      = NULL,
                                    xc_recordings = FALSE) {

  # ---- validate inputs -------------------------------------------------------
  if (!is.character(plausible_species) || length(plausible_species) == 0L)
    stop("audit_acoustic_coverage: 'plausible_species' must be a non-empty character vector.",
         call. = FALSE)
  if (!is.character(reference_species) || length(reference_species) == 0L)
    stop("audit_acoustic_coverage: 'reference_species' must be a non-empty character vector.",
         call. = FALSE)
  if (!is.logical(xc_recordings) || length(xc_recordings) != 1L || is.na(xc_recordings))
    stop("audit_acoustic_coverage: 'xc_recordings' must be TRUE or FALSE.", call. = FALSE)

  # ---- normalise for matching (trim + lowercase) -----------------------------
  plausible_norm  <- trimws(plausible_species)
  reference_norm  <- trimws(tolower(reference_species))

  in_ref <- tolower(plausible_norm) %in% reference_norm

  # ---- match_df annotation ---------------------------------------------------
  in_match <- rep(NA, length(plausible_norm))
  if (!is.null(match_df)) {
    if (!is.data.frame(match_df))
      stop("audit_acoustic_coverage: 'match_df' must be a data frame or NULL.",
           call. = FALSE)
    sp_col <- if ("taxon_name" %in% names(match_df)) "taxon_name" else
              if ("species"    %in% names(match_df)) "species"    else NULL
    if (is.null(sp_col)) {
      warning("audit_acoustic_coverage: 'match_df' has no 'taxon_name' or 'species' ",
              "column -- 'in_match_data' will be NA.", call. = FALSE)
    } else {
      match_sp <- trimws(tolower(unique(match_df[[sp_col]])))
      in_match <- as.logical(tolower(plausible_norm) %in% match_sp)
    }
  }

  # ---- Xeno-canto recording counts (optional) --------------------------------
  n_rec <- rep(NA_integer_, length(plausible_norm))
  if (xc_recordings) {
    message(sprintf(
      "audit_acoustic_coverage: querying Xeno-canto for %d species (1s per query)...",
      length(plausible_norm)
    ))
    for (i in seq_along(plausible_norm)) {
      n_rec[[i]] <- .xc_recording_count(plausible_norm[[i]])
      Sys.sleep(1)
    }
  }

  # ---- build census data frame -----------------------------------------------
  census_df <- data.frame(
    species       = plausible_norm,
    in_reference  = in_ref,
    unreferenced  = !in_ref,
    in_match_data = in_match,
    n_recordings  = n_rec,
    stringsAsFactors = FALSE
  )

  unreferenced_sp <- plausible_norm[!in_ref]

  n_plausible    <- length(plausible_norm)
  n_in_ref       <- sum(in_ref)
  n_unreferenced <- sum(!in_ref)

  message(sprintf(
    paste0(
      "audit_acoustic_coverage: %d plausible species checked; ",
      "%d in reference (%.0f%%), %d unreferenced."
    ),
    n_plausible, n_in_ref,
    100 * n_in_ref / n_plausible,
    n_unreferenced
  ))

  list(census = census_df, unreferenced = unreferenced_sp)
}


#' Apply taxonomic completeness constraints to likelihood results
#'
#' Suppresses or relabels the `"unreferenced_species"` hypothesis for genera
#' confirmed to be fully sampled in the reference database.  If a genus has
#' no unsampled species, a new undescribed species from that genus is
#' impossible -- so the `"unreferenced_species"` likelihood should either be
#' zeroed (hard constraint) or relabeled to capture the alternative biology.
#'
#' **Behaviour modes** (controlled by `constraint_behavior`):
#'
#' - `"zero"` (default): likelihoods are multiplied by `penalty_factor`
#'   (default 0.0 = hard zero).  Use when you are confident the genus is
#'   complete and any match signal is artefactual.
#'
#' - `"relabel"`: `hypothesis_type` is changed from `"unreferenced_species"`
#'   to `"unresolved_species"` and likelihoods are left unchanged.  Use when
#'   the census confirms all known species are in the reference but match
#'   scores cannot determine *which* species the sample belongs to -- i.e.
#'   the sequence is real but ambiguous among the known members.  The relabeled
#'   row contributes as a named genus-level hypothesis in
#'   `TaxaAssign::consensus_taxonomy()`, preventing a prior-only fallback for
#'   these samples while correctly resolving to genus rank.
#'
#' @param likelihood_df Data frame returned by [evaluate_likelihoods()].
#' @param census_result Data frame with columns `taxon_name` (the group name,
#'   e.g. genus label), `rank` (e.g. `"genus"`), and `status` (`"complete"` or
#'   `"closed"` for fully-sampled groups; any other value leaves the
#'   hypothesis untouched).
#'
#'   To build this from `audit_barcode_coverage()`:
#'   ```r
#'   cov <- audit_barcode_coverage(match_df, barcode_term = "12S", target_rank = "genus")
#'   census_result <- dplyr::mutate(
#'     cov$census,
#'     taxon_name = group,
#'     rank       = "genus",
#'     status     = ifelse(is_complete, "complete", "incomplete")
#'   )
#'   ```
#'
#' @param penalty_factor Numeric in \[0, 1\] (default `0.0`).  Multiplier
#'   applied to `score_likelihood` and `score_likelihood_mean` for constrained
#'   hypotheses when `constraint_behavior = "zero"`.  Ignored when
#'   `constraint_behavior = "relabel"`.
#' @param constraint_behavior Character scalar: `"zero"` (default) or
#'   `"relabel"`.  See Details above.
#'
#' @return `likelihood_df` with an added `constraint_applied` column and
#'   updated likelihood and/or `hypothesis_type` columns:
#'   \describe{
#'     \item{`"zero"` mode}{`score_likelihood` and `score_likelihood_mean`
#'       multiplied by `penalty_factor`; `constraint_applied` set to
#'       `"census_closed_genus"`.}
#'     \item{`"relabel"` mode}{`hypothesis_type` changed to
#'       `"unresolved_species"`; likelihoods unchanged; `constraint_applied`
#'       set to `"census_closed_genus_relabeled"`.}
#'   }
#'   Rows not meeting the constraint have `constraint_applied = NA`.
#'
#' @seealso [audit_barcode_coverage()], [audit_reference_coverage()],
#'   [evaluate_likelihoods()]
#'
#' @examples
#' \dontrun{
#' constrained <- apply_coverage_constraints(
#'   result$likelihoods,
#'   census_result = cov
#' )
#' table(constrained$constraint_applied, useNA = "ifany")
#' }
#'
#' @importFrom dplyr bind_rows filter left_join mutate select
#' @export
apply_coverage_constraints <- function(likelihood_df,
                                       census_result,
                                       penalty_factor      = 0.0,
                                       constraint_behavior = c("zero", "relabel")) {
  constraint_behavior <- match.arg(constraint_behavior)

  if (!is.data.frame(likelihood_df))
    stop("likelihood_df must be a data frame")
  if (!is.data.frame(census_result))
    stop("census_result must be a data frame -- see ?apply_coverage_constraints for format")
  needed <- c("taxon_name", "rank", "status")
  missing_cols <- setdiff(needed, names(census_result))
  if (length(missing_cols) > 0L)
    stop(sprintf("census_result is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))
  if (!is.numeric(penalty_factor) || length(penalty_factor) != 1L ||
      is.na(penalty_factor) || penalty_factor < 0 || penalty_factor > 1)
    stop("penalty_factor must be a single numeric value in [0, 1]")

  needed_lik <- c("hypothesis_type", "taxon_name", "taxon_name_rank",
                  "score_likelihood", "score_likelihood_mean")
  missing_lik <- setdiff(needed_lik, names(likelihood_df))
  if (length(missing_lik) > 0L)
    stop(sprintf("likelihood_df is missing required columns: %s",
                 paste(missing_lik, collapse = ", ")))

  cen_clean <- census_result |>
    dplyr::mutate(
      join_name   = tolower(taxon_name),
      join_rank   = tolower(rank),
      join_status = tolower(status)
    ) |>
    dplyr::select(join_name, join_rank, join_status)

  inf_clean <- likelihood_df |>
    dplyr::mutate(
      join_name = tolower(taxon_name),
      join_rank = tolower(taxon_name_rank)
    )

  merged <- dplyr::left_join(inf_clean, cen_clean,
                             by = c("join_name", "join_rank"))

  if (constraint_behavior == "relabel") {
    result <- merged |>
      dplyr::mutate(
        is_forbidden     = hypothesis_type == "unreferenced_species" &
          !is.na(join_status) & join_status %in% c("complete", "closed"),
        hypothesis_type  = ifelse(is_forbidden, "unresolved_species", hypothesis_type),
        constraint_applied = ifelse(is_forbidden,
                                    "census_closed_genus_relabeled", NA_character_)
      ) |>
      dplyr::select(-join_name, -join_rank, -join_status, -is_forbidden)
  } else {
    result <- merged |>
      dplyr::mutate(
        is_forbidden         = hypothesis_type == "unreferenced_species" &
          !is.na(join_status) & join_status %in% c("complete", "closed"),
        score_likelihood = ifelse(is_forbidden,
                                      score_likelihood * penalty_factor,
                                      score_likelihood),
        score_likelihood_mean      = ifelse(is_forbidden,
                                      score_likelihood_mean * penalty_factor,
                                      score_likelihood_mean),
        constraint_applied   = ifelse(is_forbidden,
                                      "census_closed_genus", NA_character_)
      ) |>
      dplyr::select(-join_name, -join_rank, -join_status, -is_forbidden)
  }

  result
}


# ==============================================================================
# .xc_recording_count() -- internal helper
# ==============================================================================

#' Query Xeno-canto v2 API for the number of recordings for one species
#'
#' Returns an integer count, or \code{NA_integer_} on error or no match.
#' Xeno-canto v2 is publicly accessible without an API key.
#' @noRd
.xc_recording_count <- function(species_name) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    warning(
      ".xc_recording_count: 'httr2' is required for Xeno-canto queries. ",
      "Install with: install.packages('httr2')",
      call. = FALSE
    )
    return(NA_integer_)
  }

  req <- httr2::request("https://xeno-canto.org/api/2/recordings") |>
    httr2::req_url_query(query = trimws(species_name)) |>
    httr2::req_error(is_error = function(resp) FALSE)

  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp) || httr2::resp_status(resp) != 200L) return(NA_integer_)

  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  if (is.null(body) || is.null(body[["numRecordings"]])) return(NA_integer_)

  suppressWarnings(as.integer(body[["numRecordings"]]))
}


# ==============================================================================
# .inat_species_info() -- internal helper
# ==============================================================================

#' Query iNaturalist taxa API for observation count and taxon metadata
#'
#' Returns a list with \code{taxon_id}, \code{matched_name}, \code{rank},
#' \code{n_observations}, \code{found} (logical). All fields \code{NA}/FALSE
#' when the taxon is not found or the request fails.
#' @noRd
.inat_species_info <- function(species_name, api_token = "") {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    warning(
      ".inat_species_info: 'httr2' is required for iNaturalist queries. ",
      "Install with: install.packages('httr2')",
      call. = FALSE
    )
    return(list(taxon_id = NA_integer_, matched_name = NA_character_,
                rank = NA_character_, n_observations = NA_integer_,
                found = FALSE))
  }

  empty <- list(taxon_id = NA_integer_, matched_name = NA_character_,
                rank = NA_character_, n_observations = NA_integer_,
                found = FALSE)

  req <- httr2::request("https://api.inaturalist.org/v1/taxa") |>
    httr2::req_url_query(
      q        = trimws(species_name),
      rank     = "species",
      per_page = 1L
    ) |>
    httr2::req_error(is_error = function(resp) FALSE)

  if (nzchar(api_token))
    req <- req |> httr2::req_headers(Authorization = paste("Bearer", api_token))

  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp)) return(empty)

  status <- httr2::resp_status(resp)
  if (status == 401L)
    stop(
      "audit_inat_coverage: iNaturalist API returned 401 Unauthorized. ",
      "Check your INAT_API_TOKEN or omit api_token to query without authentication."
    )
  if (status != 200L) return(empty)

  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  if (is.null(body) || length(body[["results"]]) == 0L) return(empty)

  r <- body[["results"]][[1L]]
  list(
    taxon_id      = as.integer(r[["id"]] %||% NA_integer_),
    matched_name  = as.character(r[["name"]] %||% NA_character_),
    rank          = as.character(r[["rank"]] %||% NA_character_),
    n_observations = as.integer(r[["observations_count"]] %||% NA_integer_),
    found         = TRUE
  )
}


# ==============================================================================
# audit_inat_coverage()
# ==============================================================================

#' Audit iNaturalist Reference Coverage for a Species List
#'
#' For each species in \code{species_list}, queries the iNaturalist taxa API
#' to retrieve the global observation count and determine whether the species
#' is likely present in iNaturalist's computer vision (CV) training data.
#' Species with fewer than \code{cv_threshold} observations are treated as
#' \strong{unreferenced} for the image classification pathway — they can never
#' appear as CV candidates and must be handled as undetected taxa in
#' \code{TaxaAssign::join_priors()}.
#'
#' This is the image analog of \code{\link{audit_barcode_coverage}}: both
#' functions take a list of prior species, identify which lack classifier
#' references, and return the unreferenced set for downstream handling.
#' Unlike \code{audit_barcode_coverage()}, no authentication is required
#' (the iNaturalist taxa API is publicly accessible); the optional
#' \code{api_token} only relaxes rate limits.
#'
#' @param species_list Character vector. Species names to check (typically
#'   the set of prior taxa, or prior taxa absent from the match object).
#'   Non-binomial names are silently skipped.
#' @param match_df Data frame or \code{NULL}. Optional. If supplied, species
#'   already present in the image match data are annotated as
#'   \code{in_match_data = TRUE}. The species column is auto-detected from
#'   \code{"taxon_name"} or \code{"species"}. Default \code{NULL}.
#' @param cv_threshold Integer. Minimum global observation count on iNaturalist
#'   for a species to be considered present in the CV training data.
#'   Default \code{100L}. The exact iNaturalist threshold is not publicly
#'   documented; 100 research-grade observations is a widely cited approximation.
#'   Species below this threshold are flagged \code{cv_model_included = FALSE}
#'   and included in \code{$unreferenced}.
#' @param api_token Character. Optional iNaturalist API token. When provided,
#'   increases the API rate limit. Defaults to \code{INAT_API_TOKEN} environment
#'   variable; pass \code{api_token = ""} to query without authentication.
#' @param verbose Logical. If \code{TRUE}, prints a progress line for each
#'   species. Default \code{FALSE}.
#' @return A named list with two components:
#'   \describe{
#'     \item{\code{census}}{Data frame with one row per entry in
#'       \code{species_list}, containing: \code{species}, \code{taxon_id},
#'       \code{matched_name} (iNat accepted name), \code{n_observations}
#'       (global iNat count), \code{in_inat} (logical; species found in iNat),
#'       \code{cv_model_included} (logical; \code{n_observations >=
#'       cv_threshold}), \code{unreferenced} (logical; \code{TRUE} when absent
#'       from iNat or below the CV threshold), \code{in_match_data} (logical;
#'       \code{NA} when \code{match_df = NULL}).}
#'     \item{\code{unreferenced}}{Character vector of species either not found
#'       in iNaturalist or below \code{cv_threshold}. Pass to
#'       \code{TaxaLikely::unreferenced_candidates()} to build H2/H3 hypotheses.}
#'   }
#' @details
#' \strong{Rate limiting:} A 0.3-second pause is inserted between API calls.
#' For 100 species, expect approximately 30 seconds.
#'
#' \strong{CV threshold interpretation:} \code{cv_model_included = FALSE} means
#' the species is too rare on iNaturalist for the CV model to have learned a
#' reliable image signature. Such species are photographed too infrequently for
#' training. In practice, marine invertebrates, algae, and many protists fall
#' below this threshold even when present on iNat, while common birds and
#' butterflies almost always exceed it.
#'
#' \strong{Backbone note:} iNaturalist uses its own taxonomy; matched names
#' may differ from GBIF. After retrieving results, run
#' \code{TaxaMatch::convert_taxonomy_backbone()} if you need GBIF-aligned names.
#' @seealso \code{\link{audit_barcode_coverage}},
#'   \code{\link{audit_acoustic_coverage}},
#'   \code{\link{apply_coverage_constraints}}
#' @export
audit_inat_coverage <- function(species_list,
                                match_df      = NULL,
                                cv_threshold  = 100L,
                                api_token     = Sys.getenv("INAT_API_TOKEN"),
                                verbose       = FALSE) {

  # ---- validate ---------------------------------------------------------------
  if (!is.character(species_list) || length(species_list) == 0L)
    stop("audit_inat_coverage: 'species_list' must be a non-empty character vector.",
         call. = FALSE)
  cv_threshold <- as.integer(cv_threshold)
  if (is.na(cv_threshold) || cv_threshold < 0L)
    stop("audit_inat_coverage: 'cv_threshold' must be a non-negative integer.",
         call. = FALSE)
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose))
    stop("audit_inat_coverage: 'verbose' must be TRUE or FALSE.", call. = FALSE)

  species_list <- unique(trimws(species_list))
  species_list <- species_list[nzchar(species_list)]
  n            <- length(species_list)

  if (n == 0L) {
    message("audit_inat_coverage: no valid species names supplied.")
    return(list(
      census = data.frame(
        species = character(0), taxon_id = integer(0),
        matched_name = character(0), n_observations = integer(0),
        in_inat = logical(0), cv_model_included = logical(0),
        unreferenced = logical(0), in_match_data = logical(0),
        stringsAsFactors = FALSE
      ),
      unreferenced = character(0)
    ))
  }

  # ---- match_df annotation ---------------------------------------------------
  match_sp_set <- NULL
  if (!is.null(match_df)) {
    if (!is.data.frame(match_df))
      stop("audit_inat_coverage: 'match_df' must be a data frame or NULL.",
           call. = FALSE)
    sp_col <- if ("taxon_name" %in% names(match_df)) "taxon_name" else
              if ("species"    %in% names(match_df)) "species"    else NULL
    if (!is.null(sp_col))
      match_sp_set <- trimws(tolower(unique(match_df[[sp_col]])))
  }

  # ---- query iNat taxa API per species ---------------------------------------
  message(sprintf(
    "audit_inat_coverage: querying iNaturalist for %d species (0.3s per query)...",
    n
  ))

  rows <- vector("list", n)
  for (i in seq_len(n)) {
    nm <- species_list[[i]]
    if (verbose) message(sprintf("  [%d/%d] %s", i, n, nm))

    info <- .inat_species_info(nm, api_token = api_token)
    Sys.sleep(0.3)

    in_inat      <- info$found
    n_obs        <- info$n_observations
    cv_included  <- in_inat && !is.na(n_obs) && n_obs >= cv_threshold
    unref        <- !cv_included
    in_match     <- if (is.null(match_sp_set)) NA else
                    tolower(nm) %in% match_sp_set

    rows[[i]] <- data.frame(
      species           = nm,
      taxon_id          = info$taxon_id,
      matched_name      = info$matched_name,
      n_observations    = n_obs,
      in_inat           = in_inat,
      cv_model_included = cv_included,
      unreferenced      = unref,
      in_match_data     = in_match,
      stringsAsFactors  = FALSE
    )
  }

  census_df <- do.call(rbind, rows)

  n_in        <- sum(census_df$cv_model_included, na.rm = TRUE)
  n_unref     <- sum(census_df$unreferenced,      na.rm = TRUE)
  message(sprintf(
    paste0("audit_inat_coverage: %d species checked; ",
           "%d likely in CV model (%.0f%%), %d unreferenced."),
    n, n_in, 100 * n_in / n, n_unref
  ))

  unreferenced_sp <- census_df$species[census_df$unreferenced]
  list(census = census_df, unreferenced = unreferenced_sp)
}

utils::globalVariables(c(
  "group", "total", "in_reference", "has_seqs_not_in_ref", "unreferenced", "is_complete",
  "constraint_applied", "is_forbidden", "join_name", "join_rank", "join_status",
  "likelihood_point_est", "likelihood_mean"
))

# Internal helper: normalise species strings to "Genus species" (first 2 words)
.first_two_words <- function(x) {
  vapply(strsplit(trimws(x), "\\s+"), function(w) {
    paste(w[seq_len(min(2L, length(w)))], collapse = " ")
  }, character(1L))
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
      uid_res <- rentrez::entrez_search(
        db   = "taxonomy",
        term = sprintf('"%s"[Genus]', grp)
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
#' ## API strategy
#' Per-species barcode counts use `retmax = 0` (count only, no records
#' returned) with the date filter embedded directly in the query term as a
#' `[PDAT]` range.  This approach (modelled on the UBC
#' `f_search_sequence_by_gene` function) is reliable for both small and
#' large genera and avoids the HTTP 500 errors caused by passing date
#' parameters separately to the NCBI nucleotide API.  Failed queries are
#' retried up to three times with exponential backoff; persistent failures
#' are counted and reported as warnings, and those species are conservatively
#' treated as unreferenced.
#'
#' When `species_list` is NULL, described species are retrieved from the NCBI
#' taxonomy subtree (three taxonomy API calls per genus).
#'
#' @return A named list:
#' \describe{
#'   \item{`census`}{Data frame, one row per genus: `group`, `total`
#'     (described species), `in_reference` (in `match_df`),
#'     `has_seqs_not_in_ref` (barcode sequences exist but not in reference
#'     -- a completeness gap), `unreferenced` (no barcode sequences found),
#'     `is_complete` (TRUE when both gaps are zero).}
#'   \item{`unreferenced`}{Character vector of unreferenced species names, suitable for
#'     `TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)`.}
#' }
#'
#' @note Requires an internet connection and the `rentrez` package.  NCBI
#'   enforces rate limits (3 req/s without an API key; 10 req/s with one).
#'
#' @note **Planned deprecation (Session 34):** This function queries NCBI for
#'   every non-reference species in every genus, which is slow for
#'   species-rich groups.  A future `suggest_unreferenced_species()` function will
#'   use an LLM to pre-filter the candidate list to plausible species before
#'   running the NCBI barcode-count step, dramatically reducing API calls.
#'   The LLM-shortcut workflow ([TaxaAssign::assign_taxa_llm()]) will
#'   integrate this internally.  This function remains correct and is
#'   appropriate for small reference databases or when exhaustive unreferenced
#'   species detection is required regardless of speed.
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
                                   species_list  = NULL,
                                   min_len       = NULL,
                                   max_len       = NULL,
                                   max_date      = NULL,
                                   target_rank   = "genus",
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

        sp_summ <- rentrez::entrez_summary(db = "taxonomy", id = sp_res$ids)
        if (inherits(sp_summ, "esummary")) sp_summ <- list(sp_summ)

        raw <- vapply(sp_summ, `[[`, character(1L), "scientificname")
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
    if (i < length(genera)) Sys.sleep(.ncbi_delay())
  }
  cli::cli_progress_done(id = pb)

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
                                    match_df = NULL) {

  # ---- validate inputs -------------------------------------------------------
  if (!is.character(plausible_species) || length(plausible_species) == 0L)
    stop("audit_acoustic_coverage: 'plausible_species' must be a non-empty character vector.",
         call. = FALSE)
  if (!is.character(reference_species) || length(reference_species) == 0L)
    stop("audit_acoustic_coverage: 'reference_species' must be a non-empty character vector.",
         call. = FALSE)

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

  # ---- build census data frame -----------------------------------------------
  census_df <- data.frame(
    species       = plausible_norm,
    in_reference  = in_ref,
    unreferenced  = !in_ref,
    in_match_data = in_match,
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
#'   applied to `likelihood_point_est` and `likelihood_mean` for constrained
#'   hypotheses when `constraint_behavior = "zero"`.  Ignored when
#'   `constraint_behavior = "relabel"`.
#' @param constraint_behavior Character scalar: `"zero"` (default) or
#'   `"relabel"`.  See Details above.
#'
#' @return `likelihood_df` with an added `constraint_applied` column and
#'   updated likelihood and/or `hypothesis_type` columns:
#'   \describe{
#'     \item{`"zero"` mode}{`likelihood_point_est` and `likelihood_mean`
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
                  "likelihood_point_est", "likelihood_mean")
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
        likelihood_point_est = ifelse(is_forbidden,
                                      likelihood_point_est * penalty_factor,
                                      likelihood_point_est),
        likelihood_mean      = ifelse(is_forbidden,
                                      likelihood_mean * penalty_factor,
                                      likelihood_mean),
        constraint_applied   = ifelse(is_forbidden,
                                      "census_closed_genus", NA_character_)
      ) |>
      dplyr::select(-join_name, -join_rank, -join_status, -is_forbidden)
  }

  result
}

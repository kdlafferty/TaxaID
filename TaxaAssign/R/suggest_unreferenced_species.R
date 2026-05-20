# suggest_unreferenced_species.R
# TaxaAssign package
#
# LLM-first unreferenced species detection for eDNA / barcode-based taxonomic assignment.
# The LLM generates biogeographically plausible species per genus; NCBI barcode-count
# queries run only on the plausible remainder after the reference skip-list is removed.
# This is dramatically faster than exhaustive genus-level NCBI queries (TaxaLikely::
# audit_barcode_coverage()) for species-rich genera.
#
# Optional family-level expansion (expand_to_family = TRUE): when a genus has no
# plausible species (LLM found none), the function asks the LLM for plausible species
# in OTHER genera of the same family, then NCBI-confirms those as unreferenced. This is
# the named-species analogue of TaxaLikely's H3 (unreferenced genus) hypothesis.
#
# Exported functions:
#   suggest_unreferenced_species()  LLM-first unreferenced species detection -> character vector (unreferenced_species_result)
#   print.unreferenced_species_result            S3 print method for unreferenced_species_result
#
# Internal helpers:
#   .build_plausible_prompt()   Genus-level prompt: genera list + context
#   .parse_plausible_response() Parse JSON array -> named list (genus -> species vec)
#   .build_family_prompt()      Family-level prompt: family + excluded genera + context
#   .parse_family_response()    Parse flat JSON species array for family expansion
#   .count_barcode_seqs()       NCBI nucleotide retmax=0 count for one species
#   .new_unreferenced_species_result()           Construct unreferenced_species_result S3 object
#
# Barcode helpers (copied from TaxaLikely -- TaxaLikely internals cannot be imported):
#   .barcode_length_defaults    Named list of min/max bp per barcode type
#   TaxaTools::resolve_barcode_lengths()  Resolve min/max bp for a barcode_term vector
#   TaxaTools::is_valid_species_name()    Filter non-binomial / sp. / cf. / aff. names

# ==============================================================================
# Barcode helpers (private copies; same logic as TaxaLikely/R/coverage.R)
# ==============================================================================

# ==============================================================================
# Internal helpers for genus-level plausible species
# ==============================================================================

#' Build a plausible-species prompt for one batch of genera
#' @noRd
.build_plausible_prompt <- function(genera, ctx) {
  ctx_fields   <- c("ecoregion", "lat", "lon", "date", "habitat")
  header_parts <- character(0L)
  for (fld in ctx_fields) {
    v <- ctx[[fld]]
    if (!is.null(v) && length(v) == 1L && !is.na(v) && nzchar(trimws(as.character(v)))) {
      label <- switch(fld,
        ecoregion = "Ecoregion", lat = "Latitude", lon = "Longitude",
        date = "Date/season", habitat = "Habitat", fld
      )
      header_parts <- c(header_parts, paste0(label, ": ", as.character(v)))
    }
  }
  ctx_block <- if (length(header_parts) > 0L)
    paste0("Context:\n", paste0("  ", header_parts, collapse = "\n"), "\n\n")
  else
    ""

  ex1 <- genera[[1L]]
  if (length(genera) >= 2L) {
    ex2 <- genera[[2L]]
    format_example <- paste0(
      "[\n",
      "  {\"genus\": \"", ex1, "\", \"plausible_species\": [",
      "\"", ex1, " speciesA\", \"", ex1, " speciesB\"]},\n",
      "  {\"genus\": \"", ex2, "\", \"plausible_species\": [",
      "\"", ex2, " speciesC\"]},\n",
      "  ...\n",
      "]"
    )
  } else {
    format_example <- paste0(
      "[\n",
      "  {\"genus\": \"", ex1, "\", \"plausible_species\": [",
      "\"", ex1, " speciesA\"]}\n",
      "]"
    )
  }

  paste0(
    "OUTPUT REQUIREMENT: Your ENTIRE response must be ONE valid JSON array.\n",
    "Do not include any text before or after the JSON array.\n",
    "You MUST include EVERY genus listed below -- no exceptions.\n\n",
    "Act as an expert wildlife biologist, biogeographer, and taxonomist.\n\n",
    ctx_block,
    "TASK: For each genus below, list ALL species that are plausible at this location.\n\n",
    "INCLUDE a species if it is:\n",
    "  - native to this region\n",
    "  - introduced and established near this location\n",
    "  - an occasional visitor or vagrant with documented occurrences nearby\n\n",
    "EXCLUDE a species ONLY if it is biogeographically impossible at this location\n",
    "  (e.g., wrong continent, wrong realm, freshwater genus at marine site).\n\n",
    "IMPORTANT: Include ALL plausible species, even if rare or seldom recorded.\n",
    "A separate NCBI sequence-availability check will filter species that have no\n",
    "barcode sequences -- do not pre-filter based on sequence availability.\n\n",
    "Use full binomial names (\"Fundulus parvipinnis\", not \"F. parvipinnis\").\n",
    "Use an empty array [] for a genus with no plausible local species.\n\n",
    "Required output format:\n",
    format_example, "\n\n",
    "Genera to assess:\n",
    paste0("- ", genera, collapse = "\n")
  )
}


#' Parse genus-level JSON array response into a named list (genus -> species vector)
#' @noRd
.parse_plausible_response <- function(response, genera, group_label = "all") {
  empty_result <- lapply(stats::setNames(genera, genera), function(g) character(0L))

  if (is.null(response) || !nzchar(trimws(response))) {
    cli::cli_warn(
      "Empty LLM response for {.val {group_label}}. Returning empty species lists."
    )
    return(empty_result)
  }

  # Extract JSON array -- (?s) enables PCRE dotall so .* matches newlines
  arr_str <- sub("(?s).*?(\\[[\\s\\S]*\\]).*", "\\1", response, perl = TRUE)

  parsed <- tryCatch(
    jsonlite::fromJSON(arr_str, simplifyDataFrame = FALSE, simplifyVector = TRUE),
    error = function(e) NULL
  )

  if (is.null(parsed) || !is.list(parsed)) {
    cli::cli_warn(
      "Failed to parse JSON response for {.val {group_label}}. \\
      Returning empty species lists."
    )
    return(empty_result)
  }

  result <- empty_result

  for (item in parsed) {
    if (!is.list(item) ||
        !"genus" %in% names(item) ||
        !"plausible_species" %in% names(item))
      next

    g   <- as.character(item$genus)[[1L]]
    sps <- as.character(item$plausible_species)
    valid <- unique(sps[TaxaTools::is_valid_species_name(sps)])

    if (g %in% genera)
      result[[g]] <- valid
  }

  empty_genera <- genera[vapply(result, length, integer(1L)) == 0L]
  if (length(empty_genera) > 0L)
    cli::cli_warn(
      "{length(empty_genera)} genus/genera had no valid plausible species \\
      in LLM response for {.val {group_label}}: {.val {empty_genera}}"
    )

  result
}


# ==============================================================================
# Internal helpers for family-level expansion
# ==============================================================================

#' Build a plausible-species prompt for one family (excluding known genera)
#' @noRd
.build_family_prompt <- function(family, exclude_genera, ctx) {
  ctx_fields   <- c("ecoregion", "lat", "lon", "date", "habitat")
  header_parts <- character(0L)
  for (fld in ctx_fields) {
    v <- ctx[[fld]]
    if (!is.null(v) && length(v) == 1L && !is.na(v) && nzchar(trimws(as.character(v)))) {
      label <- switch(fld,
        ecoregion = "Ecoregion", lat = "Latitude", lon = "Longitude",
        date = "Date/season", habitat = "Habitat", fld
      )
      header_parts <- c(header_parts, paste0(label, ": ", as.character(v)))
    }
  }
  ctx_block <- if (length(header_parts) > 0L)
    paste0("Context:\n", paste0("  ", header_parts, collapse = "\n"), "\n\n")
  else
    ""

  paste0(
    "OUTPUT REQUIREMENT: Your ENTIRE response must be ONE valid JSON array.\n",
    "Do not include any text before or after the JSON array.\n\n",
    "Act as an expert wildlife biologist, biogeographer, and taxonomist.\n\n",
    ctx_block,
    "TASK: List species in family ", family, " that could plausibly occur at this location,\n",
    "from genera OTHER THAN those listed below (which are already in the dataset):\n",
    paste0("  - ", exclude_genera, collapse = "\n"), "\n\n",
    "For each species, commit to a range_status BEFORE deciding to include it.\n",
    "ONLY include species with range_status in:\n",
    "  \"native\"               -- breeds/resides here, well-documented\n",
    "  \"introduced_established\" -- non-native but established near this location\n",
    "  \"documented_nearby\"    -- documented in the broader region; occasional here\n\n",
    "DO NOT include species with range_status:\n",
    "  \"not_documented\"       -- no records from this region\n",
    "  \"taxonomically_impossible\" -- wrong continent, realm, or habitat type\n",
    "  \"uncertain\"            -- insufficient information to assess range\n\n",
    "ALSO EXCLUDE:\n",
    "  - any species from the genera listed above\n\n",
    "A separate NCBI sequence check will filter species lacking barcode sequences.\n",
    "Do not pre-filter based on sequence availability.\n\n",
    "Use full binomial names (\"Lucania parva\", not \"L. parva\").\n",
    "Return an empty array [] if no other genera in this family are plausible here.\n\n",
    "Required output format:\n",
    "[{\"species\": \"Lucania parva\", \"range_status\": \"native\"},\n",
    " {\"species\": \"Lucania goodei\", \"range_status\": \"documented_nearby\"}]"
  )
}


#' Parse family-level JSON array response into a character vector of species names
#'
#' Expects objects with "species" + "range_status" fields. Only species with
#' range_status in the plausible set (native, introduced_established,
#' documented_nearby) are returned. This filters implausible hypotheses before
#' any NCBI queries.
#' @noRd
.parse_family_response <- function(response, family, exclude_genera,
                                    group_label = "all") {
  plausible_statuses <- c("native", "introduced_established", "documented_nearby")

  if (is.null(response) || !nzchar(trimws(response))) {
    cli::cli_warn(
      "Empty LLM response for family {.val {family}} ({.val {group_label}}). \\
      Returning empty species list."
    )
    return(character(0L))
  }

  # Extract JSON array -- (?s) PCRE dotall so .* matches newlines
  arr_str <- sub("(?s).*?(\\[[\\s\\S]*\\]).*", "\\1", response, perl = TRUE)

  parsed <- tryCatch(
    jsonlite::fromJSON(arr_str, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )

  if (is.null(parsed)) {
    cli::cli_warn(
      "Failed to parse family response for {.val {family}} ({.val {group_label}}). \\
      Returning empty species list."
    )
    return(character(0L))
  }

  # Handle empty array []
  if (is.list(parsed) && length(parsed) == 0L) return(character(0L))
  if (is.data.frame(parsed) && nrow(parsed) == 0L) return(character(0L))

  # Accept new format: data frame with "species" + "range_status" columns
  # Also accept fallback: plain character vector (old format / LLM non-compliance)
  if (is.data.frame(parsed) && "species" %in% names(parsed)) {
    spp <- as.character(parsed$species)
    if ("range_status" %in% names(parsed)) {
      rs  <- as.character(parsed$range_status)
      spp <- spp[rs %in% plausible_statuses]
    }
  } else if (is.character(parsed)) {
    # Fallback: plain string array -- accept all, no range filter possible
    cli::cli_warn(
      "Family response for {.val {family}} was a plain species array with no \\
      range_status. Accepting all names; consider re-running for better filtering."
    )
    spp <- as.character(parsed)
  } else {
    cli::cli_warn(
      "Family response for {.val {family}} was not in expected format. \\
      Returning empty species list."
    )
    return(character(0L))
  }

  # Validate binomials and remove excluded genera
  valid        <- spp[TaxaTools::is_valid_species_name(spp)]
  valid_genera <- sub(" .*", "", valid)
  unique(valid[!valid_genera %in% exclude_genera])
}


# ==============================================================================
# NCBI count helper
# ==============================================================================

#' Query NCBI nucleotide for barcode sequence count (retmax = 0)
#'
#' Returns the integer count (0 = unreferenced), or NA_integer_ if all three
#' attempts fail (treated conservatively as unreferenced by the caller).
#' @noRd
.count_barcode_seqs <- function(sp, barcode_clause, len_range, date_clause) {
  term <- sprintf('"%s"[Organism] AND %s AND %d:%d[SLEN]%s',
                  sp, barcode_clause, len_range[1L], len_range[2L], date_clause)
  for (attempt in seq_len(3L)) {
    res <- tryCatch(
      rentrez::entrez_search(db = "nuccore", term = term, retmax = 0L),
      error = function(e) NULL
    )
    if (!is.null(res) && !is.null(res$count))
      return(as.integer(res$count))
    Sys.sleep(attempt)   # exponential backoff: 1 s, 2 s, 3 s
  }
  NA_integer_
}


# ==============================================================================
# unreferenced_species_result S3 object helpers
# ==============================================================================

#' Construct an unreferenced_species_result S3 object (character vector + attributes)
#' @noRd
.new_unreferenced_species_result <- function(unreferenced, plausible, census,
                              unreferenced_family = NULL, family_census = NULL) {
  structure(
    unreferenced,
    plausible     = plausible,
    census        = census,
    unreferenced_family  = unreferenced_family,
    family_census = family_census,
    class         = c("unreferenced_species_result", "character")
  )
}


# ==============================================================================
# S3 methods for unreferenced_species_result
# ==============================================================================

#' Print method for unreferenced_species_result
#'
#' Displays a compact summary of unreferenced species found.
#' Full details are available via `attr(x, "census")`, `attr(x, "plausible")`,
#' and (when family expansion was used) `attr(x, "unreferenced_family")` (family-level map) and
#' `attr(x, "family_census")`.
#'
#' @param x An `unreferenced_species_result` object (returned by [suggest_unreferenced_species()]).
#' @param ... Not used.
#' @return `x`, invisibly.
#' @examples
#' \dontrun{
#' unref <- suggest_unreferenced_species(match_df, llm_fn = call_anthropic_api)
#' print(unref)
#' }
#' @export
print.unreferenced_species_result <- function(x, ...) {
  n <- length(x)
  if (n == 0L) {
    cat("Unreferenced species detected: 0\n")
  } else {
    cat(sprintf("Unreferenced species detected (%d):\n", n))
    show_n <- min(n, 10L)
    for (i in seq_len(show_n))
      cat(sprintf("  %s\n", x[[i]]))
    if (n > 10L)
      cat(sprintf("  ... and %d more\n", n - 10L))
  }
  fam_census <- attr(x, "family_census")
  if (!is.null(fam_census) && nrow(fam_census) > 0L) {
    n_fam <- sum(fam_census$unreferenced_count, na.rm = TRUE)
    cat(sprintf("  (%d are family-level unreferenced species from %d family/families)\n",
                n_fam, nrow(fam_census)))
  }
  cat("Access full details: attr(x, \"census\") | attr(x, \"plausible\")")
  if (!is.null(fam_census))
    cat(" | attr(x, \"unreferenced_family\") | attr(x, \"family_census\") (family-level details)")
  cat("\n")
  invisible(x)
}


# ==============================================================================
# Main exported function
# ==============================================================================

#' Suggest Unreferenced Species Using an LLM
#'
#' A fast, LLM-first alternative to [TaxaLikely::audit_barcode_coverage()] for
#' unreferenced species detection.  An **unreferenced species** is a described taxon
#' that shares a genus (or family, with `expand_to_family = TRUE`) with a scored
#' reference match candidate but has **no barcode sequence** for the target marker in NCBI.
#'
#' ## Algorithm
#' \enumerate{
#'   \item **Genus-level LLM call:** For each genus in `match_df`, the LLM lists
#'     all biogeographically plausible species.  Genera are batched by
#'     `taxa_per_call`.
#'   \item **Skip-list removal:** Species already in `match_df` have reference
#'     sequences by definition and are removed from the candidate list.
#'   \item **NCBI barcode count:** For each remaining plausible species,
#'     `rentrez::entrez_search()` is called with `retmax = 0` (count only).
#'     Count = 0 or persistent failure (NA after 3 retries) \eqn{\to}{->} unreferenced.
#'   \item **Family-level expansion (optional):** When `expand_to_family = TRUE`,
#'     genera for which the LLM found **zero** plausible species trigger a
#'     second LLM call asking for plausible species in **other genera** of the
#'     same family.  Those candidates go through the same NCBI count step.
#'     Requires a `family` column in `match_df`.
#' }
#'
#' ## Return value
#' The visible return is a character vector of unreferenced species names of class
#' `c("unreferenced_species_result", "character")`, suitable for direct use as
#' `assign_taxa_llm(unreferenced_taxa = ...)`.  `assign_taxa_llm` automatically
#' detects the `unreferenced_family` attribute and activates family-level
#' unreferenced species insertion when it is present.
#'
#' Additional details are attached as attributes:
#' \itemize{
#'   \item `attr(result, "plausible")` -- all LLM-generated species (genus-level)
#'     before the NCBI filter (character vector).
#'   \item `attr(result, "census")` -- data frame with one row per genus:
#'     `genus`, `plausible_count`, `ncbi_count`, `unreferenced_count`.
#'   \item `attr(result, "unreferenced_family")` -- named character vector mapping each
#'     family-level unreferenced species to its family name.  `NULL` when
#'     `expand_to_family = FALSE` or when no family-level unreferenced species were found.
#'   \item `attr(result, "family_census")` -- data frame with one row per
#'     expanded family: `family`, `plausible_count`, `ncbi_count`, `unreferenced_count`.
#'     `NULL` when `expand_to_family = FALSE`.
#' }
#'
#' @param match_df Data frame.  Canonical match object from TaxaMatch (or
#'   equivalent).  Required column: `taxon_name`.  Optional but strongly
#'   recommended: `genus` (if absent, derived from `taxon_name`).  Required
#'   for `expand_to_family = TRUE`: `family`.
#' @param context Optional named list or single-row data frame with location /
#'   habitat context for the LLM.  Recognised fields: `ecoregion`, `lat`,
#'   `lon`, `date`, `habitat`.  NULL (default) sends no context.
#' @param barcode_term Character scalar or vector.  One or more marker search
#'   terms (e.g. `"12S"`, `c("12S", "MiFish")`).  Multiple terms are OR-ed.
#'   Default `"COI"`.
#' @param llm_fn Function or NULL.  Provider function following the TaxaTools
#'   `llm_fn` pattern: accepts a single character string prompt and returns a
#'   single character string response.  Default NULL resolves to
#'   `TaxaTools::call_anthropic_api` (requires TaxaTools).
#' @param expand_to_family Logical.  If `TRUE`, genera for which the LLM
#'   returned zero plausible species trigger a second LLM call asking for
#'   plausible species in OTHER genera of the same family.  These
#'   **family-level unreferenced species** fill the role of TaxaLikely's H3 (unreferenced genus)
#'   hypothesis with named species.  Requires a `family` column in `match_df`.
#'   Default `FALSE`.
#' @param max_date Optional character scalar.  Restricts unreferenced species detection to
#'   sequences present in NCBI on or before this date.  Format: `"YYYY"`,
#'   `"YYYY/MM"`, or `"YYYY/MM/DD"`.  NULL uses the current state of GenBank.
#' @param min_len Integer or NULL.  Minimum sequence length (`SLEN` filter).
#'   NULL uses a barcode-specific default.
#' @param max_len Integer or NULL.  Maximum sequence length.  NULL uses the
#'   barcode-specific default.
#' @param taxa_per_call Integer >= 1.  Maximum genera per LLM call.  Default 30.
#' @param pause_seconds Numeric.  Seconds to pause between LLM calls.  Default 1.
#' @param ncbi_api_key Optional NCBI API key.  Raises rate limit from 3 to 10
#'   requests per second.  Can also be set via the `ENTREZ_KEY` environment
#'   variable.
#' @param verbose Logical.  If `TRUE`, prints each prompt and raw LLM response.
#'   Default `FALSE`.
#'
#' @return A character vector of unreferenced species names with class
#'   `c("unreferenced_species_result", "character")`.  `length()` returns the total number of
#'   unreferenced species (congener + family-level combined).  Pass directly to
#'   `assign_taxa_llm(unreferenced_taxa = ...)`.
#'
#' @seealso [assign_taxa_llm()] to use the returned unreferenced species names in the
#'   Bayesian assignment pipeline.
#'   [TaxaLikely::audit_barcode_coverage()] for exhaustive (slower)
#'   unreferenced species detection that does not require an LLM.
#'
#' @importFrom cli cli_abort cli_inform cli_warn cli_progress_bar
#'   cli_progress_update cli_progress_done
#' @importFrom jsonlite fromJSON
#' @importFrom stats setNames
#'
#' @export
#'
#' @examples
#' \dontrun{
#' match_df <- readRDS(
#'   system.file("match_obj.rds", package = "TaxaMatch")
#' )
#'
#' ctx <- data.frame(
#'   ecoregion = "Southern California Bight",
#'   habitat   = "estuarine / coastal lagoon"
#' )
#'
#' # Genus-level unreferenced species only
#' unref_names <- suggest_unreferenced_species(
#'   match_df, context = ctx, barcode_term = "12S",
#'   llm_fn = TaxaTools::call_anthropic_api, max_date = "2024/12/31"
#' )
#' cat("Unreferenced taxa found:", length(unref_names), "\n")
#'
#' # With family-level expansion for genera with no local species
#' unref_names <- suggest_unreferenced_species(
#'   match_df, context = ctx, barcode_term = "12S",
#'   expand_to_family = TRUE, max_date = "2024/12/31"
#' )
#' attr(unref_names, "family_census")
#'
#' # Pass directly to assign_taxa_llm
#' result <- assign_taxa_llm(match_df, context = ctx, unreferenced_taxa = unref_names)
#' }
suggest_unreferenced_species <- function(match_df,
                                      context          = NULL,
                                      barcode_term     = "COI",
                                      llm_fn           = NULL,
                                      expand_to_family = FALSE,
                                      max_date         = NULL,
                                      min_len          = NULL,
                                      max_len          = NULL,
                                      taxa_per_call    = 30L,
                                      pause_seconds    = 1,
                                      ncbi_api_key     = NULL,
                                      verbose          = FALSE) {

  # ---- Resolve llm_fn default --------------------------------------------------
  llm_fn <- .resolve_llm_fn(llm_fn, "suggest_unreferenced_species")

  # ---- Input validation -------------------------------------------------------
  if (!is.data.frame(match_df))
    cli::cli_abort("{.arg match_df} must be a data frame.")
  if (!"taxon_name" %in% names(match_df))
    cli::cli_abort("{.arg match_df} must have a {.field taxon_name} column.")
  if (!is.character(barcode_term) || length(barcode_term) == 0L ||
      any(is.na(barcode_term)) || any(!nzchar(trimws(barcode_term))))
    cli::cli_abort(
      "{.arg barcode_term} must be a non-empty character vector with no NA values."
    )
  if (!is.null(max_date)) {
    if (!is.character(max_date) || length(max_date) != 1L || is.na(max_date))
      cli::cli_abort("{.arg max_date} must be a single character string or NULL.")
    if (!grepl("^\\d{4}(/\\d{2}(/\\d{2})?)?$", trimws(max_date)))
      cli::cli_abort(
        "{.arg max_date} must be in YYYY, YYYY/MM, or YYYY/MM/DD format."
      )
  }
  if (!is.function(llm_fn))
    cli::cli_abort("{.arg llm_fn} must be a function.")
  if (!is.logical(expand_to_family) || length(expand_to_family) != 1L ||
      is.na(expand_to_family))
    cli::cli_abort("{.arg expand_to_family} must be TRUE or FALSE.")
  if (isTRUE(expand_to_family) && !"family" %in% names(match_df))
    cli::cli_abort(
      "{.arg expand_to_family} = TRUE requires a {.field family} column in {.arg match_df}."
    )
  if (!is.numeric(taxa_per_call) || taxa_per_call < 1L)
    cli::cli_abort("{.arg taxa_per_call} must be a positive number.")
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose))
    cli::cli_abort("{.arg verbose} must be TRUE or FALSE.")

  if (!requireNamespace("rentrez", quietly = TRUE))
    cli::cli_abort(
      "Package {.pkg rentrez} is required. \\
      Install with: {.code install.packages('rentrez')}"
    )

  # ---- Extract genera and build skip-list ------------------------------------
  if ("genus" %in% names(match_df)) {
    genera <- unique(stats::na.omit(match_df$genus))
    genera <- genera[nchar(trimws(genera)) > 0L]
  } else {
    sp_names <- match_df$taxon_name[TaxaTools::is_valid_species_name(match_df$taxon_name)]
    genera   <- unique(sub(" .*", "", sp_names))
  }
  genera <- sort(genera[nchar(trimws(genera)) > 0L])

  if (length(genera) == 0L) {
    cli::cli_warn("No valid genera found in {.arg match_df}. Returning empty result.")
    empty_census <- data.frame(genus = character(0L), plausible_count = integer(0L),
                               ncbi_count = integer(0L), unreferenced_count = integer(0L),
                               stringsAsFactors = FALSE)
    return(.new_unreferenced_species_result(character(0L), character(0L), empty_census))
  }

  # Skip-list: species already in match_df have reference sequences by definition
  skip_list <- unique(
    match_df$taxon_name[TaxaTools::is_valid_species_name(match_df$taxon_name)]
  )

  # ---- Normalise context to a named list -------------------------------------
  ctx <- if (is.data.frame(context)) {
    as.list(context[1L, setdiff(names(context), "observation_id"), drop = FALSE])
  } else if (is.list(context)) {
    context
  } else {
    list()
  }

  # ---- Step 2: LLM calls to get plausible species per genus ------------------
  n_genera  <- length(genera)
  tpc       <- as.integer(taxa_per_call)
  n_batches <- ceiling(n_genera / tpc)

  cli::cli_inform(
    "Querying LLM for plausible species: {n_genera} genus/genera, \\
    {n_batches} API call(s) ({tpc} genera/call max)."
  )

  all_plausible_list <- stats::setNames(
    lapply(genera, function(g) character(0L)),
    genera
  )

  pb_llm <- cli::cli_progress_bar(
    total  = n_batches,
    format = "  {cli::pb_bar} {cli::pb_current}/{cli::pb_total} LLM calls"
  )

  for (b in seq_len(n_batches)) {
    idx_start    <- (b - 1L) * tpc + 1L
    idx_end      <- min(b * tpc, n_genera)
    batch_genera <- genera[idx_start:idx_end]
    batch_label  <- if (n_batches > 1L)
      sprintf("batch %d/%d", b, n_batches)
    else
      "all"

    prompt <- .build_plausible_prompt(batch_genera, ctx)

    if (verbose) {
      cli::cli_inform(
        "--- LLM call {b}/{n_batches}: {length(batch_genera)} genera ({batch_label}) ---"
      )
      cat(prompt, "\n")
    }

    raw <- tryCatch(
      llm_fn(prompt),
      error = function(e) {
        cli::cli_warn(
          "LLM call failed for {.val {batch_label}}: {conditionMessage(e)}"
        )
        NULL
      }
    )

    if (verbose && !is.null(raw)) {
      cli::cli_inform("--- Response ---")
      cat(raw, "\n")
    }

    # When raw is NULL (LLM error already warned above), skip parsing
    batch_parsed <- if (is.null(raw)) {
      lapply(stats::setNames(batch_genera, batch_genera), function(g) character(0L))
    } else {
      .parse_plausible_response(raw, batch_genera, batch_label)
    }
    for (g in batch_genera)
      all_plausible_list[[g]] <- batch_parsed[[g]]

    cli::cli_progress_update(id = pb_llm)
    if (b < n_batches) Sys.sleep(pause_seconds)
  }

  cli::cli_progress_done(id = pb_llm)

  # All LLM-generated plausible species (before skip-list removal and NCBI filter)
  all_plausible_flat <- unique(unlist(all_plausible_list, use.names = FALSE))

  # ---- Step 3: Remove skip-list ----------------------------------------------
  candidates <- all_plausible_flat[!all_plausible_flat %in% skip_list]

  # ---- Step 4: NCBI setup (shared by genus and family loops) -----------------
  # Determine whether any NCBI queries are needed before setting up
  empty_genera_for_family <- if (isTRUE(expand_to_family))
    genera[vapply(all_plausible_list, length, integer(1L)) == 0L]
  else
    character(0L)

  needs_ncbi <- length(candidates) > 0L || length(empty_genera_for_family) > 0L

  if (needs_ncbi) {
    if (!is.null(ncbi_api_key))
      rentrez::set_entrez_key(ncbi_api_key)

    len_range <- TaxaTools::resolve_barcode_lengths(barcode_term, min_len, max_len)

    barcode_clause <- if (length(barcode_term) == 1L) {
      sprintf("%s[All Fields]", barcode_term)
    } else {
      sprintf("(%s)",
              paste(sprintf("%s[All Fields]", barcode_term), collapse = " OR "))
    }

    date_clause <- if (!is.null(max_date)) {
      sprintf(" AND (1985[PDAT] : %s[PDAT])", trimws(max_date))
    } else ""
  }

  # ---- Step 5: Genus-level NCBI barcode count --------------------------------
  unref_vec    <- character(0L)
  has_seqs_vec <- character(0L)
  n_failed     <- 0L

  if (length(candidates) > 0L) {
    n_cands  <- length(candidates)
    term_str <- paste(barcode_term, collapse = "/")

    cli::cli_inform(
      "Checking NCBI barcode counts for {n_cands} plausible species \\
      (barcode: '{term_str}', {len_range[1]}-{len_range[2]} bp)..."
    )

    pb_ncbi <- cli::cli_progress_bar(
      total  = n_cands,
      format = "  {cli::pb_bar} {cli::pb_current}/{cli::pb_total} NCBI queries"
    )

    for (k in seq_len(n_cands)) {
      sp    <- candidates[k]
      count <- .count_barcode_seqs(sp, barcode_clause, len_range, date_clause)

      if (is.na(count)) {
        n_failed  <- n_failed + 1L
        unref_vec <- c(unref_vec, sp)
      } else if (count == 0L) {
        unref_vec <- c(unref_vec, sp)
      } else {
        has_seqs_vec <- c(has_seqs_vec, sp)
      }

      cli::cli_progress_update(id = pb_ncbi)
      if (k %% 3L == 0L) Sys.sleep(0.35)
    }

    cli::cli_progress_done(id = pb_ncbi)

    if (n_failed > 0L)
      cli::cli_warn(
        "{n_failed} NCBI barcode {?query/queries} failed after 3 attempts \\
        (treated conservatively as unreferenced{?/})."
      )
  } else if (!isTRUE(expand_to_family)) {
    cli::cli_inform(
      "All LLM-suggested species are already in the reference. No genus-level unreferenced species."
    )
  }

  # ---- Step 6: Build genus census --------------------------------------------
  census_df <- do.call(rbind, lapply(genera, function(g) {
    p       <- all_plausible_list[[g]]
    cands_g <- p[!p %in% skip_list]
    data.frame(
      genus           = g,
      plausible_count = length(p),
      ncbi_count      = sum(cands_g %in% has_seqs_vec),
      unreferenced_count     = sum(cands_g %in% unref_vec),
      stringsAsFactors = FALSE
    )
  }))

  # ---- Step 7: Family-level expansion (optional) -----------------------------
  unreferenced_family_map <- NULL
  family_census_df <- NULL

  if (isTRUE(expand_to_family) && length(empty_genera_for_family) > 0L) {

    # Look up family for each empty genus from match_df
    genus_to_family_lookup <- vapply(empty_genera_for_family, function(g) {
      fam <- match_df$family[!is.na(match_df$genus) & match_df$genus == g &
                               !is.na(match_df$family)]
      if (length(fam) > 0L) fam[[1L]] else NA_character_
    }, character(1L))

    has_fam            <- !is.na(genus_to_family_lookup)
    empty_with_fam     <- empty_genera_for_family[has_fam]
    families_to_expand <- unique(genus_to_family_lookup[has_fam])

    if (length(families_to_expand) > 0L) {
      cli::cli_inform(
        "{length(empty_with_fam)} empty genus/genera triggering family-level \\
        expansion in {length(families_to_expand)} family/families: \\
        {.val {families_to_expand}}"
      )

      all_fam_unref_vec    <- character(0L)
      all_fam_has_seqs_vec <- character(0L)
      fam_plausible_list   <- stats::setNames(
        lapply(families_to_expand, function(f) character(0L)),
        families_to_expand
      )

      pb_fam <- cli::cli_progress_bar(
        total  = length(families_to_expand),
        format = "  {cli::pb_bar} {cli::pb_current}/{cli::pb_total} family calls"
      )

      for (f_idx in seq_along(families_to_expand)) {
        fam <- families_to_expand[[f_idx]]

        # Exclude ALL genera in match_df belonging to this family
        exclude_genera <- unique(
          match_df$genus[!is.na(match_df$family) & match_df$family == fam &
                           !is.na(match_df$genus)]
        )

        prompt_fam <- .build_family_prompt(fam, exclude_genera, ctx)

        if (verbose) {
          cli::cli_inform(
            "--- Family expansion: {fam} ({length(exclude_genera)} excluded genera) ---"
          )
          cat(prompt_fam, "\n")
        }

        raw_fam <- tryCatch(
          llm_fn(prompt_fam),
          error = function(e) {
            cli::cli_warn(
              "LLM call failed for family {.val {fam}}: {conditionMessage(e)}"
            )
            NULL
          }
        )

        if (verbose && !is.null(raw_fam)) {
          cli::cli_inform("--- Response ---")
          cat(raw_fam, "\n")
        }

        fam_species <- if (is.null(raw_fam)) {
          character(0L)
        } else {
          .parse_family_response(raw_fam, fam, exclude_genera, fam)
        }

        fam_candidates         <- fam_species[!fam_species %in% skip_list]
        fam_plausible_list[[fam]] <- fam_species

        n_fam_cands <- length(fam_candidates)
        if (n_fam_cands > 0L) {
          cli::cli_inform(
            "  Family {.val {fam}}: checking {n_fam_cands} candidate(s)..."
          )
          n_fam_failed <- 0L

          for (k in seq_len(n_fam_cands)) {
            sp    <- fam_candidates[k]
            count <- .count_barcode_seqs(sp, barcode_clause, len_range, date_clause)

            if (is.na(count)) {
              n_fam_failed         <- n_fam_failed + 1L
              all_fam_unref_vec    <- c(all_fam_unref_vec, sp)
            } else if (count == 0L) {
              all_fam_unref_vec    <- c(all_fam_unref_vec, sp)
            } else {
              all_fam_has_seqs_vec <- c(all_fam_has_seqs_vec, sp)
            }

            if (k %% 3L == 0L) Sys.sleep(0.35)
          }

          if (n_fam_failed > 0L)
            cli::cli_warn(
              "{n_fam_failed} NCBI {?query/queries} failed for family \\
              {.val {fam}} (treated as unreferenced{?/})."
            )
        }

        cli::cli_progress_update(id = pb_fam)
        if (f_idx < length(families_to_expand)) Sys.sleep(pause_seconds)
      }

      cli::cli_progress_done(id = pb_fam)

      # Build unreferenced_family_map: named vector species -> family
      gfm_parts <- lapply(families_to_expand, function(f) {
        cands   <- fam_plausible_list[[f]][!fam_plausible_list[[f]] %in% skip_list]
        unref_f <- cands[cands %in% all_fam_unref_vec]
        if (length(unref_f) > 0L)
          stats::setNames(rep(f, length(unref_f)), unref_f)
        else
          character(0L)
      })
      unreferenced_family_map <- unlist(gfm_parts)
      if (length(unreferenced_family_map) == 0L) unreferenced_family_map <- NULL

      unref_vec <- c(unref_vec, all_fam_unref_vec)

      # Build family census
      family_census_df <- do.call(rbind, lapply(families_to_expand, function(f) {
        p       <- fam_plausible_list[[f]]
        cands_f <- p[!p %in% skip_list]
        data.frame(
          family          = f,
          plausible_count = length(p),
          ncbi_count      = sum(cands_f %in% all_fam_has_seqs_vec),
          unreferenced_count     = sum(cands_f %in% all_fam_unref_vec),
          stringsAsFactors = FALSE
        )
      }))

      n_fam_unref <- length(all_fam_unref_vec)
      cli::cli_inform(
        "Family-level unreferenced species detected: {n_fam_unref} across \\
        {length(families_to_expand)} family/families."
      )
    }
  }

  # ---- Step 8: Report and return ---------------------------------------------
  n_genus_unref <- sum(census_df$unreferenced_count, na.rm = TRUE)
  n_seqgap       <- length(has_seqs_vec)
  n_fam_unref   <- if (!is.null(family_census_df))
    sum(family_census_df$unreferenced_count, na.rm = TRUE)
  else 0L

  cli::cli_inform(
    "Total unreferenced species: {length(unref_vec)} \\
    ({n_genus_unref} congener, {n_fam_unref} family-level; \\
    {n_seqgap} with barcode sequences but absent from reference)."
  )

  .new_unreferenced_species_result(unref_vec, all_plausible_flat, census_df,
                  unreferenced_family  = unreferenced_family_map,
                  family_census = family_census_df)
}

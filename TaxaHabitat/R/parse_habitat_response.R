# ==============================================================================
# parse_habitat_response.R
# TaxaHabitat — Parse LLM habitat response
#
# Exported functions:
#   parse_hierarchical_habitat_response()   Provider-neutral habitat response parser
#
# Internal helpers (all @noRd):
#   .is_two_level()                  Check if scheme has L1 + L2 columns
#   .validate_habitat_scheme_local() Validate bare dataframe as habitat scheme
#   .is_two_level_local()            .is_two_level for bare-dataframe path
#   .strip_and_extract_csv()         Remove fences, find header, trim preamble/postamble
#   .standardise_taxon_col()         Normalise taxon column -> taxon_name
#   .warn_missing_taxa()             Warn on taxa absent from response
# ==============================================================================


# ==============================================================================
# STEP 3: Parse LLM response (provider-neutral)
# ==============================================================================

#' Parse a Weighted Habitat Response from an LLM
#'
#' Parses the raw text returned by any LLM in response to a
#' \code{\link{build_habitat_prompt}} prompt into a species-by-habitat weight
#' table. Provider-neutral: works with the multi-chunk dispatcher
#' (\code{\link[TaxaTools]{prompt_api}} with any \code{llm_fn}),
#' any direct \code{call_*_api()} function, user-written provider functions,
#' and manually saved response files (\code{\link[TaxaTools]{read_llm_response}}).
#'
#' @param raw_text Character. Length-1 string containing the LLM response.
#'   Markdown code fences, leading/trailing preamble, and postamble text
#'   are handled automatically.
#' @param taxon_list Character vector. Species submitted in the prompt.
#'   Used to detect taxa missing from the response.
#' @param habitat_scheme A \code{habitat_prompt} object from
#'   \code{\link{build_habitat_prompt}}. \strong{Always supply this} --
#'   its \code{$habitat_cols} element is used to identify and validate
#'   the weight columns, and its \code{$scheme} drives IUCN vs. custom
#'   mode. \code{NULL} triggers legacy IUCN mode (deprecated; IUCN
#'   output is also now wide-weighted).
#' @param extra_covariates Character vector. Names of any additional binary
#'   covariate columns to retain from the parsed output. Default \code{NULL}
#'   (no extra columns retained). Ignored when no matching columns are found.
#'
#' @return A data.frame with one row per species and the following columns:
#' \describe{
#'   \item{taxon_name}{Character. Species name as returned by the LLM.}
#'   \item{<habitat columns>}{Numeric. One column per habitat in the scheme,
#'     named exactly as in \code{prompt$habitat_cols}. Values are 0.0-1.0.}
#'   \item{Other_weight}{Numeric. Weight assigned to habitats outside the
#'     scheme. 0 for specialists that fit the scheme.}
#'   \item{habitat_best_guess}{Character. Free-text description of the actual
#'     habitat for species with non-zero \code{Other_weight}. Empty string
#'     otherwise.}
#'   \item{Habitat}{Character. Convenience column: name of the habitat column
#'     with the highest weight (argmax). \code{"Other"} when
#'     \code{Other_weight} is the largest. Used by downstream functions
#'     (\code{\link{assign_habitat_biological}}) that expect a single primary
#'     habitat label per species.}
#' }
#'
#' @details
#' \strong{Multi-chunk responses:} If \code{raw_text} contains multiple CSV
#' blocks (one per chunk from \code{\link[TaxaTools]{prompt_api}}), duplicate
#' header rows are stripped automatically before combining.
#'
#' \strong{Weight normalisation:} Weights are NOT renormalised. A warning is
#' emitted for any row where weights deviate more than 0.05 from 1.0.
#'
#' \strong{Unrecognised columns:} If the LLM returns habitat column names not
#' in \code{prompt$habitat_cols}, those columns are folded into
#' \code{Other_weight} with a warning.
#'
#' \strong{Missing species:} Taxa in \code{taxon_list} absent from the parsed
#' output trigger a warning listing the first five missing names.
#'
#' @seealso \code{\link{build_habitat_prompt}},
#'   \code{\link[TaxaTools]{prompt_api}},
#'   \code{\link[TaxaTools]{call_anthropic_api}},
#'   \code{\link[TaxaTools]{call_gemini_api}},
#'   \code{\link[TaxaTools]{call_openai_api}},
#'   \code{\link[TaxaTools]{call_ollama_api}},
#'   \code{\link[TaxaTools]{prompt_manual}},
#'   \code{\link[TaxaTools]{read_llm_response}},
#'   \code{\link{assign_habitat_biological}}
#'
#' @importFrom utils read.csv
#' @export
#'
#' @examples
#' \dontrun{
#' prompt   <- build_habitat_prompt(c("Gadus morhua", "Oncorhynchus mykiss"),
#'                                  habitat_scheme = my_scheme)
#' raw_text <- TaxaTools::prompt_api(prompt)
#' hab_tbl  <- parse_hierarchical_habitat_response(raw_text, prompt$taxa,
#'                                                 habitat_scheme = prompt)
#' }

parse_hierarchical_habitat_response <- function(raw_text,
                                                taxon_list,
                                                habitat_scheme   = NULL,
                                                extra_covariates = NULL) {

  # ---------------------------------------------------------------------------
  # Argument checks
  # ---------------------------------------------------------------------------
  if (!is.character(raw_text) || length(raw_text) != 1L || !nzchar(trimws(raw_text))) {
    stop("parse_hierarchical_habitat_response: 'raw_text' must be a length-1 non-empty character string.")
  }
  if (!is.character(taxon_list) || length(taxon_list) == 0L) {
    stop("parse_hierarchical_habitat_response: 'taxon_list' must be a non-empty character vector.")
  }
  # Remove NAs and warn about duplicates
  n_na <- sum(is.na(taxon_list))
  if (n_na > 0L) {
    warning(sprintf("parse_hierarchical_habitat_response: removing %d NA value(s) from taxon_list.", n_na))
    taxon_list <- taxon_list[!is.na(taxon_list)]
  }
  n_dup <- sum(duplicated(taxon_list))
  if (n_dup > 0L) {
    warning(sprintf("parse_hierarchical_habitat_response: removing %d duplicate(s) from taxon_list.", n_dup))
    taxon_list <- unique(taxon_list)
  }

  # ---------------------------------------------------------------------------
  # Resolve scheme and expected habitat columns from the prompt object
  # ---------------------------------------------------------------------------
  expected_hab_cols <- NULL
  scheme            <- NULL

  if (inherits(habitat_scheme, "habitat_prompt")) {
    expected_hab_cols <- habitat_scheme$habitat_cols   # ordered vector from build_habitat_prompt()
    scheme            <- habitat_scheme$scheme         # validated dataframe (or NULL for IUCN)
  } else if (is.data.frame(habitat_scheme)) {
    # Legacy: bare dataframe -- derive cols the same way build_habitat_prompt() would
    scheme <- tryCatch(.validate_habitat_scheme_local(habitat_scheme), error = function(e) NULL)
    if (!is.null(scheme)) {
      if (.is_two_level_local(scheme)) {
        expected_hab_cols <- unique(scheme$l2_name[!is.na(scheme$l2_name) &
                                                     nzchar(trimws(scheme$l2_name))])
      } else {
        expected_hab_cols <- unique(scheme$l1_name)
      }
    }
  }
  # NULL habitat_scheme or unrecognised type: expected_hab_cols stays NULL;
  # all numeric columns are treated as habitat weights (IUCN wide mode).

  # ---------------------------------------------------------------------------
  # Strip fences and extract the CSV block
  # ---------------------------------------------------------------------------
  cleaned <- .strip_and_extract_csv(raw_text)

  # Strip duplicate header rows that appear when multi-chunk responses are
  # concatenated directly (e.g. via paste() in Path 2, or in tests).
  # .combine_chunk_responses handles this for the API path, but parse() should
  # be robust regardless of how raw_text was assembled.
  cleaned_lines <- strsplit(cleaned, "\n", fixed = TRUE)[[1]]
  if (length(cleaned_lines) > 1L) {
    header_line <- cleaned_lines[1L]
    dup_header  <- cleaned_lines[-1L] == header_line
    if (any(dup_header)) {
      cleaned_lines <- c(header_line, cleaned_lines[-1L][!dup_header])
      cleaned <- paste(cleaned_lines, collapse = "\n")
    }
  }

  # ---------------------------------------------------------------------------
  # Parse CSV
  # ---------------------------------------------------------------------------
  parsed <- tryCatch(
    utils::read.csv(text = cleaned, stringsAsFactors = FALSE,
                    strip.white = TRUE, check.names = FALSE,
                    na.strings = c("", "NA", "N/A")),
    error = function(e) {
      stop(
        "parse_hierarchical_habitat_response: CSV parsing failed: ", e$message,
        "\nFirst line of extracted block: ",
        strsplit(cleaned, "\n")[[1]][1],
        call. = FALSE
      )
    }
  )

  if (nrow(parsed) == 0L) {
    stop(
      "parse_hierarchical_habitat_response: CSV parsed successfully but contains ",
      "no data rows. Check the LLM response."
    )
  }

  # ---------------------------------------------------------------------------
  # Standardise taxon column name
  # ---------------------------------------------------------------------------
  parsed <- .standardise_taxon_col(parsed)

  if (!"taxon_name" %in% names(parsed)) {
    stop(
      "parse_hierarchical_habitat_response: could not identify a taxon name column. ",
      "Column names found: ", paste(names(parsed), collapse = ", ")
    )
  }

  parsed$taxon_name <- trimws(as.character(parsed$taxon_name))
  # nzchar(NA) returns NA (not FALSE) -- must guard explicitly
  parsed <- parsed[!is.na(parsed$taxon_name) & nzchar(parsed$taxon_name), ,
                   drop = FALSE]

  # ---------------------------------------------------------------------------
  # Separate text columns before numeric detection
  # ---------------------------------------------------------------------------
  has_best_guess     <- "habitat_best_guess" %in% names(parsed)
  has_ecoregion_guess <- "ecoregion_best_guess" %in% names(parsed)

  # ---------------------------------------------------------------------------
  # Identify numeric weight columns
  # ---------------------------------------------------------------------------
  protected_cols     <- c("taxon_name",
                          if (has_best_guess) "habitat_best_guess",
                          if (has_ecoregion_guess) "ecoregion_best_guess")
  numeric_candidates <- setdiff(names(parsed), protected_cols)

  # A column is a weight col if:
  #   (a) it is named in expected_hab_cols (explicit scheme) — always include, OR
  #   (b) at least half its non-NA values parse as numeric (heuristic for NULL scheme), OR
  #   (c) all its values are NA — plausibly numeric; will be coerced to 0.
  # Case (c) matters for single-row inputs where the LLM wrote "NA" for a weight.
  is_weight_col <- vapply(numeric_candidates, function(col) {
    if (!is.null(expected_hab_cols) &&
        (col %in% expected_hab_cols || col %in% c("Other_weight", "Other"))) {
      return(TRUE)
    }
    vals      <- suppressWarnings(as.numeric(parsed[[col]]))
    n_numeric <- sum(!is.na(vals))
    n_total   <- length(vals)
    n_numeric >= max(1L, as.integer(n_total / 2)) || all(is.na(vals))
  }, logical(1))

  weight_cols <- numeric_candidates[is_weight_col]

  for (wc in weight_cols) {
    parsed[[wc]] <- suppressWarnings(as.numeric(parsed[[wc]]))
    parsed[[wc]][is.na(parsed[[wc]])] <- 0
  }

  # Drop clearly non-numeric columns that slipped through (e.g. Suitability)
  non_weight_extra <- numeric_candidates[!is_weight_col]

  # ---------------------------------------------------------------------------
  # Validate / align against expected habitat columns
  # ---------------------------------------------------------------------------
  if (!is.null(expected_hab_cols)) {
    missing_expected <- setdiff(expected_hab_cols, weight_cols)
    if (length(missing_expected) > 0L) {
      warning(sprintf(
        paste0("parse_hierarchical_habitat_response: %d expected habitat column(s) ",
               "absent from LLM response: %s. Added with weight 0."),
        length(missing_expected),
        paste(head(missing_expected, 5), collapse = ", ")
      ), call. = FALSE)
      for (mc in missing_expected) {
        parsed[[mc]] <- 0
      }
      weight_cols <- c(weight_cols, missing_expected)
    }

    # Columns not in expected set and not Other/Other_weight -> fold into Other_weight
    extra_cols <- setdiff(weight_cols,
                          c(expected_hab_cols, "Other_weight", "Other"))
    if (length(extra_cols) > 0L) {
      warning(sprintf(
        paste0("parse_hierarchical_habitat_response: LLM returned %d unrecognised ",
               "habitat column(s): %s. Folded into Other_weight."),
        length(extra_cols),
        paste(head(extra_cols, 5), collapse = ", ")
      ), call. = FALSE)
      other_col <- if ("Other_weight" %in% weight_cols) "Other_weight" else "Other"
      if (!other_col %in% names(parsed)) { parsed[[other_col]] <- 0 }
      for (ec in extra_cols) {
        parsed[[other_col]] <- parsed[[other_col]] + parsed[[ec]]
        parsed[[ec]] <- NULL
        weight_cols  <- setdiff(weight_cols, ec)
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Standardise Other_weight column name
  # ---------------------------------------------------------------------------
  if ("Other" %in% weight_cols && !"Other_weight" %in% weight_cols) {
    names(parsed)[names(parsed) == "Other"] <- "Other_weight"
    weight_cols[weight_cols == "Other"] <- "Other_weight"
  }
  if (!"Other_weight" %in% weight_cols) {
    parsed[["Other_weight"]] <- 0
    weight_cols <- c(weight_cols, "Other_weight")
  }

  pure_hab_cols <- setdiff(weight_cols, "Other_weight")

  # ---------------------------------------------------------------------------
  # Warn on rows that don't sum to ~1.0
  # ---------------------------------------------------------------------------
  row_sums <- rowSums(parsed[, weight_cols, drop = FALSE], na.rm = TRUE)
  bad_rows <- abs(row_sums - 1) > 0.05 & row_sums > 0
  if (any(bad_rows)) {
    warning(sprintf(
      paste0("parse_hierarchical_habitat_response: %d row(s) have habitat weights ",
             "not summing to 1.0 (tolerance 0.05). First offenders: %s. ",
             "Weights have NOT been renormalised."),
      sum(bad_rows),
      paste(head(parsed$taxon_name[bad_rows], 3), collapse = ", ")
    ), call. = FALSE)
  }

  # ---------------------------------------------------------------------------
  # habitat_best_guess column
  # ---------------------------------------------------------------------------
  if (!has_best_guess) {
    parsed[["habitat_best_guess"]] <- ""
  } else {
    parsed[["habitat_best_guess"]][is.na(parsed[["habitat_best_guess"]])] <- ""
    parsed[["habitat_best_guess"]] <- trimws(as.character(parsed[["habitat_best_guess"]]))
  }

  # ---------------------------------------------------------------------------
  # ecoregion_best_guess column (present when geographic_context was used)
  # ---------------------------------------------------------------------------
  if (has_ecoregion_guess) {
    parsed[["ecoregion_best_guess"]][is.na(parsed[["ecoregion_best_guess"]])] <- ""
    parsed[["ecoregion_best_guess"]] <- trimws(as.character(parsed[["ecoregion_best_guess"]]))
  }

  # ---------------------------------------------------------------------------
  # Habitat convenience column: argmax of all weight columns
  # ---------------------------------------------------------------------------
  all_weight_cols <- c(pure_hab_cols, "Other_weight")
  weight_mat      <- as.matrix(parsed[, all_weight_cols, drop = FALSE])
  weight_mat[is.na(weight_mat)] <- 0
  best_idx   <- max.col(weight_mat, ties.method = "first")
  col_labels <- sub("^Other_weight$", "Other", all_weight_cols)
  parsed[["Habitat"]] <- col_labels[best_idx]
  parsed[["Habitat"]][rowSums(weight_mat) == 0] <- NA_character_

  # ---------------------------------------------------------------------------
  # Warn on missing taxa
  # ---------------------------------------------------------------------------
  parsed <- .warn_missing_taxa(parsed, taxon_list,
                               "parse_hierarchical_habitat_response")

  # ---------------------------------------------------------------------------
  # Retain any requested extra_covariates columns
  # ---------------------------------------------------------------------------
  covariate_keep <- if (!is.null(extra_covariates)) {
    intersect(extra_covariates, names(parsed))
  } else {
    character(0)
  }

  # ---------------------------------------------------------------------------
  # Canonical column order; drop non-scheme leftovers
  # ---------------------------------------------------------------------------
  col_order <- c("taxon_name", pure_hab_cols, "Other_weight",
                 "habitat_best_guess",
                 if (has_ecoregion_guess) "ecoregion_best_guess",
                 "Habitat", covariate_keep)
  parsed[, intersect(col_order, names(parsed)), drop = FALSE]
}


# ==============================================================================
# Internal helpers
# ==============================================================================


#' Local .is_two_level: scheme has l1_name + l2_name columns with values
#' @noRd
.is_two_level <- function(scheme) {
  if (is.null(scheme)) return(FALSE)
  all(c("l1_name", "l2_name") %in% names(scheme)) &&
    any(!is.na(scheme$l2_name))
}


#' Local scheme validator used when a bare dataframe is passed as habitat_scheme.
#' Mirrors .validate_habitat_scheme() from build_habitat_prompt.R but kept local
#' to avoid cross-file dependency in this helper path.
#' @noRd
.validate_habitat_scheme_local <- function(scheme) {
  if (!is.data.frame(scheme) || !"l1_name" %in% names(scheme)) return(NULL)
  if (!"l2_code" %in% names(scheme)) scheme$l2_code <- NA_character_
  if (!"l2_name" %in% names(scheme)) scheme$l2_name <- NA_character_
  if (!"realm"   %in% names(scheme)) scheme$realm   <- NA_character_
  scheme[, c("l1_name", "l2_code", "l2_name", "realm")]
}


#' Local .is_two_level for bare-dataframe scheme validation path
#' @noRd
.is_two_level_local <- function(scheme) {
  if (is.null(scheme)) return(FALSE)
  all(c("l1_name", "l2_name") %in% names(scheme)) &&
    any(!is.na(scheme$l2_name) & nzchar(trimws(scheme$l2_name)))
}


#' Remove markdown fences; find header row; trim preamble and postamble.
#' Returns a single character string suitable for utils::read.csv(text = ...).
#' @noRd
.strip_and_extract_csv <- function(raw_text) {

  txt   <- gsub("```[a-zA-Z]*\n?", "", raw_text)
  txt   <- gsub("```",              "", txt)
  lines <- trimws(strsplit(txt, "\n")[[1]])

  # Header row must contain "taxon_name" and a comma
  header_idx <- which(grepl("taxon_name", lines, ignore.case = TRUE) &
                        grepl(",", lines, fixed = TRUE))[1]
  if (is.na(header_idx)) return(trimws(txt))

  # Trim preamble
  lines <- lines[header_idx:length(lines)]

  # Trim postamble: keep header + any line with a comma
  is_csv_line <- grepl(",", lines, fixed = TRUE) | seq_along(lines) == 1L
  last_csv    <- max(which(is_csv_line))
  lines       <- lines[1:last_csv]

  # Drop blank lines
  lines <- lines[nzchar(lines)]

  paste(lines, collapse = "\n")
}


#' Standardise the taxon name column to "taxon_name".
#' @noRd
.standardise_taxon_col <- function(parsed) {
  if ("taxon_name" %in% names(parsed)) return(parsed)
  tax_col <- grep("taxon|species|name", names(parsed),
                  ignore.case = TRUE, value = TRUE)[1]
  if (!is.na(tax_col)) parsed[["taxon_name"]] <- parsed[[tax_col]]
  parsed
}


#' Warn about taxa in taxon_list absent from the parsed response.
#' Returns parsed unchanged (for call-chain compatibility).
#' @noRd
.warn_missing_taxa <- function(parsed, taxon_list, fn_name) {
  returned <- trimws(parsed[["taxon_name"]])
  missing  <- setdiff(taxon_list, returned)
  if (length(missing) > 0L) {
    warning(sprintf(
      "%s: %d taxon/taxa missing from response: %s",
      fn_name, length(missing), paste(head(missing, 5), collapse = ", ")
    ), call. = FALSE)
  }
  parsed
}


#' Null-coalescing operator (local copy for this file)

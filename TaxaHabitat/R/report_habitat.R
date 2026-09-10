# ==============================================================================
# report_habitat.R
# TaxaHabitat -- Summarize habitat assignment for Methods/Results reporting
#
# Exported functions:
#   report_habitat()   -- generate report_section from habitat data
#
# Session 65: initial implementation
# ==============================================================================


#' Generate a Report Section for Habitat Assignment
#'
#' Summarizes the habitat assignment produced by TaxaHabitat into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param habitat_data Data frame. Output of
#'   \code{\link{assign_habitat_biological}} or the raw habitat weights from
#'   \code{\link{parse_hierarchical_habitat_response}}. Must contain at least
#'   one numeric habitat weight column.
#' @param taxon_col Character. Column name containing taxon names.
#'   Default \code{"scientificName"}.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing habitat assignment approach.}
#'   \item{results}{Template text summarizing habitat assignments.}
#'   \item{params}{Named list of habitat parameters.}
#'   \item{statistics}{Named list of summary counts.}
#' }
#'
#' @seealso \code{\link{assign_habitat_biological}},
#'   \code{\link{parse_hierarchical_habitat_response}}
#'
#' @examples
#' \dontrun{
#' hab <- parse_hierarchical_habitat_response(llm_output)
#' sec <- report_habitat(hab)
#' print(sec)
#' }
#'
#' @export
report_habitat <- function(habitat_data,
                           taxon_col = "scientificName",
                           verbose = FALSE) {
  if (!is.data.frame(habitat_data) || nrow(habitat_data) == 0L) {
    stop("report_habitat: 'habitat_data' must be a non-empty data frame.",
      call. = FALSE
    )
  }

  # This function is documented to accept either assign_habitat_biological()'s
  # output (occurrence-level data with a categorical main_habitat winner per
  # row) or the raw per-species weight table from
  # parse_hierarchical_habitat_response(). The two shapes need genuinely
  # different summarisation -- assign_habitat_biological()'s real @return
  # adds only main_habitat/habitat_best_guess (both character) to whatever
  # occurrence_data it was given, so it carries NO numeric habitat-weight
  # columns at all. Treating "any numeric column not on a small exclude
  # list" as a habitat weight column (the pre-2026-09-08 logic) therefore
  # picked up the occurrence data's own incidental numeric columns instead
  # (decimalLatitude/decimalLongitude in every real production caller) --
  # confirmed live on both a real 18S and a real GreatLakes report, which
  # rendered "under the decimalLatitude/decimalLongitude scheme" and
  # "Dominant habitat: decimalLatitude (mean weight 3519%)" (mean latitude
  # times 100).
  #
  # main_habitat's mere presence isn't a safe dispatch signal on its own --
  # a data frame can legitimately carry both a real main_habitat column AND
  # real per-category weight columns together (this file's own "excludes
  # known non-habitat columns" test does exactly that). Positively identify
  # real weight columns instead: every habitat weight column is documented
  # (parse_hierarchical_habitat_response()'s own @return) to hold values in
  # [0, 1] -- a coordinate or other incidental numeric column essentially
  # never does. Only fall back to tallying the categorical main_habitat
  # column when NOTHING numeric passes that range check.
  candidate_cols <- .candidate_habitat_cols(habitat_data, taxon_col)
  has_weight_cols <- length(candidate_cols) > 0L && any(vapply(candidate_cols, function(hc) {
    x <- habitat_data[[hc]]
    all(is.na(x) | (x >= 0 & x <= 1))
  }, logical(1L)))

  if (!has_weight_cols && "main_habitat" %in% names(habitat_data)) {
    hab <- .summarise_main_habitat(habitat_data, taxon_col)
  } else {
    hab <- .summarise_habitat_weights(habitat_data, taxon_col, candidate_cols)
  }

  statistics <- list(
    n_taxa         = hab$n_taxa,
    n_habitat_cols = length(hab$habitat_cols)
  )
  if (!is.null(hab$dominant_habitat)) {
    statistics$dominant_habitat <- hab$dominant_habitat
    statistics$dominant_pct <- hab$dominant_pct
  }

  # --- Params -----------------------------------------------------------------
  params <- list(method = "LLM-based biological consensus")
  if (!is.null(hab$scheme)) params$habitat_scheme <- hab$scheme

  # Read report_params if available
  rp <- attr(habitat_data, "report_params")
  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Methods text -----------------------------------------------------------
  methods_text <- sprintf(
    "Habitat classifications were assigned to %d taxa using LLM-based biological consensus",
    hab$n_taxa
  )
  if (!is.null(hab$scheme)) {
    methods_text <- paste0(methods_text, sprintf(" under the %s scheme", hab$scheme))
  }
  methods_text <- paste0(methods_text, ".")

  # --- Results text -----------------------------------------------------------
  results_text <- paste(hab$results_parts, collapse = " ")

  # --- Construct report_section -----------------------------------------------
  TaxaTools::new_report_section(
    package    = "TaxaHabitat",
    section    = "habitat",
    methods    = methods_text,
    results    = results_text,
    citations  = NULL,
    params     = params,
    statistics = statistics
  )
}


#' Resolve the taxon-name column, falling back to this ecosystem's convention
#'
#' Every real production caller passes \code{assign_habitat_biological()}'s
#' output, which names its taxon column \code{taxon_name} (not this function's
#' historical \code{"scientificName"} default) -- without this fallback,
#' \code{n_taxa} silently counted raw ROWS instead of unique taxa whenever the
#' requested column wasn't present (the real cause of a generated report
#' claiming "1419840 taxa" for an 18S survey with 2,027 real taxa).
#'
#' @noRd
.resolve_taxon_col <- function(habitat_data, taxon_col) {
  if (taxon_col %in% names(habitat_data)) {
    return(taxon_col)
  }
  if ("taxon_name" %in% names(habitat_data)) {
    return("taxon_name")
  }
  taxon_col
}


#' Summarise assign_habitat_biological() output (categorical main_habitat)
#' @noRd
.summarise_main_habitat <- function(habitat_data, taxon_col) {
  resolved_taxon_col <- .resolve_taxon_col(habitat_data, taxon_col)
  n_taxa <- if (resolved_taxon_col %in% names(habitat_data)) {
    length(unique(habitat_data[[resolved_taxon_col]][!is.na(habitat_data[[resolved_taxon_col]])]))
  } else {
    nrow(habitat_data)
  }

  mh <- habitat_data$main_habitat[!is.na(habitat_data$main_habitat)]
  # First-appearance order, not table()'s alphabetical default -- a scheme
  # string should read in the order categories actually occur, not shuffle
  # depending on which letters the LLM's own labels happen to start with.
  habitat_cols <- unique(mh)
  counts <- vapply(habitat_cols, function(h) sum(mh == h), integer(1L))
  scheme <- if (length(habitat_cols) > 0L) paste(habitat_cols, collapse = "/") else NULL

  dominant_habitat <- NULL
  dominant_pct <- NULL
  if (length(counts) > 0L) {
    dominant_habitat <- habitat_cols[which.max(counts)]
    dominant_pct <- round(100 * max(counts) / length(mh), 0)
  }

  results_parts <- sprintf(
    "%d taxa received habitat assignments across %d categories.",
    n_taxa, length(habitat_cols)
  )
  if (!is.null(dominant_habitat)) {
    results_parts <- c(results_parts, sprintf(
      "Dominant habitat: %s (%.0f%% of assigned records).",
      dominant_habitat, dominant_pct
    ))
  }

  list(
    n_taxa = n_taxa, habitat_cols = habitat_cols, scheme = scheme,
    dominant_habitat = dominant_habitat, dominant_pct = dominant_pct,
    results_parts = results_parts
  )
}


#' Numeric columns that could plausibly be habitat weight columns: not the
#' taxon column or a known non-habitat column. This is deliberately just the
#' candidate set (no value-range filtering) -- report_habitat()'s own dispatch
#' logic uses the range check to decide which shape was passed, but once
#' Shape A is confirmed every candidate is still treated as a real habitat
#' column here, same as before, so a column with a defensible out-of-range
#' value (e.g. floating-point overshoot) is never silently dropped.
#' @noRd
.candidate_habitat_cols <- function(habitat_data, taxon_col) {
  exclude_cols <- c(
    taxon_col, "habitat_best_guess", "ecoregion_best_guess",
    "Habitat", "main_habitat"
  )
  numeric_cols <- names(habitat_data)[
    vapply(habitat_data, is.numeric, logical(1L))
  ]
  setdiff(numeric_cols, exclude_cols)
}


#' Summarise raw per-species habitat weights (parse_hierarchical_habitat_response())
#' @noRd
.summarise_habitat_weights <- function(habitat_data, taxon_col, habitat_cols) {
  # Infer scheme from column names
  scheme <- NULL
  if (length(habitat_cols) > 0L) {
    if (all(habitat_cols %in% c("Marine", "Freshwater", "Terrestrial", "Other"))) {
      scheme <- "3-category"
    } else if (any(grepl("^\\d+\\.?\\d*", habitat_cols))) {
      scheme <- "IUCN_L1"
    } else {
      scheme <- paste(habitat_cols, collapse = "/")
    }
  }

  n_taxa <- if (taxon_col %in% names(habitat_data)) {
    length(unique(habitat_data[[taxon_col]][!is.na(habitat_data[[taxon_col]])]))
  } else {
    nrow(habitat_data)
  }

  # Dominant habitat (column with highest mean weight)
  dominant_habitat <- NULL
  dominant_pct <- NULL
  if (length(habitat_cols) > 0L) {
    col_means <- vapply(habitat_cols, function(hc) {
      mean(habitat_data[[hc]], na.rm = TRUE)
    }, numeric(1L))
    dominant_habitat <- names(which.max(col_means))
    # Read the pct off the SELECTED column, not max(col_means): which.max()
    # skips NA means (an all-NA habitat column) but a bare max() returns NA
    # whenever any column's mean is NA -- yielding a valid dominant_habitat
    # paired with an NA pct, which is what actually crashed the %d sprintf
    # below on the first real kernel-path GL report run (2026-09-01).
    #
    # Guarded on dominant_habitat itself, not just habitat_cols: when EVERY
    # habitat column is entirely NA (a degraded-LLM-output case, not yet hit
    # in production but structurally possible), which.max() on an all-NA
    # col_means returns integer(0), so dominant_habitat is NULL here --
    # col_means[[NULL]] then errors ("attempt to select less than one
    # element") instead of falling through to the no-dominant-habitat path
    # the `if (!is.null(dominant_habitat))` check below already exists to
    # handle. Found in this session's code-review pass, 2026-09-07.
    if (!is.null(dominant_habitat)) {
      dominant_pct <- round(col_means[[dominant_habitat]] * 100, 0)
    }
  }

  results_parts <- sprintf(
    "%d taxa received habitat weight assignments across %d categories.",
    n_taxa, length(habitat_cols)
  )
  if (!is.null(dominant_habitat)) {
    results_parts <- c(results_parts, sprintf(
      # %.0f, not %d: round() returns a double, and sprintf's %d errors on
      # non-integer doubles (found by the first real kernel-path GL report
      # run, 2026-09-01 -- this ecosystem's documented sprintf footgun class).
      "Dominant habitat: %s (mean weight %.0f%%).",
      dominant_habitat, dominant_pct
    ))
  }

  list(
    n_taxa = n_taxa, habitat_cols = habitat_cols, scheme = scheme,
    dominant_habitat = dominant_habitat, dominant_pct = dominant_pct,
    results_parts = results_parts
  )
}

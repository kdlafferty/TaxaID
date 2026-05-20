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
                           verbose   = FALSE) {

  if (!is.data.frame(habitat_data) || nrow(habitat_data) == 0L)
    stop("report_habitat: 'habitat_data' must be a non-empty data frame.",
         call. = FALSE)

  # --- Detect habitat columns -------------------------------------------------
  # Habitat weight columns are numeric and not the taxon column or known

  # non-habitat columns
  exclude_cols <- c(taxon_col, "habitat_best_guess", "ecoregion_best_guess",
                    "Habitat", "main_habitat")
  numeric_cols <- names(habitat_data)[
    vapply(habitat_data, is.numeric, logical(1L))
  ]
  habitat_cols <- setdiff(numeric_cols, exclude_cols)

  # --- Detect habitat scheme --------------------------------------------------
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

  # --- Extract statistics -----------------------------------------------------
  n_taxa <- if (taxon_col %in% names(habitat_data)) {
    length(unique(habitat_data[[taxon_col]][!is.na(habitat_data[[taxon_col]])]))
  } else {
    nrow(habitat_data)
  }

  # Dominant habitat (column with highest mean weight)
  dominant_habitat <- NULL
  if (length(habitat_cols) > 0L) {
    col_means <- vapply(habitat_cols, function(hc) {
      mean(habitat_data[[hc]], na.rm = TRUE)
    }, numeric(1L))
    dominant_habitat <- names(which.max(col_means))
    dominant_pct <- round(max(col_means) * 100, 0)
  }

  statistics <- list(
    n_taxa         = n_taxa,
    n_habitat_cols = length(habitat_cols)
  )
  if (!is.null(dominant_habitat)) {
    statistics$dominant_habitat <- dominant_habitat
    statistics$dominant_pct     <- dominant_pct
  }

  # --- Params -----------------------------------------------------------------
  params <- list(method = "LLM-based biological consensus")
  if (!is.null(scheme)) params$habitat_scheme <- scheme

  # Read report_params if available
  rp <- attr(habitat_data, "report_params")
  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Methods text -----------------------------------------------------------
  methods_text <- sprintf(
    "Habitat classifications were assigned to %d taxa using LLM-based biological consensus",
    n_taxa
  )
  if (!is.null(scheme)) {
    methods_text <- paste0(methods_text, sprintf(" under the %s scheme", scheme))
  }
  methods_text <- paste0(methods_text, ".")

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  results_parts <- c(results_parts, sprintf(
    "%d taxa received habitat weight assignments across %d categories.",
    n_taxa, length(habitat_cols)
  ))

  if (!is.null(dominant_habitat)) {
    results_parts <- c(results_parts, sprintf(
      "Dominant habitat: %s (mean weight %d%%).",
      dominant_habitat, dominant_pct
    ))
  }

  results_text <- paste(results_parts, collapse = " ")

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

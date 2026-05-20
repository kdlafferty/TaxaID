# ==============================================================================
# report_priors.R
# TaxaExpect -- Summarize prior estimation for Methods/Results reporting
#
# Exported functions:
#   report_priors()   -- generate report_section from priors output
#
# Session 65: initial implementation
# ==============================================================================


#' Generate a Report Section for Prior Estimation
#'
#' Summarizes the prior estimation produced by TaxaExpect into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param priors_output Either:
#'   \itemize{
#'     \item A list returned by \code{\link{build_priors}} (contains
#'       \code{$priors}, \code{$model}, \code{$occurrences}, \code{$grid_result}).
#'     \item A data frame of priors directly (output of
#'       \code{\link{generate_full_priors}}).
#'   }
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing prior estimation approach.}
#'   \item{results}{Template text summarizing prior coverage.}
#'   \item{citations}{Propagated from occurrence data if available.}
#'   \item{params}{Named list of prior parameters.}
#'   \item{statistics}{Named list of summary counts.}
#' }
#'
#' @seealso \code{\link{build_priors}}, \code{\link{generate_full_priors}}
#'
#' @examples
#' \dontrun{
#' bp <- build_priors(taxon_list = taxa, geometry = bbox)
#' sec <- report_priors(bp)
#' print(sec)
#' }
#'
#' @export
report_priors <- function(priors_output,
                          verbose = FALSE) {

  # --- Accept list (build_priors output) or data frame ------------------------
  if (is.list(priors_output) && !is.data.frame(priors_output) &&
      "priors" %in% names(priors_output)) {
    priors_df <- priors_output$priors
    rp <- attr(priors_output, "report_params")
    habitat_scheme <- attr(priors_output, "habitat_scheme")
    # Try to get occurrence count from the occurrences slot
    n_occurrence_records <- if (!is.null(priors_output$occurrences) &&
                                is.data.frame(priors_output$occurrences)) {
      nrow(priors_output$occurrences)
    } else {
      NULL
    }
  } else if (is.data.frame(priors_output) && nrow(priors_output) > 0L) {
    priors_df <- priors_output
    rp <- attr(priors_output, "report_params")
    habitat_scheme <- attr(priors_output, "habitat_scheme")
    n_occurrence_records <- NULL
  } else {
    stop("report_priors: 'priors_output' must be a non-empty data frame or build_priors() list.",
         call. = FALSE)
  }

  # --- Extract statistics from priors -----------------------------------------
  n_taxa <- if ("taxon_name" %in% names(priors_df)) {
    length(unique(priors_df$taxon_name[!is.na(priors_df$taxon_name)]))
  } else {
    NA_integer_
  }

  n_grid_cells <- if ("grid_id" %in% names(priors_df)) {
    length(unique(priors_df$grid_id))
  } else {
    NA_integer_
  }

  # Tier breakdown
  tier_breakdown <- NULL
  if ("model_tier" %in% names(priors_df)) {
    tier_counts <- table(priors_df$model_tier)
    tier_breakdown <- as.list(tier_counts)
  }

  # --- Citations (propagated from occurrence data) ----------------------------
  citations <- NULL
  if (!is.null(rp$citations)) {
    citations <- rp$citations
    citations <- citations[!is.na(citations) & nzchar(citations)]
    if (length(citations) == 0L) citations <- NULL
  }

  # --- Statistics -------------------------------------------------------------
  statistics <- list(n_taxa = n_taxa)
  if (!is.na(n_grid_cells)) statistics$n_grid_cells <- n_grid_cells
  if (!is.null(n_occurrence_records)) statistics$n_occurrence_records <- n_occurrence_records
  if (!is.null(tier_breakdown)) statistics$tier_breakdown <- tier_breakdown

  # --- Params -----------------------------------------------------------------
  params <- list(method = "hierarchical biodiversity model")
  if (!is.null(habitat_scheme)) params$habitat_scheme <- habitat_scheme
  if (!is.na(n_grid_cells)) params$n_grid_cells <- n_grid_cells
  if (!is.null(rp)) {
    extra <- rp[!names(rp) %in% c(names(params), "citations")]
    if (length(extra) > 0L) params <- c(params, extra)
  }

  # --- Methods text -----------------------------------------------------------
  methods_text <- "Prior probabilities were estimated"

  if (!is.null(n_occurrence_records)) {
    methods_text <- paste0(methods_text, sprintf(
      " from %s occurrence records", format(n_occurrence_records, big.mark = ",")))
  }

  methods_text <- paste0(methods_text,
    " using a hierarchical biodiversity model")

  if (!is.na(n_grid_cells)) {
    methods_text <- paste0(methods_text, sprintf(
      " across %d spatial grid cells", n_grid_cells))
  }
  methods_text <- paste0(methods_text, ".")

  if (!is.null(habitat_scheme)) {
    methods_text <- paste0(methods_text, sprintf(
      " Habitat scheme: %s.", habitat_scheme))
  }

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  if (!is.na(n_taxa)) {
    results_parts <- c(results_parts, sprintf(
      "Priors were generated for %d taxa.", n_taxa))
  }

  if (!is.null(tier_breakdown)) {
    tier_strs <- vapply(names(tier_breakdown), function(nm) {
      sprintf("%s: %d", nm, tier_breakdown[[nm]])
    }, character(1L))
    results_parts <- c(results_parts, sprintf(
      "Model tier breakdown: %s.", paste(tier_strs, collapse = ", ")))
  }

  results_text <- if (length(results_parts) > 0L) {
    paste(results_parts, collapse = " ")
  } else {
    NULL
  }

  # --- Construct report_section -----------------------------------------------
  if (!requireNamespace("TaxaTools", quietly = TRUE))
    stop("report_priors: TaxaTools is required for report_section objects. ",
         "Install with: devtools::install('path/to/TaxaTools')", call. = FALSE)

  TaxaTools::new_report_section(
    package    = "TaxaExpect",
    section    = "priors",
    methods    = methods_text,
    results    = results_text,
    citations  = citations,
    params     = params,
    statistics = statistics
  )
}

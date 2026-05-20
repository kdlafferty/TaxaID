# ==============================================================================
# report_assign.R
# TaxaAssign -- Generate report_section for taxonomic assignment
#
# Exported functions:
#   report_assign()   -- generate report_section from assignment output
#
# Session 65: initial implementation
# ==============================================================================


#' Generate a Report Section for Taxonomic Assignment
#'
#' Summarizes the taxonomic assignment results into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' This function extracts key statistics from the posterior result and
#' consensus objects, producing template-based Methods and Results text.
#' For the full-featured report (with LLM-generated results prose), use
#' \code{\link{generate_report}} instead.
#'
#' @param result Data frame or \code{NULL}. Posterior output from
#'   \code{\link{compute_posterior}} or \code{\link{assign_taxa_llm}}.
#'   Required for posterior-based consensus. Pass \code{NULL} for score-based.
#' @param consensus Data frame. Output from \code{\link{posterior_consensus}}
#'   or \code{\link{score_consensus}}.
#' @param data_type Character or \code{NULL}. One of \code{"eDNA"},
#'   \code{"image"}, \code{"acoustic"}.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing assignment method.}
#'   \item{results}{Template text summarizing assignment outcomes.}
#'   \item{params}{Named list of assignment parameters.}
#'   \item{statistics}{Named list of summary counts.}
#' }
#'
#' @seealso \code{\link{generate_report}}, \code{\link{posterior_consensus}},
#'   \code{\link{score_consensus}}
#'
#' @examples
#' \dontrun{
#' sec <- report_assign(result, consensus)
#' print(sec)
#' }
#'
#' @export
report_assign <- function(result    = NULL,
                          consensus,
                          data_type = NULL,
                          verbose   = FALSE) {

  if (!is.data.frame(consensus) || nrow(consensus) == 0L)
    stop("report_assign: 'consensus' must be a non-empty data frame.",
         call. = FALSE)

  # --- Detect consensus type --------------------------------------------------
  consensus_type <- if ("top_score" %in% names(consensus)) "score" else "posterior"

  # --- Detect workflow --------------------------------------------------------
  workflow <- if (consensus_type == "score") {
    "score"
  } else if (!is.null(result) && is.data.frame(result)) {
    llm_cols <- c("range_status", "habitat_fit", "information_quality")
    if (all(llm_cols %in% names(result))) "llm" else "bayesian"
  } else {
    "posterior"
  }

  # --- Gather report_params ---------------------------------------------------
  rp <- if (!is.null(result)) attr(result, "report_params") else NULL
  cp <- attr(consensus, "report_params")
  all_params <- c(cp, rp)

  # --- Statistics -------------------------------------------------------------
  n_samples <- length(unique(consensus$observation_id))
  n_resolved <- sum(consensus$is_resolved, na.rm = TRUE)
  resolution_rate <- round(100 * n_resolved / n_samples, 1)
  n_unique_taxa <- length(unique(consensus$consensus_taxon))

  # Rank breakdown
  rank_table <- if ("consensus_rank" %in% names(consensus)) {
    as.list(table(consensus$consensus_rank))
  } else {
    NULL
  }

  statistics <- list(
    n_samples       = n_samples,
    n_resolved      = n_resolved,
    resolution_rate = resolution_rate,
    n_unique_taxa   = n_unique_taxa
  )

  # Posterior stats
  if (!is.null(result) && is.data.frame(result) &&
      "posterior_mean" %in% names(result)) {
    top <- result[order(result$observation_id, -result$posterior_mean), ]
    top <- top[!duplicated(top$observation_id), ]
    statistics$median_posterior <- round(stats::median(top$posterior_mean, na.rm = TRUE), 3)
  }

  # Score stats
  if ("top_score" %in% names(consensus)) {
    statistics$median_top_score <- round(
      stats::median(consensus$top_score, na.rm = TRUE), 2)
  }

  # --- Params -----------------------------------------------------------------
  params <- list(workflow = workflow)
  if (!is.null(data_type)) params$data_type <- data_type

  # Pull key params from report_params
  if (!is.null(all_params$cumulative_threshold))
    params$cumulative_threshold <- all_params$cumulative_threshold
  if (!is.null(all_params$n_sims))
    params$n_sims <- all_params$n_sims
  if (!is.null(all_params$min_score))
    params$min_score <- all_params$min_score

  # --- Methods text -----------------------------------------------------------
  workflow_desc <- switch(workflow,
    llm      = "LLM-shortcut Bayesian assignment with LLM-derived priors",
    bayesian = "full Bayesian assignment with occurrence-based priors",
    score    = "score-based consensus assignment",
    "taxonomic assignment"
  )

  methods_text <- sprintf(
    "Taxonomic assignments were determined using %s", workflow_desc)

  if (!is.null(data_type)) {
    methods_text <- paste0(methods_text, sprintf(" applied to %s data", data_type))
  }
  methods_text <- paste0(methods_text, ".")

  if (workflow %in% c("llm", "bayesian")) {
    threshold <- all_params$cumulative_threshold
    if (!is.null(threshold)) {
      methods_text <- paste0(methods_text, sprintf(
        " Consensus was determined at a cumulative posterior threshold of %g%%.",
        threshold * 100))
    }
  }

  if (workflow == "score" && !is.null(all_params$min_score)) {
    methods_text <- paste0(methods_text, sprintf(
      " Minimum score threshold: %g%%.", all_params$min_score))
  }

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  results_parts <- c(results_parts, sprintf(
    "Of %d observations, %d (%.1f%%) were resolved to species level.",
    n_samples, n_resolved, resolution_rate))

  results_parts <- c(results_parts, sprintf(
    "%d unique taxa were identified.", n_unique_taxa))

  if (!is.null(statistics$median_posterior) && !is.na(statistics$median_posterior)) {
    results_parts <- c(results_parts, sprintf(
      "Median top posterior probability was %.3f.", statistics$median_posterior))
  }

  if (!is.null(statistics$median_top_score) && !is.na(statistics$median_top_score)) {
    results_parts <- c(results_parts, sprintf(
      "Median top match score was %.1f%%.", statistics$median_top_score))
  }

  results_text <- paste(results_parts, collapse = " ")

  # --- Construct report_section -----------------------------------------------
  if (!requireNamespace("TaxaTools", quietly = TRUE))
    stop("report_assign: TaxaTools is required for report_section objects. ",
         "Install with: devtools::install('path/to/TaxaTools')", call. = FALSE)

  TaxaTools::new_report_section(
    package    = "TaxaAssign",
    section    = "assign",
    methods    = methods_text,
    results    = results_text,
    citations  = NULL,
    params     = params,
    statistics = statistics
  )
}

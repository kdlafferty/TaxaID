# ==============================================================================
# report_match.R
# TaxaMatch -- Summarize sequence matching for Methods/Results reporting
#
# Exported functions:
#   report_match()   -- generate report_section from match data
#
# Session 65: initial implementation
# ==============================================================================


#' Generate a Report Section for Sequence Matching
#'
#' Summarizes the match data produced by TaxaMatch into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param match_data Data frame. Match results from \code{\link{blast_sequences}}
#'   or \code{\link{standardize_match_data}}. Must contain at least
#'   \code{observation_id} and \code{score}.
#' @param data_type Character or \code{NULL}. One of \code{"eDNA"},
#'   \code{"image"}, \code{"acoustic"}. If \code{NULL}, defaults to
#'   \code{"eDNA"} when column names suggest sequence data.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing matching approach.}
#'   \item{results}{Template text summarizing match statistics.}
#'   \item{params}{Named list of matching parameters.}
#'   \item{statistics}{Named list of summary counts and scores.}
#' }
#'
#' @seealso \code{\link{blast_sequences}}, \code{\link{standardize_match_data}}
#'
#' @examples
#' \dontrun{
#' hits <- blast_sequences(seq_df, method = "remote")
#' sec <- report_match(hits)
#' print(sec)
#' }
#'
#' @export
report_match <- function(match_data,
                         data_type = NULL,
                         verbose   = FALSE) {

  if (!is.data.frame(match_data) || nrow(match_data) == 0L)
    stop("report_match: 'match_data' must be a non-empty data frame.",
         call. = FALSE)

  # --- Read report_params if available ----------------------------------------
  rp <- attr(match_data, "report_params")

  # --- Detect data type -------------------------------------------------------
  if (is.null(data_type)) {
    if ("accession" %in% names(match_data) ||
        "alignment_length" %in% names(match_data)) {
      data_type <- "eDNA"
    }
  }

  # --- Extract statistics -----------------------------------------------------
  n_samples <- if ("observation_id" %in% names(match_data)) {
    length(unique(match_data$observation_id))
  } else {
    NA_integer_
  }

  score_stats <- NULL
  if ("score_original" %in% names(match_data)) {
    scores <- match_data$score_original[!is.na(match_data$score_original)]
    if (length(scores) > 0L) {
      # Top score per observation
      if ("observation_id" %in% names(match_data)) {
        top_scores <- tapply(match_data$score_original, match_data$observation_id, max,
                             na.rm = TRUE)
      } else {
        top_scores <- scores
      }
      score_stats <- list(
        median_top_score = round(stats::median(top_scores, na.rm = TRUE), 1),
        min_top_score    = round(min(top_scores, na.rm = TRUE), 1),
        max_top_score    = round(max(top_scores, na.rm = TRUE), 1),
        n_matches        = length(scores)
      )
    }
  }

  n_taxa <- if ("taxon_name" %in% names(match_data)) {
    length(unique(match_data$taxon_name[!is.na(match_data$taxon_name)]))
  } else if ("species" %in% names(match_data)) {
    length(unique(match_data$species[!is.na(match_data$species)]))
  } else {
    NA_integer_
  }

  # Marker detection
  marker <- if ("testid" %in% names(match_data)) {
    ids <- unique(match_data$testid[!is.na(match_data$testid)])
    if (length(ids) > 0L) paste(ids, collapse = ", ") else NULL
  } else {
    NULL
  }

  statistics <- list(
    n_samples = n_samples,
    n_taxa    = n_taxa
  )

  if (!is.null(score_stats)) statistics <- c(statistics, score_stats)

  # --- Params from report_params or defaults ----------------------------------
  method    <- if (!is.null(rp$method)) rp$method else "BLAST"
  database  <- if (!is.null(rp$database)) rp$database else NULL
  min_score <- if (!is.null(rp$min_score)) rp$min_score else NULL

  params <- list(method = method)
  if (!is.null(database))  params$database  <- database
  if (!is.null(min_score)) params$min_score <- min_score
  if (!is.null(marker))    params$marker    <- marker
  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Methods text -----------------------------------------------------------
  sample_desc <- if (!is.null(data_type) && data_type == "eDNA") {
    sprintf("Environmental DNA samples (n = %s)", format(n_samples, big.mark = ","))
  } else if (!is.null(data_type)) {
    sprintf("%s detections (n = %s)", data_type, format(n_samples, big.mark = ","))
  } else {
    sprintf("Samples (n = %s)", format(n_samples, big.mark = ","))
  }

  match_desc <- sprintf("were matched using %s", method)
  if (!is.null(database)) {
    match_desc <- paste0(match_desc, sprintf(" against %s", database))
  }
  if (!is.null(min_score)) {
    match_desc <- paste0(match_desc,
                         sprintf(" with a minimum score threshold of %g%%", min_score))
  }
  match_desc <- paste0(match_desc, ".")

  if (!is.null(marker)) {
    match_desc <- paste0(match_desc, sprintf(" Target marker: %s.", marker))
  }

  methods_text <- paste(sample_desc, match_desc)

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  if (!is.null(score_stats)) {
    results_parts <- c(results_parts, sprintf(
      "Median top match score was %g%% (range: %g%%-%g%%).",
      score_stats$median_top_score,
      score_stats$min_top_score,
      score_stats$max_top_score
    ))
  }

  if (!is.na(n_taxa)) {
    results_parts <- c(results_parts, sprintf(
      "%d candidate taxa were identified across %s samples.",
      n_taxa, format(n_samples, big.mark = ",")
    ))
  }

  results_text <- if (length(results_parts) > 0L) {
    paste(results_parts, collapse = " ")
  } else {
    NULL
  }

  # --- Construct report_section -----------------------------------------------
  TaxaTools::new_report_section(
    package    = "TaxaMatch",
    section    = "match",
    methods    = methods_text,
    results    = results_text,
    citations  = NULL,
    params     = params,
    statistics = statistics
  )
}

# ==============================================================================
# report_match.R
# TaxaMatch -- Summarize sequence matching for Methods/Results reporting
#
# Exported functions:
#   report_match()   -- generate report_section from match data
#
# ==============================================================================


#' Generate a Report Section for Sequence Matching
#'
#' Summarizes the match data produced by TaxaMatch into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param match_data Data frame. Match results from \code{\link{blast_sequences}}
#'   or \code{\link{standardize_match_data}}. Must contain at least
#'   \code{observation_id} and \code{score_original} -- the canonical raw
#'   score column name produced by \code{standardize_match_data()} (see the
#'   package's "Canonical Match Object" documentation), not \code{score}. A
#'   \code{match_data} lacking \code{score_original} is accepted without
#'   error but produces no score statistics and empty results text.
#' @param data_type Character or \code{NULL}. One of \code{"eDNA"},
#'   \code{"image"}, \code{"acoustic"}. If \code{NULL}, auto-detected as
#'   \code{"eDNA"} when \code{match_data} has an \code{accession} or
#'   \code{alignment_length} column (both BLAST-specific); otherwise stays
#'   \code{NULL} and the methods/results text uses generic wording. There is
#'   currently no auto-detection for \code{"image"}/\code{"acoustic"} --
#'   pass these explicitly. \code{data_type} also controls whether the
#'   results text formats scores as a percentage (see \code{@return}'s
#'   \code{results} entry).
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing matching approach, including
#'     whatever search provenance \code{attr(match_data, "report_params")}
#'     records -- tool version, the database the search server reported, the
#'     reference database's build date, and the search date. Each sentence
#'     appears only when the match object actually carries that field, so the
#'     methods text never states a version or a date on no evidence.}
#'   \item{results}{Template text summarizing match statistics, or
#'     \code{NULL} when \code{match_data} has neither \code{score_original}
#'     nor a taxon-name column to summarize. Scores are formatted as a
#'     percentage only when \code{data_type == "eDNA"} (percent identity is
#'     always 0-100 for BLAST); for \code{"image"}/\code{"acoustic"} (whose
#'     score scale varies by classifier -- 0-1 for BirdNET/Animl, 0-100 for
#'     iNaturalist CV) the raw score value is reported unlabeled rather than
#'     guessing a scale.}
#'   \item{params}{Named list of matching parameters (\code{method},
#'     \code{database}, \code{min_score}, \code{marker} when available). May
#'     contain additional fields passed through unchanged from
#'     \code{attr(match_data, "report_params")} (e.g. \code{n_samples} and
#'     the provenance fields from \code{blast_sequences()}) whenever that
#'     attribute carries fields not already named above.}
#'   \item{statistics}{Named list of summary counts and scores.}
#' }
#'
#' @section Match objects that record no method:
#' A match object built outside \code{\link{blast_sequences}} -- an imported
#' hit list from another search tool, or a classifier export -- carries no
#' \code{report_params} attribute, and this function cannot infer what
#' produced it: such a table is indistinguishable here from a BLAST result.
#' The methods text then reports the method as unrecorded and omits the BLAST
#' citation, rather than naming a tool and citing a paper the search may have
#' no connection to. To have a published methods section name the real tool,
#' its version and its database, attach those fields as
#' \code{attr(match_data, "report_params")} before calling this function.
#'
#' @seealso \code{\link{blast_sequences}}, \code{\link{standardize_match_data}}
#'
#' @examples
#' # Self-contained example (no BLAST call needed)
#' hits <- data.frame(
#'   observation_id = c("ASV1", "ASV1", "ASV2"),
#'   score_original = c(98.5, 91.2, 99.1),
#'   taxon_name = c(
#'     "Girella nigricans", "Girella simplicidens",
#'     "Oncorhynchus mykiss"
#'   )
#' )
#' sec <- report_match(hits, data_type = "eDNA")
#' print(sec)
#'
#' \dontrun{
#' hits <- blast_sequences(seq_df, method = "remote")
#' sec <- report_match(hits)
#' print(sec)
#' }
#'
#' @export
report_match <- function(match_data,
                         data_type = NULL,
                         verbose = FALSE) {
  if (!is.data.frame(match_data) || nrow(match_data) == 0L) {
    stop("report_match: 'match_data' must be a non-empty data frame.",
      call. = FALSE
    )
  }

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
          na.rm = TRUE
        )
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
  # A match object with no report_params records no method, and this function
  # cannot infer one: an imported hit list (vsearch, a classifier export) is
  # indistinguishable here from a BLAST result. Saying "BLAST" would put a
  # method -- and, below, a BLAST citation -- into a published methods section
  # on no evidence, so an unrecorded method is reported as unrecorded.
  method_recorded <- !is.null(rp$method)
  method <- if (method_recorded) rp$method else NA_character_
  database <- if (!is.null(rp$database)) rp$database else NULL
  min_score <- if (!is.null(rp$min_score)) rp$min_score else NULL

  params <- list(method = if (method_recorded) method else "not recorded in the match object")
  if (!is.null(database)) params$database <- database
  if (!is.null(min_score)) params$min_score <- min_score
  if (!is.null(marker)) params$marker <- marker
  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Methods text -----------------------------------------------------------
  sample_desc <- if (!is.null(data_type) && data_type == "eDNA") {
    sprintf("Environmental DNA samples (n = %s)", format(n_samples, big.mark = ","))
  } else if (!is.null(data_type)) {
    sprintf("%s detections (n = %s)", data_type, format(n_samples, big.mark = ","))
  } else {
    sprintf("Samples (n = %s)", format(n_samples, big.mark = ","))
  }

  # Score scale varies by data type: eDNA percent identity is always 0-100,
  # so "%" formatting is safe there (and is the historical default when
  # data_type is unknown/NULL). Image/acoustic classifier confidence scores
  # do NOT have one universal scale across sources (BirdNET/Animl are 0-1;
  # iNaturalist CV is 0-100) -- reporting a raw, unlabeled value avoids
  # asserting a scale this function cannot verify from match_data alone.
  is_pct_scale <- is.null(data_type) || identical(data_type, "eDNA")

  match_desc <- if (method_recorded) {
    sprintf("were matched using %s", method)
  } else {
    "were matched by a method not recorded in the match object"
  }
  if (!is.null(database)) {
    match_desc <- paste0(match_desc, sprintf(" against %s", database))
  }
  if (!is.null(min_score)) {
    match_desc <- paste0(
      match_desc,
      if (is_pct_scale) {
        sprintf(" with a minimum score threshold of %g%%", min_score)
      } else {
        sprintf(" with a minimum score threshold of %g", min_score)
      }
    )
  }
  match_desc <- paste0(match_desc, ".")

  if (!is.null(marker)) {
    match_desc <- paste0(match_desc, sprintf(" Target marker: %s.", marker))
  }

  if (identical(data_type, "acoustic") || identical(data_type, "image")) {
    match_desc <- paste0(
      match_desc,
      " Candidates are ranked by classifier confidence score, not percent sequence identity."
    )
  }

  # --- Search provenance ------------------------------------------------------
  # Each field prints only when the match object actually recorded it. A
  # methods section that omits the search date is a gap; one that prints a date
  # the match object never carried is worse than the gap.
  .recorded <- function(x) !is.null(x) && length(x) >= 1L && !all(is.na(x))
  prov_parts <- character(0L)
  if (.recorded(rp$blast_version)) {
    prov_parts <- c(prov_parts, sprintf("Search tool version: %s.", rp$blast_version))
  }
  if (.recorded(rp$database_reported)) {
    prov_parts <- c(prov_parts, sprintf(
      "Database as reported by the search server: %s.", rp$database_reported
    ))
  }
  if (.recorded(rp$db_build_dates)) {
    prov_parts <- c(prov_parts, sprintf(
      "Reference database build date: %s.",
      paste(unique(stats::na.omit(rp$db_build_dates)), collapse = ", ")
    ))
  }
  if (.recorded(rp$search_started)) {
    prov_parts <- c(prov_parts, sprintf(
      "Search run: %s.", format(as.POSIXct(rp$search_started), "%Y-%m-%d")
    ))
  }

  methods_text <- paste(c(sample_desc, match_desc, prov_parts), collapse = " ")

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  if (!is.null(score_stats)) {
    results_parts <- c(results_parts, if (is_pct_scale) {
      sprintf(
        "Median top match score was %g%% (range: %g%%-%g%%).",
        score_stats$median_top_score,
        score_stats$min_top_score,
        score_stats$max_top_score
      )
    } else {
      sprintf(
        "Median top match score was %g (range: %g-%g).",
        score_stats$median_top_score,
        score_stats$min_top_score,
        score_stats$max_top_score
      )
    })
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

  if (verbose) {
    message(sprintf(
      "report_match: %s, %d sample(s), %s taxa, %s.",
      if (!is.null(data_type)) data_type else "unknown data_type",
      n_samples,
      if (!is.na(n_taxa)) n_taxa else "unknown",
      if (!is.null(score_stats)) "score statistics computed" else "no score_original column found"
    ))
  }

  # BLAST is the only method this function currently has a citable reference
  # for; image/acoustic classifier citations depend on which specific tool
  # produced match_data, which this function cannot determine from the data
  # alone.
  citations <- if (method_recorded &&
    (identical(method, "BLAST") || identical(method, "remote BLAST") ||
      identical(method, "local BLAST"))) {
    paste0(
      "Altschul SF, Gish W, Miller W, Myers EW, Lipman DJ (1990). Basic ",
      "local alignment search tool. Journal of Molecular Biology, 215(3), 403-410."
    )
  } else {
    NULL
  }

  # --- Construct report_section -----------------------------------------------
  TaxaTools::new_report_section(
    package    = "TaxaMatch",
    section    = "match",
    methods    = methods_text,
    results    = results_text,
    citations  = citations,
    params     = params,
    statistics = statistics
  )
}

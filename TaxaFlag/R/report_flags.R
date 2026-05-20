# ==============================================================================
# report_flags.R
# TaxaFlag -- Summarize quality flagging for Methods/Results reporting
#
# Exported functions:
#   report_flags()   -- generate report_section from flagged data
#
# Session 65: initial implementation
# ==============================================================================


#' Generate a Report Section for Quality Flagging
#'
#' Summarizes the quality flags applied by TaxaFlag into a structured
#' \code{report_section} object (from TaxaTools). Auto-detects which flag
#' types are present in the data. Works standalone or feeds into
#' \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param flagged_data Data frame. Assignment data with flag columns from
#'   \code{\link{flag_contaminant}}, \code{\link{flag_handler}}, and/or
#'   \code{\link{review_assignments}}.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing which flags were applied.}
#'   \item{results}{Template text summarizing flag counts.}
#'   \item{params}{Named list of flagging parameters.}
#'   \item{statistics}{Named list of flag counts.}
#' }
#'
#' @seealso \code{\link{flag_contaminant}}, \code{\link{flag_handler}},
#'   \code{\link{review_assignments}}
#'
#' @examples
#' \dontrun{
#' flagged <- flag_contaminant(data, control_samples = blanks)
#' sec <- report_flags(flagged)
#' print(sec)
#' }
#'
#' @export
report_flags <- function(flagged_data,
                         verbose = FALSE) {

  if (!is.data.frame(flagged_data) || nrow(flagged_data) == 0L)
    stop("report_flags: 'flagged_data' must be a non-empty data frame.",
         call. = FALSE)

  # --- Auto-detect flag columns -----------------------------------------------
  all_cols <- names(flagged_data)

  # Contaminant flags: flag_lab, flag_field, flag_positive, flag_control
  contaminant_cols <- grep("^flag_(lab|field|positive|control)", all_cols, value = TRUE)

  # Handler flags: flag_handler
  handler_cols <- grep("^flag_handler", all_cols, value = TRUE)

  # Review flags: review_* columns from review_assignments()
  review_cols <- grep("^review_", all_cols, value = TRUE)

  flag_types <- character(0L)
  if (length(contaminant_cols) > 0L) flag_types <- c(flag_types, "contamination")
  if (length(handler_cols) > 0L) flag_types <- c(flag_types, "handler artifacts")
  if (length(review_cols) > 0L) flag_types <- c(flag_types, "expert review")

  # --- Count flagged assignments ----------------------------------------------
  n_total <- nrow(flagged_data)

  # Count "unlikely" or "possible" in each flag column
  flag_counts <- list()

  for (col in c(contaminant_cols, handler_cols)) {
    if (col %in% all_cols) {
      vals <- flagged_data[[col]]
      n_flagged <- sum(vals %in% c("unlikely", "possible"), na.rm = TRUE)
      if (n_flagged > 0L) flag_counts[[col]] <- n_flagged
    }
  }

  # Review: check for review_confidence == "low" or similar
  if ("review_confidence" %in% all_cols) {
    n_low_conf <- sum(flagged_data$review_confidence == "low", na.rm = TRUE)
    if (n_low_conf > 0L) flag_counts[["review_low_confidence"]] <- n_low_conf
  }

  total_flagged <- if (length(flag_counts) > 0L) {
    # Unique rows flagged (at least one flag column triggered)
    flag_matrix <- vapply(c(contaminant_cols, handler_cols), function(col) {
      flagged_data[[col]] %in% c("unlikely", "possible")
    }, logical(n_total))
    if (is.matrix(flag_matrix)) {
      sum(rowSums(flag_matrix, na.rm = TRUE) > 0L)
    } else {
      sum(flag_matrix, na.rm = TRUE)
    }
  } else {
    0L
  }

  # --- Statistics -------------------------------------------------------------
  statistics <- list(
    n_total   = n_total,
    n_flagged = total_flagged,
    flag_types_detected = length(flag_types)
  )
  if (length(flag_counts) > 0L) statistics$flag_counts <- flag_counts

  # --- Params -----------------------------------------------------------------
  params <- list(flag_types = flag_types)
  rp <- attr(flagged_data, "report_params")
  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Methods text -----------------------------------------------------------
  if (length(flag_types) > 0L) {
    methods_text <- sprintf(
      "Assignments were screened for %s.",
      paste(flag_types, collapse = ", "))
  } else {
    methods_text <- "No quality flags were detected in the data."
  }

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  if (total_flagged > 0L) {
    results_parts <- c(results_parts, sprintf(
      "Of %s assignments, %d (%.1f%%) were flagged as potentially problematic.",
      format(n_total, big.mark = ","), total_flagged,
      100 * total_flagged / n_total))

    # Per-flag breakdown
    if (length(flag_counts) > 0L) {
      breakdown_strs <- vapply(names(flag_counts), function(nm) {
        sprintf("%s: %d", sub("^flag_", "", nm), flag_counts[[nm]])
      }, character(1L))
      results_parts <- c(results_parts, sprintf(
        "Breakdown: %s.", paste(breakdown_strs, collapse = ", ")))
    }
  } else {
    results_parts <- c(results_parts, sprintf(
      "Of %s assignments, none were flagged.", format(n_total, big.mark = ",")))
  }

  results_text <- paste(results_parts, collapse = " ")

  # --- Construct report_section -----------------------------------------------
  TaxaTools::new_report_section(
    package    = "TaxaFlag",
    section    = "flags",
    methods    = methods_text,
    results    = results_text,
    citations  = NULL,
    params     = params,
    statistics = statistics
  )
}

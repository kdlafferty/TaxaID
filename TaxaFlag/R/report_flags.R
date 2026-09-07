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
#' flagged <- data.frame(
#'   taxon_name    = c("Oncorhynchus mykiss", "Homo sapiens", "Salmo salar"),
#'   validity_flag = c("valid", "invalid_lab_contaminant", "questionable_lab_contaminant")
#' )
#' sec <- report_flags(flagged)
#' print(sec)
#'
#' @export
report_flags <- function(flagged_data,
                         verbose = FALSE) {

  if (!is.data.frame(flagged_data) || nrow(flagged_data) == 0L)
    stop("report_flags: 'flagged_data' must be a non-empty data frame.",
         call. = FALSE)

  # --- Auto-detect flag columns -----------------------------------------------
  all_cols <- names(flagged_data)

  # Contaminant flags — three naming conventions supported:
  #   Pre-Session 101:   flag_lab_contaminant, flag_field_contaminant, etc.
  #   Post-Session 101:  lab_contaminant_risk, field_contaminant_risk,
  #                      contamination_risk (from review_assignments())
  #   Post-2026-09-06:   llm_contamination_risk (review_assignments()'s
  #                      llm_ column rename -- see that function's own
  #                      "Column naming" roxygen section)
  contaminant_cols_old <- grep("^flag_(lab|field|positive|control)", all_cols, value = TRUE)
  contaminant_cols_new <- grep(
    "^(lab|field|positive|control)_contaminant_risk$|^contamination_risk$|^llm_contamination_risk$",
    all_cols, value = TRUE
  )
  contaminant_cols <- unique(c(contaminant_cols_old, contaminant_cols_new))

  # Handler flags: flag_handler (naming unchanged)
  handler_cols <- grep("^flag_handler", all_cols, value = TRUE)

  # Plausibility columns from review_assignments() (post-Session 101; post-
  # 2026-09-06 these are llm_habitat_plausibility/llm_geographic_plausibility/
  # llm_scope_plausibility -- suffix-matched, so the llm_ prefix needs no
  # change here):
  plausibility_cols <- grep("_plausibility$", all_cols, value = TRUE)

  # Review metadata columns: review_confidence, review_comment, etc.
  review_cols <- grep("^review_", all_cols, value = TRUE)

  # Unified validity schema (2026-07-24, flag_contaminant()/flag_handler()):
  # every TaxaFlag flag_*() mechanism now shares one literal column name
  # (validity_flag), so -- unlike every earlier naming era above, where the
  # COLUMN NAME itself identified which check produced it -- the check type
  # here has to be read out of the VALUES ("valid" / "questionable_{type}" /
  # "invalid_{type}"). This is additive to, not a replacement for, the two
  # naming eras above (a data frame built from an older flag_contaminant()/
  # flag_handler() call still detects correctly via the branches above).
  validity_flag_present <- "validity_flag" %in% all_cols
  validity_bad_values <- if (validity_flag_present) {
    vals <- flagged_data$validity_flag
    unique(vals[!is.na(vals) & vals != "valid"])
  } else {
    character(0L)
  }
  validity_types <- unique(sub("^(questionable|invalid)_", "", validity_bad_values))

  flag_types <- character(0L)
  if (length(contaminant_cols) > 0L || any(grepl("contaminant", validity_types)))
    flag_types <- c(flag_types, "contamination")
  if (length(handler_cols) > 0L || any(grepl("handling", validity_types)))
    flag_types <- c(flag_types, "handler artifacts")
  if (length(plausibility_cols) > 0L) flag_types <- c(flag_types, "plausibility review")
  if (length(review_cols) > 0L)       flag_types <- c(flag_types, "expert review")
  # Any validity_type not already covered above (e.g. a future flag_*()
  # mechanism this function doesn't have specific wording for yet) still
  # counts toward "flagging was applied", generically.
  other_validity_types <- validity_types[
    !grepl("contaminant", validity_types) & !grepl("handling", validity_types)
  ]
  if (length(other_validity_types) > 0L) flag_types <- c(flag_types, "quality validity checks")
  flag_types <- unique(flag_types)

  # --- Count flagged assignments ----------------------------------------------
  n_total <- nrow(flagged_data)

  # Count flags for each column, accounting for both value conventions:
  #   Pre-Session 101 risk:       "unlikely" / "possible" = flagged
  #   Post-Session 101 risk:      "moderate" / "high"     = flagged
  #   Post-Session 101 plausibility: "possible" / "unlikely" = flagged
  .is_flagged <- function(col) {
    vals <- flagged_data[[col]]
    (vals %in% c("unlikely", "possible")) |          # pre-101 risk + post-101 plausibility
      (vals %in% c("moderate", "high"))              # post-101 risk
  }

  flag_counts <- list()

  for (col in c(contaminant_cols, handler_cols, plausibility_cols)) {
    if (col %in% all_cols) {
      n_flagged <- sum(.is_flagged(col), na.rm = TRUE)
      if (n_flagged > 0L) flag_counts[[col]] <- n_flagged
    }
  }

  # Unified validity schema (2026-07-24): one breakdown entry per distinct
  # non-"valid" value actually present (e.g. "invalid_lab_contaminant: 12,
  # questionable_lab_contaminant: 5") -- finer-grained than the old
  # one-count-per-column convention above, since severity is now carried in
  # the value rather than being a separate per-column concept.
  for (val in validity_bad_values) {
    n_flagged <- sum(flagged_data$validity_flag == val, na.rm = TRUE)
    if (n_flagged > 0L) flag_counts[[val]] <- n_flagged
  }

  # Review: check for review_confidence == "low"
  if ("review_confidence" %in% all_cols) {
    n_low_conf <- sum(flagged_data$review_confidence == "low", na.rm = TRUE)
    if (n_low_conf > 0L) flag_counts[["review_low_confidence"]] <- n_low_conf
  }

  all_flag_cols <- intersect(
    c(contaminant_cols, handler_cols, plausibility_cols),
    all_cols
  )
  old_era_flagged <- if (length(all_flag_cols) > 0L) {
    # Unique rows where at least one flag column triggered
    flag_matrix <- vapply(all_flag_cols, .is_flagged, logical(n_total))
    if (is.matrix(flag_matrix)) {
      rowSums(flag_matrix, na.rm = TRUE) > 0L
    } else {
      flag_matrix
    }
  } else {
    rep(FALSE, n_total)
  }
  validity_flagged <- if (validity_flag_present) {
    !is.na(flagged_data$validity_flag) & flagged_data$validity_flag != "valid"
  } else {
    rep(FALSE, n_total)
  }
  total_flagged <- sum(old_era_flagged | validity_flagged, na.rm = TRUE)

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

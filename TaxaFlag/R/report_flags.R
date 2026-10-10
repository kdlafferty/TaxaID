# ==============================================================================
# report_flags.R
# TaxaFlag -- Summarize quality flagging for Methods/Results reporting
#
# Exported functions:
#   report_flags()   -- generate report_section from flagged data
# ==============================================================================


#' Generate a Report Section for Quality Flagging
#'
#' @description
#' Summarizes the quality flags applied by TaxaFlag into a structured
#' \code{report_section} object (from TaxaTools). Auto-detects which flag
#' types are present in the data. Works standalone or feeds into
#' \code{TaxaTools::assemble_report()} for a unified pipeline report. Any
#' reference-support columns from
#' \code{TaxaLikely::annotate_reference_support()} are reported next to the
#' flags and kept out of every flag count: they are information, not a flag,
#' and \strong{a low reference count does not mean a call is wrong}.
#'
#' If the data carries reference-support columns from
#' \code{TaxaLikely::annotate_reference_support()} -- any
#' \code{*_n_references} column and its companions -- their distribution is
#' reported next to the flags, and kept out of every flag count. They are
#' information, not a flag: they say how many per-species training
#' observations the likelihood model fitted that call's taxon from.
#' \strong{A low count does not mean a call is wrong}, and nothing in TaxaID
#' thresholds or filters on one; under-sequenced species that are
#' nonetheless correctly called are ordinary. Two readings in particular
#' invert the truth: a row whose basis is \code{"no_model_row"} has
#' \emph{less} reference support than any row carrying a number (too few
#' observations for a per-species row at all, typically one reference
#' sequence), not more; and a count sitting at the model's maximum is
#' censored by the sequence-matrix build, so it means "this many or more"
#' rather than an exact total. Read the basis column, never a bare
#' \code{NA}.
#'
#' @param flagged_data Data frame. Assignment data with flag columns from
#'   \code{\link{flag_contaminant}}, \code{\link{flag_handler}}, and/or
#'   \code{\link{review_assignments}}, optionally also carrying
#'   reference-support columns from
#'   \code{TaxaLikely::annotate_reference_support()}. Those columns are
#'   additive and order-independent, so annotating before or after any
#'   \code{flag_*()} call or \code{\link{add_posthoc_assessment}} gives
#'   the same result.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing which flags were applied.}
#'   \item{results}{Template text summarizing flag counts.}
#'   \item{params}{Named list of flagging parameters.}
#'   \item{statistics}{Named list of flag counts. When reference-support
#'     columns are present, also \code{reference_support}: one entry per
#'     column prefix giving \code{n_rows}, \code{n_with_count}, the
#'     \code{min}/\code{median}/\code{max} count, \code{n_at_model_max}
#'     (censored rows), and \code{basis} (how many rows fall in each
#'     situation, including the \code{"no_model_row"} rows that have the
#'     least reference support of all). None of it is added to
#'     \code{n_flagged}.}
#' }
#'
#' @seealso \code{\link{flag_contaminant}}, \code{\link{flag_handler}},
#'   \code{\link{review_assignments}}, and
#'   \code{TaxaLikely::annotate_reference_support()} for the
#'   reference-support columns this function reports but never flags on
#'
#' @examples
#' flagged <- data.frame(
#'   taxon_name    = c("Oncorhynchus mykiss", "Homo sapiens", "Salmo salar"),
#'   validity_flag = c("valid", "invalid_lab_contaminant", "questionable_lab_contaminant")
#' )
#' sec <- report_flags(flagged)
#' print(sec)
#'
#' # With reference support annotated: reported, but not flagged. Salmo salar
#' # here is the thinnest of the three despite carrying no count.
#' flagged$winner_n_references <- c(3L, 20L, NA_integer_)
#' flagged$winner_reference_basis <- c(
#'   "model_species_row", "model_species_row", "no_model_row"
#' )
#' flagged$winner_at_model_max <- c(FALSE, TRUE, NA)
#' sec2 <- report_flags(flagged)
#' sec2$statistics$reference_support$winner
#'
#' @export
report_flags <- function(flagged_data,
                         verbose = FALSE) {
  if (!is.data.frame(flagged_data) || nrow(flagged_data) == 0L) {
    stop("report_flags: 'flagged_data' must be a non-empty data frame.",
      call. = FALSE
    )
  }

  # --- Auto-detect flag columns -----------------------------------------------
  all_cols <- names(flagged_data)

  # Contaminant flags -- flagged_data may carry contamination-risk information
  # under any of three column-naming conventions, depending on which function
  # produced it:
  #   flag_lab_contaminant, flag_field_contaminant, etc. (flag_contaminant())
  #   lab_contaminant_risk, field_contaminant_risk, contamination_risk
  #     (review_assignments())
  #   llm_contamination_risk (review_assignments()'s llm_-prefixed columns --
  #     see that function's own "Column naming" roxygen section)
  contaminant_cols_old <- grep("^flag_(lab|field|positive|control)", all_cols, value = TRUE)
  contaminant_cols_new <- grep(
    "^(lab|field|positive|control)_contaminant_risk$|^contamination_risk$|^llm_contamination_risk$",
    all_cols,
    value = TRUE
  )
  contaminant_cols <- unique(c(contaminant_cols_old, contaminant_cols_new))

  # Handler flags: flag_handler (naming unchanged)
  handler_cols <- grep("^flag_handler", all_cols, value = TRUE)

  # Plausibility columns from review_assignments() -- these are
  # llm_habitat_plausibility/llm_geographic_plausibility/llm_scope_plausibility;
  # suffix-matched, so the llm_ prefix needs no change here:
  plausibility_cols <- grep("_plausibility$", all_cols, value = TRUE)

  # Review metadata columns: review_confidence, review_comment, etc.
  review_cols <- grep("^review_", all_cols, value = TRUE)

  # Reference-support columns from TaxaLikely::annotate_reference_support().
  # Suffix-matched on the count column, so any prefix is picked up (the
  # function's own `prefix` argument lets one table carry several, e.g.
  # winner_ and primary_), matching the suffix convention used for
  # plausibility columns above. These are NOT flags and are deliberately
  # kept out of every flag count below: they report how much reference data
  # the likelihood model had, which neither accuses nor clears a call.
  ref_count_cols <- grep("_n_references$", all_cols, value = TRUE)

  # Unified validity schema (flag_contaminant()/flag_handler()): every
  # TaxaFlag flag_*() mechanism shares one literal column name
  # (validity_flag), so -- unlike the column-naming conventions detected
  # above, where the COLUMN NAME itself identifies which check produced it --
  # the check type here has to be read out of the VALUES ("valid" /
  # "questionable_{type}" / "invalid_{type}"). This detection is independent
  # of, not a replacement for, the column-naming detection above: a data
  # frame using either convention is still detected correctly.
  validity_flag_present <- "validity_flag" %in% all_cols
  validity_bad_values <- if (validity_flag_present) {
    vals <- flagged_data$validity_flag
    unique(vals[!is.na(vals) & vals != "valid"])
  } else {
    character(0L)
  }
  validity_types <- unique(sub("^(questionable|invalid)_", "", validity_bad_values))

  flag_types <- character(0L)
  if (length(contaminant_cols) > 0L || any(grepl("contaminant", validity_types))) {
    flag_types <- c(flag_types, "contamination")
  }
  if (length(handler_cols) > 0L || any(grepl("handling", validity_types))) {
    flag_types <- c(flag_types, "handler artifacts")
  }
  if (length(plausibility_cols) > 0L) flag_types <- c(flag_types, "plausibility review")
  if (length(review_cols) > 0L) flag_types <- c(flag_types, "expert review")
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
  #   risk columns using "unlikely"/"possible" as the flagged values
  #   risk columns using "moderate"/"high" as the flagged values
  #   plausibility columns using "possible"/"unlikely" as the flagged values
  .is_flagged <- function(col) {
    vals <- flagged_data[[col]]
    (vals %in% c("unlikely", "possible")) | # pre-101 risk + post-101 plausibility
      (vals %in% c("moderate", "high")) # post-101 risk
  }

  flag_counts <- list()

  for (col in c(contaminant_cols, handler_cols, plausibility_cols)) {
    if (col %in% all_cols) {
      n_flagged <- sum(.is_flagged(col), na.rm = TRUE)
      if (n_flagged > 0L) flag_counts[[col]] <- n_flagged
    }
  }

  # Unified validity schema: one breakdown entry per distinct non-"valid"
  # value actually present (e.g. "invalid_lab_contaminant: 12,
  # questionable_lab_contaminant: 5") -- finer-grained than the
  # one-count-per-column convention above, since severity is carried in the
  # value rather than being a separate per-column concept.
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
    n_total = n_total,
    n_flagged = total_flagged,
    flag_types_detected = length(flag_types)
  )
  if (length(flag_counts) > 0L) statistics$flag_counts <- flag_counts

  # Reference support: distribution only. Reported per count column, each
  # alongside the basis breakdown that says why a row has no count -- the
  # breakdown is not optional context, because one of its values
  # ("no_model_row") marks calls with LESS reference support than any row
  # carrying a number, and a bare NA count would read as the opposite.
  ref_support <- list()
  for (cnt_col in ref_count_cols) {
    pfx <- sub("_n_references$", "", cnt_col)
    cnt <- suppressWarnings(as.numeric(flagged_data[[cnt_col]]))
    entry <- list(n_rows = n_total, n_with_count = sum(!is.na(cnt)))
    if (entry$n_with_count > 0L) {
      entry$min <- min(cnt, na.rm = TRUE)
      entry$median <- stats::median(cnt, na.rm = TRUE)
      entry$max <- max(cnt, na.rm = TRUE)
    }
    basis_col <- paste0(pfx, "_reference_basis")
    if (basis_col %in% all_cols) {
      bt <- table(as.character(flagged_data[[basis_col]]), useNA = "ifany")
      entry$basis <- as.list(stats::setNames(as.integer(bt), names(bt)))
    }
    max_col <- paste0(pfx, "_at_model_max")
    if (max_col %in% all_cols) {
      entry$n_at_model_max <- sum(as.logical(flagged_data[[max_col]]), na.rm = TRUE)
    }
    ref_support[[pfx]] <- entry
  }
  if (length(ref_support) > 0L) statistics$reference_support <- ref_support

  # --- Params -----------------------------------------------------------------
  params <- list(flag_types = flag_types)
  rp <- attr(flagged_data, "report_params")
  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Methods text -----------------------------------------------------------
  if (length(flag_types) > 0L) {
    methods_text <- sprintf(
      "Assignments were screened for %s.",
      paste(flag_types, collapse = ", ")
    )
  } else {
    methods_text <- "No quality flags were detected in the data."
  }
  if (length(ref_count_cols) > 0L) {
    methods_text <- paste(
      methods_text,
      paste0(
        "Reference support -- how many per-species training observations ",
        "the likelihood model fitted each call's taxon from -- is reported ",
        "alongside these flags for information only: no flag, threshold or ",
        "filter reads it, and a low count is not evidence that a call is ",
        "wrong."
      )
    )
  }

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  if (total_flagged > 0L) {
    results_parts <- c(results_parts, sprintf(
      "Of %s assignments, %d (%.1f%%) were flagged as potentially problematic.",
      format(n_total, big.mark = ","), total_flagged,
      100 * total_flagged / n_total
    ))

    # Per-flag breakdown
    if (length(flag_counts) > 0L) {
      breakdown_strs <- vapply(names(flag_counts), function(nm) {
        sprintf("%s: %d", sub("^flag_", "", nm), flag_counts[[nm]])
      }, character(1L))
      results_parts <- c(results_parts, sprintf(
        "Breakdown: %s.", paste(breakdown_strs, collapse = ", ")
      ))
    }
  } else {
    results_parts <- c(results_parts, sprintf(
      "Of %s assignments, none were flagged.", format(n_total, big.mark = ",")
    ))
  }

  for (pfx in names(ref_support)) {
    e <- ref_support[[pfx]]
    if (e$n_with_count > 0L) {
      results_parts <- c(results_parts, sprintf(
        paste0(
          "Reference support (%s): %d of %s calls carry a per-species ",
          "reference count, median %s (range %s-%s)%s."
        ),
        pfx, e$n_with_count, format(e$n_rows, big.mark = ","),
        format(e$median), format(e$min), format(e$max),
        if (!is.null(e$n_at_model_max) && e$n_at_model_max > 0L) {
          sprintf(
            "; %d at the model's maximum, where the build censors the count",
            e$n_at_model_max
          )
        } else {
          ""
        }
      ))
    } else {
      results_parts <- c(results_parts, sprintf(
        "Reference support (%s): no call carries a per-species reference count.",
        pfx
      ))
    }
    no_row <- if (!is.null(e$basis)) e$basis[["no_model_row"]] else NULL
    if (!is.null(no_row) && no_row > 0L) {
      results_parts <- c(results_parts, sprintf(
        paste0(
          "A further %d call(s) have no per-species row in the model at all ",
          "-- fewer training observations than it fits, so less reference ",
          "support than any counted call, not more."
        ),
        no_row
      ))
    }
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

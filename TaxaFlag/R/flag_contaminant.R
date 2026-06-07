utils::globalVariables(c("n_reads", "total_reads", "prop", "mean_prop",
                         "is_control", "n_controls_present", "n_controls_total",
                         "mean_prop_field", "mean_prop_control",
                         "contaminant_score"))

#' Flag Potential Contaminants by Comparison to Control Samples
#'
#' Compares read proportions between field samples and control samples
#' (negative controls or positive controls) to identify taxa that may be
#' contaminants. Supports extraction controls, PCR controls, field controls,
#' and positive controls.
#'
#' The algorithm computes within-sample proportions for each taxon, then
#' compares mean proportions in field samples vs. controls. Taxa with higher
#' proportions in controls than field samples receive low scores (likely
#' contaminants); taxa absent from controls receive a score of 1.0.
#'
#' For positive controls, the interpretation is inverted: taxa from the
#' positive control appearing in field samples indicate cross-contamination.
#'
#' @param df Data frame in long format with at minimum columns for sample
#'   identification, taxon identification, and read counts.
#' @param event_col Character. Column name identifying collection events
#'   (e.g., individual filters, bottles, or deployments). Default
#'   \code{"event_id"}.
#' @param taxon_col Character. Column name identifying taxa (species, ESV,
#'   ASV, etc.). Default \code{"taxon_name"}.
#' @param reads_col Character. Column name with integer read counts. Default
#'   \code{"n_reads"}.
#' @param control_samples Character vector of sample IDs that are controls
#'   (negative controls or positive controls). Mutually exclusive with
#'   \code{sample_type_col}; at least one must be supplied.
#' @param sample_type_col Character. Column name containing sample type
#'   labels. When supplied, \code{control_types} identifies which values are
#'   controls. Mutually exclusive with \code{control_samples}.
#' @param control_types Character vector of values in \code{sample_type_col}
#'   that identify control samples. Required when \code{sample_type_col} is
#'   used. Default \code{NULL}.
#' @param exclude_samples Character vector of sample IDs to exclude from
#'   both control and field calculations. Use to remove e.g. extraction controls
#'   when analysing PCR controls, or vice versa. Default \code{NULL}.
#' @param contaminant_type Character. Label for the type of contamination
#'   being assessed. Controls output column names:
#'   \code{{contaminant_type}_risk}, \code{{contaminant_type}_score},
#'   \code{{contaminant_type}_reason}. Common values: \code{"lab_contaminant"},
#'   \code{"field_contaminant"}, \code{"positive_control"}. Default
#'   \code{"lab_contaminant"}.
#' @param score_thresholds Numeric vector of length 2. Thresholds for
#'   converting scores to risk values. Scores at or below the first value
#'   are \code{"high"} risk (probable contaminant); scores at or below the
#'   second are \code{"moderate"} risk; higher scores are \code{"low"} risk
#'   (likely a genuine detection). Default \code{c(0.5, 0.9)}.
#' @param verbose Logical. Print summary messages. Default \code{TRUE}.
#'
#' @return A data frame with one row per taxon, sorted by score (most
#'   likely contaminants first). Columns:
#' \describe{
#'   \item{\code{{taxon_col}}}{Taxon identifier (from input).}
#'   \item{\code{flag_{contaminant_type}_score}}{Numeric 0--1. Ratio of
#'     field proportion to total (field + control) proportion. Higher = more
#'     likely a real detection. 1.0 for taxa absent from controls.}
#'   \item{\code{{contaminant_type}_risk}}{Character. \code{"high"} (probable
#'     contaminant), \code{"moderate"} (uncertain), or \code{"low"} (likely
#'     genuine detection). Higher = more contamination risk.}
#'   \item{\code{flag_{contaminant_type}_reason}}{Character. Plain-English
#'     explanation including proportions and control detection counts.}
#'   \item{\code{mean_prop_field}}{Mean within-sample proportion in field
#'     samples.}
#'   \item{\code{mean_prop_control}}{Mean within-sample proportion in control
#'     samples.}
#'   \item{\code{n_controls_present}}{Number of controls in which the taxon was
#'     detected.}
#'   \item{\code{n_controls_total}}{Total number of controls.}
#' }
#'
#' @seealso \code{\link{flag_handler}}, \code{\link{review_assignments}}
#'
#' @examples
#' \dontrun{
#' # Identify extraction control columns, flag contaminants
#' flagged <- flag_contaminant(
#'   df             = reads_long,
#'   control_samples  = c("Palmyra30", "Palmyra62"),
#'   contaminant_type = "lab_contaminant"
#' )
#'
#' # Using sample_type column instead
#' flagged <- flag_contaminant(
#'   df              = reads_long,
#'   sample_type_col = "sample_type",
#'   control_types     = c("extraction_blank", "pcr_blank"),
#'   contaminant_type = "lab_contaminant"
#' )
#'
#' # Flag positive control leakage
#' flagged <- flag_contaminant(
#'   df               = reads_long,
#'   control_samples    = c("Palmyra32", "Palmyra64"),
#'   exclude_samples  = c("Palmyra30", "Palmyra31", "Palmyra62", "Palmyra63"),
#'   contaminant_type = "positive_control"
#' )
#' }
#'
#' @export
flag_contaminant <- function(df,
                             event_col       = "event_id",
                             taxon_col        = "taxon_name",
                             reads_col        = "n_reads",
                             control_samples    = NULL,
                             sample_type_col  = NULL,
                             control_types      = NULL,
                             exclude_samples  = NULL,
                             contaminant_type = "lab_contaminant",
                             score_thresholds = c(0.5, 0.9),
                             verbose          = TRUE) {

  # --- Input validation ---
  if (!is.data.frame(df)) stop("'df' must be a data frame.", call. = FALSE)

  for (col in c(event_col, taxon_col, reads_col)) {
    if (!col %in% names(df))
      stop(sprintf("Column '%s' not found in df.", col), call. = FALSE)
  }

  if (!is.numeric(df[[reads_col]]))
    stop(sprintf("Column '%s' must be numeric.", reads_col), call. = FALSE)

  if (is.null(control_samples) && is.null(sample_type_col))
    stop("Supply either 'control_samples' or 'sample_type_col' to identify controls.",
         call. = FALSE)

  if (!is.null(control_samples) && !is.null(sample_type_col))
    stop("Supply 'control_samples' OR 'sample_type_col', not both.", call. = FALSE)

  if (!is.null(sample_type_col)) {
    if (!sample_type_col %in% names(df))
      stop(sprintf("Column '%s' not found in df.", sample_type_col), call. = FALSE)
    if (is.null(control_types) || length(control_types) == 0L)
      stop("'control_types' required when using 'sample_type_col'.", call. = FALSE)
  }

  if (!is.numeric(score_thresholds) || length(score_thresholds) != 2L)
    stop("'score_thresholds' must be a numeric vector of length 2.", call. = FALSE)

  if (!is.character(contaminant_type) || length(contaminant_type) != 1L)
    stop("'contaminant_type' must be a single character string.", call. = FALSE)

  # --- Resolve control vs field samples ---
  all_samples <- unique(df[[event_col]])

  # Exclude samples first

  if (!is.null(exclude_samples)) {
    df <- df[!df[[event_col]] %in% exclude_samples, , drop = FALSE]
    all_samples <- setdiff(all_samples, exclude_samples)
  }

  # Identify controls
  if (!is.null(control_samples)) {
    control_ids <- intersect(control_samples, all_samples)
    if (length(control_ids) == 0L)
      stop("None of 'control_samples' found in df after exclusions.", call. = FALSE)
  } else {
    control_ids <- unique(df[[event_col]][df[[sample_type_col]] %in% control_types])
    if (length(control_ids) == 0L)
      stop(sprintf("No samples match control_types '%s' in column '%s'.",
                    paste(control_types, collapse = "', '"), sample_type_col),
           call. = FALSE)
  }

  field_ids <- setdiff(all_samples, control_ids)
  if (length(field_ids) == 0L)
    stop("No field samples remaining after identifying controls and exclusions.",
         call. = FALSE)

  if (verbose) {
    message(sprintf("flag_contaminant (%s): %d control(s), %d field sample(s), %d excluded.",
                    contaminant_type, length(control_ids), length(field_ids),
                    length(if (is.null(exclude_samples)) character(0) else exclude_samples)))
  }

  # --- Compute scores ---
  scores <- .compute_contaminant_scores(
    df         = df,
    event_col = event_col,
    taxon_col  = taxon_col,
    reads_col  = reads_col,
    control_ids  = control_ids,
    field_ids  = field_ids
  )

  # --- Apply thresholds to get risk levels ---
  # score = field / (field + control); low score = probable contaminant = high risk
  scores$flag <- dplyr::case_when(
    scores$contaminant_score <= score_thresholds[1] ~ "high",
    scores$contaminant_score <= score_thresholds[2] ~ "moderate",
    TRUE ~ "low"
  )

  # --- Build reason strings ---
  scores$reason <- sprintf(
    "field proportion %.4f, control proportion %.4f, score %.3f; detected in %d/%d control(s)",
    scores$mean_prop_field, scores$mean_prop_control,
    scores$contaminant_score, scores$n_controls_present, scores$n_controls_total
  )

  # --- Build per-taxon result ---
  flag_col    <- paste0(contaminant_type, "_risk")
  score_col   <- paste0(contaminant_type, "_score")
  reason_col  <- paste0(contaminant_type, "_reason")

  result <- data.frame(
    taxon            = scores$taxon,
    score            = scores$contaminant_score,
    flag             = scores$flag,
    reason           = scores$reason,
    mean_prop_field  = scores$mean_prop_field,
    mean_prop_control  = scores$mean_prop_control,
    n_controls_present = scores$n_controls_present,
    n_controls_total   = scores$n_controls_total,
    stringsAsFactors = FALSE
  )
  names(result) <- c(taxon_col, score_col, flag_col, reason_col,
                     "mean_prop_field", "mean_prop_control",
                     "n_controls_present", "n_controls_total")

  # Sort by score (most likely contaminants first)
  result <- result[order(result[[score_col]]), , drop = FALSE]
  rownames(result) <- NULL

  if (verbose) {
    n_high     <- sum(result[[flag_col]] == "high")
    n_moderate <- sum(result[[flag_col]] == "moderate")
    n_low      <- sum(result[[flag_col]] == "low")
    message(sprintf("  %d taxa scored: %d high risk, %d moderate risk, %d low risk.",
                    nrow(result), n_high, n_moderate, n_low))
  }

  result
}


#' Compute Contaminant Scores from Read Proportions
#'
#' Internal helper. Computes within-sample proportions for each taxon,
#' then compares mean proportions between field and control samples.
#'
#' @param df Data frame in long format.
#' @param event_col,taxon_col,reads_col Column name strings.
#' @param control_ids,field_ids Character vectors of sample IDs.
#'
#' @return Data frame with one row per taxon and columns: \code{taxon},
#'   \code{mean_prop_field}, \code{mean_prop_control}, \code{n_controls_present},
#'   \code{n_controls_total}, \code{contaminant_score}.
#'
#' @noRd
.compute_contaminant_scores <- function(df, event_col, taxon_col, reads_col,
                                        control_ids, field_ids) {

  # Standardise column names for internal use
  work <- data.frame(
    sample   = df[[event_col]],
    taxon    = df[[taxon_col]],
    n_reads  = df[[reads_col]],
    stringsAsFactors = FALSE
  )

  # Remove zero-read rows

  work <- work[work$n_reads > 0, , drop = FALSE]

  # Within-sample proportions
  sample_totals <- stats::aggregate(n_reads ~ sample, data = work, FUN = sum)
  names(sample_totals)[2] <- "total_reads"
  work <- merge(work, sample_totals, by = "sample")
  work$prop <- work$n_reads / work$total_reads

  # Tag control vs field
  work$is_control <- work$sample %in% control_ids

  # Get all unique taxa
  all_taxa <- unique(work$taxon)
  n_controls_total <- length(control_ids)

  # Mean proportion per taxon in field vs control
  results <- lapply(all_taxa, function(tx) {
    tx_rows <- work[work$taxon == tx, , drop = FALSE]
    field_rows <- tx_rows[!tx_rows$is_control, , drop = FALSE]
    control_rows <- tx_rows[tx_rows$is_control, , drop = FALSE]

    mean_prop_field <- if (nrow(field_rows) > 0L) mean(field_rows$prop) else 0
    mean_prop_control <- if (nrow(control_rows) > 0L) mean(control_rows$prop) else 0
    n_controls_present <- length(unique(control_rows$sample))

    # Score: field / (field + control). Taxa absent from controls get 1.0
    if (mean_prop_control == 0) {
      score <- 1.0
    } else if (mean_prop_field == 0) {
      score <- 0.0
    } else {
      score <- mean_prop_field / (mean_prop_field + mean_prop_control)
    }

    data.frame(
      taxon            = tx,
      mean_prop_field  = mean_prop_field,
      mean_prop_control  = mean_prop_control,
      n_controls_present = n_controls_present,
      n_controls_total   = n_controls_total,
      contaminant_score = score,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, results)
}

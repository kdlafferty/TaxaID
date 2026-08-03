utils::globalVariables(c("n_reads", "seq_length", "min_reads", "max_reads", "quantile_reads",
                         "total_reads", "n_samples_detected"))

#' Build per-observation covariates for modelling a review classification
#'
#' Collapses a long-format reads table (one row per taxon x sample) to one
#' row per observation, joined to a categorical classification column (e.g.
#' \code{\link{add_posthoc_assessment}}'s \code{primary_plausibility}/
#' \code{primary_discrimination}, or any \code{\link{review_assignments}}
#' output column). Intended as the training-
#' data step for a model relating observation-level attributes (sequence
#' length, read depth, detection breadth, blank frequency) to how an
#' observation was classified -- see \code{\link{model_review_classification}}.
#'
#' \strong{Field denominator:} \code{prop_samples_detected} is computed
#' against the TOTAL number of distinct field (non-control) samples present
#' anywhere in \code{reads_df} -- not just among samples where the
#' observation itself occurs -- so it is genuinely relative to sampling
#' effort.
#'
#' \strong{Blank frequency:} rather than recompute a raw blank-detection
#' proportion, this function joins in \code{\link{flag_contaminant}}'s own
#' \code{control_rate} (and any other columns requested via
#' \code{contaminant_cols}) when \code{contaminant_df} is supplied --
#' \code{control_rate} is depth-weighted and Empirical-Bayes-shrunk (see
#' \code{\link{flag_contaminant}}'s Design section), a better-calibrated
#' signal than a raw count-of-blanks-detected-in proportion, and this avoids
#' computing the same thing two different ways in two different places.
#'
#' @param reads_df Long-format data frame: one row per taxon x sample, with
#'   a taxon identifier, a sample/event identifier, a read-count column, and
#'   (optionally) a sequence column. Matches the input shape of
#'   \code{\link{flag_contaminant}}.
#' @param classification_df Data frame with a taxon identifier and a
#'   classification column to be modelled -- typically
#'   \code{\link{add_posthoc_assessment}}'s output or a
#'   \code{\link{review_assignments}} output column.
#' @param taxon_col Character. Taxon/observation identifier column in
#'   \code{reads_df} (default \code{"ESVId"}).
#' @param classification_taxon_col Character. Taxon/observation identifier
#'   column in \code{classification_df} (default \code{"observation_id"} --
#'   this ecosystem's consensus/review tables use a different id-column name
#'   than its read-count tables by convention).
#' @param classification_col Character. Column in \code{classification_df}
#'   holding the categorical label to model (default
#'   \code{"primary_plausibility"} -- \code{add_posthoc_assessment()}'s
#'   retired \code{posthoc_assessment} column is no longer produced; any
#'   axis column, or a \code{review_assignments()} output column, works
#'   equally well here).
#' @param event_col Character. Sample/event identifier column in
#'   \code{reads_df} (default \code{"event_id"}).
#' @param reads_col Character. Read-count column in \code{reads_df} (default
#'   \code{"n_reads"}).
#' @param sequence_col Character or \code{NULL}. Sequence column in
#'   \code{reads_df}, used to derive \code{seq_length}. Set \code{NULL} to
#'   skip (default \code{"sequence"}).
#' @param control_samples Character vector of \code{event_col} values that
#'   are blanks/controls -- same convention as
#'   \code{\link{flag_contaminant}}'s own \code{control_samples} parameter.
#'   Used ONLY to exclude blank samples from the field-side read-depth/
#'   detection-breadth covariates (\code{min_reads}, \code{max_reads},
#'   \code{quantile_reads}, \code{total_reads}, \code{n_samples_detected},
#'   \code{prop_samples_detected});
#'   blank-frequency
#'   itself comes from \code{contaminant_df}, not from this argument. Default
#'   \code{NULL} (no samples excluded -- appropriate if \code{reads_df} is
#'   already field-only).
#' @param contaminant_df Data frame or \code{NULL} (default). Output of
#'   \code{\link{flag_contaminant}}, joined in to supply blank-frequency
#'   covariates. \code{NULL} omits these columns entirely.
#' @param contaminant_taxon_col Character. Taxon identifier column in
#'   \code{contaminant_df} (default \code{taxon_col}'s value -- matches
#'   \code{flag_contaminant()}'s own convention of echoing back whatever
#'   \code{taxon_col} it was called with).
#' @param contaminant_cols Character vector. Columns from
#'   \code{contaminant_df} to join onto the result (default
#'   \code{"control_rate"}). Common additions: \code{"field_rate"}, or
#'   \code{flag_contaminant()}'s own \code{"observation_validity"}/
#'   \code{"validity_flag"} columns (2026-07-24 -- fixed names now, no
#'   longer prefixed by \code{contaminant_type}; see that function's docs).
#' @param extra_covariate_cols Character vector or \code{NULL} (default).
#'   Additional columns to carry through unchanged from
#'   \code{classification_df} -- e.g. \code{"winner_likelihood"}
#'   (sequence-match confidence from \code{TaxaAssign::posterior_consensus()})
#'   or \code{"consensus_rank"} (taxonomic resolution), when
#'   \code{classification_df} already has them (as
#'   \code{TaxaAssign::posterior_consensus()} / \code{\link{review_assignments}}
#'   output typically does). These are read-count-independent covariates that
#'   don't need \code{reads_df} at all, so they're passed through rather than
#'   recomputed.
#' @param read_quantile Numeric in (0, 1] (default \code{0.9}). Quantile of
#'   per-sample field read counts used for \code{quantile_reads} (see
#'   \code{@return} below). \code{1} reproduces \code{max_reads}.
#'
#' @return One row per \code{classification_df} row, with:
#' \describe{
#'   \item{\code{observation_id}}{From \code{classification_taxon_col}.}
#'   \item{\code{classification}}{From \code{classification_col}.}
#'   \item{\code{seq_length}}{Sequence length in bp (omitted if
#'     \code{sequence_col = NULL}).}
#'   \item{\code{min_reads}}{Minimum per-sample read count among field
#'     (non-control) samples where the observation was detected -- the
#'     weakest single piece of support. Mostly reflects normal within-taxon
#'     variability across replicate samples (even a genuine, common species
#'     will show some weak detections) rather than overall evidence quality,
#'     since it can only get worse as more samples are added.}
#'   \item{\code{max_reads}}{Maximum per-sample read count among field
#'     samples -- the strongest single piece of support this observation
#'     ever received. A better signal for "was this ever well-supported"
#'     than \code{min_reads}: a low \code{max_reads} means no sample ever
#'     gave strong support, which is a more direct read on whether the
#'     observation itself is thin, rather than just noisy in one replicate.
#'     Caution: \code{max_reads} is an extreme-value statistic -- the maximum
#'     of \eqn{n} draws stochastically increases with \eqn{n} even when the
#'     underlying per-sample distribution is identical, so \code{max_reads}
#'     is mechanically inflated for taxa detected in many samples, confounding
#'     it with \code{n_samples_detected}/\code{prop_samples_detected}
#'     independent of true evidence strength. Confirmed on real data: mean
#'     \code{max_reads} rose ~260x from taxa detected in 1 sample to taxa
#'     detected in 50+, versus ~47x for \code{quantile_reads} at the default
#'     \code{read_quantile = 0.9} over the same range -- prefer
#'     \code{quantile_reads} unless \code{max_reads} itself (not a robust
#'     summary of it) is specifically what a downstream QC rule acts on.}
#'   \item{\code{quantile_reads}}{The \code{read_quantile}-th quantile
#'     (default 90th percentile) of per-sample field read counts -- a less
#'     extreme-value-sensitive alternative to \code{max_reads} that still
#'     captures "how strong was this observation's best-supported evidence,"
#'     without being as mechanically driven by how many samples it was
#'     detected in.}
#'   \item{\code{total_reads}}{Summed read count among field samples.}
#'   \item{\code{n_samples_detected}}{Count of distinct field samples with
#'     \code{reads_col > 0} for this observation.}
#'   \item{\code{prop_samples_detected}}{\code{n_samples_detected} divided by
#'     the total distinct field samples in \code{reads_df}.}
#'   \item{\code{contaminant_cols}}{Whichever \code{contaminant_df} columns
#'     were requested, present only when \code{contaminant_df} is supplied.}
#' }
#' Observations with zero field-sample detections (including taxa present
#' only in control samples) get \code{0}/\code{0L} for detection counts/
#' proportions and \code{total_reads}, and \code{NA} for \code{min_reads}/
#' \code{max_reads} (undefined for zero observations) -- a legitimate result, not a data gap,
#' so this does not warn. Observations absent from \code{reads_df} entirely
#' (no row at all, field or control) get the same zero-fill plus \code{NA}
#' \code{seq_length}, WITH a warning naming them -- this usually signals an
#' id-mismatch or a genuinely orphaned \code{classification_df} row. The same
#' applies, separately, to rows absent from \code{contaminant_df} when it is
#' supplied.
#'
#' @examples
#' reads <- data.frame(
#'   ESVId    = c("ESV_1", "ESV_1", "ESV_1", "ESV_2", "ESV_2"),
#'   sequence = c("ACGTACGT", "ACGTACGT", "ACGTACGT", "ACGT", "ACGT"),
#'   event_id = c("s1", "s2", "blank1", "s1", "s2"),
#'   n_reads  = c(100, 50, 2, 5, 0)
#' )
#' cls <- data.frame(
#'   observation_id = c("ESV_1", "ESV_2"),
#'   primary_plausibility = c("expected", "unexpected")
#' )
#' build_review_covariates(reads, cls, control_samples = "blank1")
#'
#' @seealso \code{\link{model_review_classification}},
#'   \code{\link{add_posthoc_assessment}}, \code{\link{flag_contaminant}}
#' @importFrom dplyr filter group_by summarise ungroup n_distinct left_join
#' @export
build_review_covariates <- function(reads_df,
                                     classification_df,
                                     taxon_col                = "ESVId",
                                     classification_taxon_col = "observation_id",
                                     classification_col       = "primary_plausibility",
                                     event_col                 = "event_id",
                                     reads_col                 = "n_reads",
                                     sequence_col               = "sequence",
                                     control_samples            = NULL,
                                     contaminant_df              = NULL,
                                     contaminant_taxon_col       = taxon_col,
                                     contaminant_cols            = "control_rate",
                                     extra_covariate_cols        = NULL,
                                     read_quantile                = 0.9) {

  # ---- validate -----------------------------------------------------------
  if (!is.data.frame(reads_df))
    stop("build_review_covariates: 'reads_df' must be a data frame.", call. = FALSE)
  if (!is.numeric(read_quantile) || length(read_quantile) != 1L ||
      is.na(read_quantile) || read_quantile <= 0 || read_quantile > 1)
    stop("build_review_covariates: 'read_quantile' must be a single number in (0, 1].", call. = FALSE)
  if (!is.data.frame(classification_df))
    stop("build_review_covariates: 'classification_df' must be a data frame.", call. = FALSE)
  for (col in c(taxon_col, event_col, reads_col))
    if (!col %in% names(reads_df))
      stop(sprintf("build_review_covariates: column '%s' not found in reads_df.", col),
           call. = FALSE)
  for (col in c(classification_taxon_col, classification_col, extra_covariate_cols))
    if (!col %in% names(classification_df))
      stop(sprintf("build_review_covariates: column '%s' not found in classification_df.", col),
           call. = FALSE)
  if (!is.null(sequence_col) && !sequence_col %in% names(reads_df))
    stop(sprintf("build_review_covariates: column '%s' not found in reads_df.", sequence_col),
         call. = FALSE)
  if (!is.null(contaminant_df)) {
    if (!is.data.frame(contaminant_df))
      stop("build_review_covariates: 'contaminant_df' must be a data frame or NULL.", call. = FALSE)
    for (col in c(contaminant_taxon_col, contaminant_cols))
      if (!col %in% names(contaminant_df))
        stop(sprintf("build_review_covariates: column '%s' not found in contaminant_df.", col),
             call. = FALSE)
  }

  # ---- split field vs. control rows ----------------------------------------
  reads_df <- reads_df[reads_df[[reads_col]] > 0, , drop = FALSE]
  field_df <- reads_df[!reads_df[[event_col]] %in% control_samples, , drop = FALSE]

  n_field_samples <- dplyr::n_distinct(field_df[[event_col]])

  # ---- field-side per-taxon aggregates -------------------------------------
  field_agg <- field_df |>
    dplyr::group_by(.data[[taxon_col]]) |>
    dplyr::summarise(
      min_reads           = min(.data[[reads_col]]),
      max_reads           = max(.data[[reads_col]]),
      quantile_reads      = stats::quantile(.data[[reads_col]], read_quantile, type = 7, names = FALSE),
      total_reads         = sum(.data[[reads_col]]),
      n_samples_detected  = dplyr::n_distinct(.data[[event_col]]),
      .groups = "drop"
    )
  field_agg$prop_samples_detected <-
    if (n_field_samples > 0L) field_agg$n_samples_detected / n_field_samples else NA_real_

  # ---- sequence length (one value per taxon; warn if inconsistent) --------
  if (!is.null(sequence_col)) {
    seq_agg <- reads_df |>
      dplyr::group_by(.data[[taxon_col]]) |>
      dplyr::summarise(
        seq_length   = nchar(.data[[sequence_col]][1]),
        n_seq_lengths = dplyr::n_distinct(nchar(.data[[sequence_col]])),
        .groups = "drop"
      )
    inconsistent <- seq_agg[[taxon_col]][seq_agg$n_seq_lengths > 1L]
    if (length(inconsistent) > 0L)
      warning(sprintf(
        "build_review_covariates: %d taxon/taxa have more than one distinct sequence length; using the first occurrence: %s",
        length(inconsistent), paste(utils::head(inconsistent, 5L), collapse = ", ")
      ), call. = FALSE)
    seq_agg$n_seq_lengths <- NULL
  }

  # ---- assemble result: one row per classification_df row -----------------
  result <- data.frame(
    observation_id = classification_df[[classification_taxon_col]],
    classification  = classification_df[[classification_col]],
    stringsAsFactors = FALSE
  )
  for (col in extra_covariate_cols)
    result[[col]] <- classification_df[[col]]

  result <- dplyr::left_join(result, field_agg,
                              by = c("observation_id" = taxon_col))
  if (!is.null(sequence_col))
    result <- dplyr::left_join(result, seq_agg,
                                by = c("observation_id" = taxon_col))

  # "No field detections" (n_samples_detected NA after the left_join) is a
  # legitimate, common, NON-alarming outcome -- e.g. a taxon present only in
  # a blank sample, or a taxon that genuinely never appears in this
  # particular reads_df subset. It is NOT the same as "absent from reads_df
  # entirely", which is worth a warning since it usually means an id-mismatch
  # or a genuinely orphaned classification_df row. Distinguish the two
  # explicitly rather than warning on every zero-detection row.
  all_taxa_in_reads <- unique(as.character(reads_df[[taxon_col]]))
  truly_absent <- !result$observation_id %in% all_taxa_in_reads
  if (any(truly_absent))
    warning(sprintf(
      "build_review_covariates: %d observation(s) in classification_df had no matching rows in reads_df at all: %s",
      sum(truly_absent), paste(utils::head(result$observation_id[truly_absent], 5L), collapse = ", ")
    ), call. = FALSE)

  # Zero-fill detection counts/proportions for every row with no field
  # detections (both the truly-absent and the control-only cases) -- a real
  # zero, not a missing value. total_reads (sum of nothing) is also a real
  # zero; min_reads/max_reads/quantile_reads (a quantile of nothing) have no
  # defined value and stay NA.
  no_field <- is.na(result$n_samples_detected)
  result$n_samples_detected[no_field] <- 0L
  result$prop_samples_detected[no_field] <- 0
  result$total_reads[no_field] <- 0

  # ---- join in blank-frequency covariates from flag_contaminant() ---------
  if (!is.null(contaminant_df)) {
    join_cols <- unique(c(contaminant_taxon_col, contaminant_cols))
    contaminant_sub <- contaminant_df[, join_cols, drop = FALSE]
    result <- dplyr::left_join(result, contaminant_sub,
                                by = c("observation_id" = contaminant_taxon_col))

    missing_contam <- is.na(result[[contaminant_cols[1]]])
    if (any(missing_contam))
      warning(sprintf(
        "build_review_covariates: %d observation(s) had no matching rows in contaminant_df: %s",
        sum(missing_contam), paste(utils::head(result$observation_id[missing_contam], 5L), collapse = ", ")
      ), call. = FALSE)
  }

  result
}

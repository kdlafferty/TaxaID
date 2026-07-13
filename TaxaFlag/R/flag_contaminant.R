utils::globalVariables(c("n_reads", "total_reads", "prop", "mean_prop",
                         "is_control", "n_controls_present", "n_controls_total",
                         "mean_prop_field", "mean_prop_control",
                         "n_reads_total", "contaminant_score"))

#' Flag Potential Contaminants by Comparison to Control Samples
#'
#' Compares read proportions between field samples and control samples
#' (negative controls or positive controls) to identify taxa that may be
#' contaminants. Supports extraction controls, PCR controls, field controls,
#' and positive controls.
#'
#' The algorithm computes a read-depth-weighted detection rate per taxon in
#' field samples vs. controls, then an Empirical Bayes-shrunk score
#' comparing them (\code{.compute_contaminant_scores()}'s own internal
#' documentation has the full mechanism and the real-data motivation for
#' it). Taxa with a higher rate in controls than field samples receive low
#' scores (likely contaminants); taxa strongly favoring field samples
#' receive scores approaching, but not reaching, 1.0 -- shrinkage means no
#' taxon gets an absolute 0 or 1 score purely from having little total read
#' support (Session 152 -- shrinkage strength is measured in reads, not
#' samples; see \code{.compute_contaminant_scores()}'s documentation).
#'
#' \strong{This score is a ranked screening statistic, not a calibrated
#' probability.} Earlier versions of this documentation described it as
#' "the probability the detection reflects true presence" -- it is not:
#' no generative model of contamination is fit, and the score is not
#' validated against known-true contamination status. Use it to rank taxa
#' for review against \code{score_thresholds}, not as a literal posterior
#' probability.
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
#' @param prior_weight Numeric (default \code{20}). Empirical Bayes shrinkage
#'   strength, in units of "equivalent reads" (Session 152 -- see
#'   \code{.compute_contaminant_scores()}'s own documentation for why this
#'   changed from "equivalent samples" in Session 151). Controls how strongly
#'   the final field-vs-control ratio is pulled toward 0.5 (maximally
#'   uncertain) when a taxon has little total read support overall. Higher
#'   values shrink harder (more conservative, less willing to call a
#'   thinly-supported taxon confidently clean or contaminated); \code{0}
#'   disables shrinkage entirely, restoring the raw depth-weighted ratio.
#' @param verbose Logical. Print summary messages. Default \code{TRUE}.
#'
#' @return A data frame with one row per taxon, sorted by score (most
#'   likely contaminants first). Columns:
#' \describe{
#'   \item{\code{{taxon_col}}}{Taxon identifier (from input).}
#'   \item{\code{flag_{contaminant_type}_score}}{Numeric 0--1. Empirical
#'     Bayes-shrunk ratio of the depth-weighted field rate to the total
#'     (field + control) rate. Higher = more likely a real detection.
#'     Approaches, but does not reach, 1.0 for taxa absent from controls --
#'     see Details. A ranked screening statistic, not a calibrated
#'     probability.}
#'   \item{\code{{contaminant_type}_risk}}{Character. \code{"high"} (probable
#'     contaminant), \code{"moderate"} (uncertain), or \code{"low"} (likely
#'     genuine detection). Higher = more contamination risk.}
#'   \item{\code{flag_{contaminant_type}_reason}}{Character. Plain-English
#'     explanation including depth-weighted rates and control detection counts.}
#'   \item{\code{mean_prop_field}}{Informational only, does not drive the
#'     score (Session 151): unweighted mean of within-sample proportions in
#'     field samples.}
#'   \item{\code{mean_prop_control}}{Informational only, does not drive the
#'     score (Session 151): unweighted mean of within-sample proportions in
#'     control samples.}
#'   \item{\code{field_rate}}{Depth-weighted detection rate in field samples
#'     (taxon reads / total field sequencing depth), before shrinkage.}
#'   \item{\code{control_rate}}{Depth-weighted detection rate in control
#'     samples, before shrinkage.}
#'   \item{\code{n_field_present}}{Number of field samples in which the taxon
#'     was detected. Informational only since Session 152 -- does not drive
#'     the shrinkage weight (see \code{n_reads_total}).}
#'   \item{\code{n_controls_present}}{Number of controls in which the taxon was
#'     detected. Informational only since Session 152.}
#'   \item{\code{n_controls_total}}{Total number of controls.}
#'   \item{\code{n_reads_total}}{Total reads for this taxon across field +
#'     control samples combined (\code{Session 152}). This, not sample count,
#'     is what the shrinkage weight (\code{prior_weight}) is measured
#'     against -- see \code{.compute_contaminant_scores()} for why.}
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
                             prior_weight     = 20,
                             verbose          = TRUE) {

  # --- Input validation ---
  if (!is.data.frame(df)) stop("'df' must be a data frame.", call. = FALSE)

  for (col in c(event_col, taxon_col, reads_col)) {
    if (!col %in% names(df))
      stop(sprintf("Column '%s' not found in df.", col), call. = FALSE)
  }

  if (!is.numeric(df[[reads_col]]))
    stop(sprintf("Column '%s' must be numeric.", reads_col), call. = FALSE)

  if (!is.numeric(prior_weight) || length(prior_weight) != 1L ||
      is.na(prior_weight) || prior_weight < 0)
    stop("'prior_weight' must be a single non-negative numeric value.", call. = FALSE)

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
    field_ids  = field_ids,
    prior_weight = prior_weight
  )

  # --- Apply thresholds to get risk levels ---
  # score = shrunk field rate / (shrunk field rate + shrunk control rate);
  # low score = probable contaminant = high risk
  scores$flag <- dplyr::case_when(
    scores$contaminant_score <= score_thresholds[1] ~ "high",
    scores$contaminant_score <= score_thresholds[2] ~ "moderate",
    TRUE ~ "low"
  )

  # --- Build reason strings ---
  # Reports the depth-weighted rates that actually drive contaminant_score
  # (Session 151), not the old unweighted mean_prop_field/mean_prop_control
  # (still returned, but purely informational -- see roxygen).
  scores$reason <- sprintf(
    "field rate %.5f, control rate %.5f (depth-weighted, shrunk by %d total read(s)), score %.3f; detected in %d field / %d/%d control sample(s)",
    scores$field_rate, scores$control_rate, scores$n_reads_total,
    scores$contaminant_score, scores$n_field_present,
    scores$n_controls_present, scores$n_controls_total
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
    field_rate         = scores$field_rate,
    control_rate       = scores$control_rate,
    n_field_present     = scores$n_field_present,
    n_controls_present = scores$n_controls_present,
    n_controls_total   = scores$n_controls_total,
    n_reads_total      = scores$n_reads_total,
    stringsAsFactors = FALSE
  )
  names(result) <- c(taxon_col, score_col, flag_col, reason_col,
                     "mean_prop_field", "mean_prop_control",
                     "field_rate", "control_rate",
                     "n_field_present", "n_controls_present", "n_controls_total",
                     "n_reads_total")

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
#' Internal helper. Computes within-sample proportions for each taxon, a
#' read-depth-weighted rate per group (field vs. control), then an Empirical
#' Bayes-shrunk score comparing them.
#'
#' @section Depth-weighting and shrinkage (soundness-review item 15):
#' The naive version of this comparison -- an unweighted mean of each
#' taxon's per-sample proportions -- lets a single shallow, noisy sample
#' dominate the mean as much as a deep, well-supported one, and gives a hard
#' 0.0/1.0 score to any taxon absent from one side regardless of how little
#' evidence (how few samples) that absence is based on. Two independent
#' fixes, composed:
#' \enumerate{
#'   \item \strong{Depth-weighting.} `field_rate`/`control_rate` are computed
#'     as `sum(taxon reads in group) / sum(total reads across samples in
#'     that group)` -- mathematically identical to a reads-weighted mean of
#'     per-sample proportions, so a proportion from 500,000 reads now counts
#'     far more than one from 50. Each rate is normalized by its OWN group's
#'     total depth (not a shared pool), which keeps the comparison
#'     scale-free even when field and control pools have very different
#'     total sequencing depth -- the common real case of many field samples
#'     against a couple of small blanks.
#'   \item \strong{Shrinkage.} The raw ratio `field_rate / (field_rate +
#'     control_rate)` is shrunk toward 0.5 (maximally uncertain) with weight
#'     `w = n_reads_total / (n_reads_total + prior_weight)`, where
#'     `n_reads_total` is the taxon's total READ count (summed across both
#'     groups) -- the same Empirical Bayes form used throughout this
#'     ecosystem (e.g. `TaxaLikely::train_likelihood_model()`'s per-species
#'     shrinkage), but measured in reads, not samples (Session 152 -- see
#'     below). A taxon with little total read support, however lopsided its
#'     raw ratio, no longer gets an overconfident 0 or 1; a taxon with
#'     substantial read support keeps close to its raw ratio regardless of
#'     how few samples it came from.
#' }
#' Shrinkage is applied to the FINAL ratio, not to `field_rate`/
#' `control_rate` individually toward some shared reference rate -- an
#' earlier version of this fix tried shrinking each rate toward the taxon's
#' own pooled (field+control) rate, which let a taxon's own field read
#' volume leak into its control-side prior and systematically understated
#' genuinely clean taxa's scores whenever field depth dominated control
#' depth (re-introducing the exact group-depth-imbalance problem
#' depth-weighting exists to avoid). `mean_prop_field`/`mean_prop_control`
#' (the old, unweighted per-sample means) are still returned as
#' informational diagnostics, but no longer feed `contaminant_score`.
#'
#' @section Reads, not samples, as the shrinkage denominator (Session 152):
#' Session 151 shrunk by SAMPLE count (`n_field_present + n_controls_present`).
#' Real PtConception data (both 12S and 18S) showed this conflates two very
#' different evidence strengths: a taxon detected via 2 reads in one sample
#' and a taxon detected via 500,000 reads in one sample were both treated as
#' "n_present = 1" and shrunk identically -- capping BOTH at the same
#' distance from 0.5 regardless of how much real evidence either one
#' actually carries. With the Session 151 default (`prior_weight = 2`,
#' sample-count shrinkage), no taxon detected in 1-8 total samples could
#' ever reach the `"low"` risk tier even with overwhelming, unambiguous
#' read support -- and the median real taxon in both PtConception datasets
#' is detected in exactly 1 field sample, so this capped the vast majority
#' of legitimately clean detections at `"moderate"` (12S: 97% of taxa,
#' 18S: 88%) purely as an artifact of sample count, not evidence quality.
#'
#' Read count fixes this directly and needs no change to the 0.5 shrink
#' target (already correct in depth-normalized rate space, per the
#' Depth-weighting section above). A read-FRACTION-based alternative (shrink
#' toward the study's own control:field depth ratio rather than 0.5) was
#' also tried and rejected: it requires anchoring to that ratio explicitly
#' and does not transfer across studies with very different ratios --
#' verified directly against both real datasets, where it either missed or
#' downgraded taxa the sample-count-based approach had correctly flagged
#' `"high"`.
#'
#' Empirically validated against real PtConception 12S and 18S data at
#' `prior_weight` (now read-equivalent units) of 20, 50, 100, and 500: the
#' known `"high"`-risk taxa (stable across the pre-151 and Session-151
#' formulas) are recovered with 100% sensitivity and zero false positives at
#' every value tested, on both datasets, while a much larger fraction of
#' well-supported clean detections correctly reach `"low"` instead of being
#' capped at `"moderate"`. Default chosen: `prior_weight = 20` -- recovers
#' the most `"low"`-tier informativeness of the values tested while still
#' correctly keeping thin (~20-30 total read) single-detections at
#' `"moderate"`, not `"low"` (a genuinely well-supported single-sample
#' detection with tens of thousands of reads does reach `"low"`, as it
#' should).
#'
#' @param df Data frame in long format.
#' @param event_col,taxon_col,reads_col Column name strings.
#' @param control_ids,field_ids Character vectors of sample IDs.
#' @param prior_weight Numeric. Equivalent read count for shrinking the final
#'   ratio toward 0.5 (Session 152 -- previously an equivalent sample count).
#'   Higher values pull harder toward 0.5 for taxa with little total read
#'   support (field + control combined).
#'
#' @return Data frame with one row per taxon and columns: \code{taxon},
#'   \code{mean_prop_field}, \code{mean_prop_control}, \code{field_rate},
#'   \code{control_rate}, \code{n_field_present}, \code{n_controls_present},
#'   \code{n_controls_total}, \code{n_reads_total}, \code{contaminant_score}.
#'
#' @noRd
.compute_contaminant_scores <- function(df, event_col, taxon_col, reads_col,
                                        control_ids, field_ids,
                                        prior_weight = 20) {

  # Standardise column names for internal use
  work <- data.frame(
    sample   = df[[event_col]],
    taxon    = df[[taxon_col]],
    n_reads  = df[[reads_col]],
    stringsAsFactors = FALSE
  )

  # Remove zero-read rows

  work <- work[work$n_reads > 0, , drop = FALSE]

  # Within-sample proportions (still computed -- feeds mean_prop_field/
  # mean_prop_control, the informational unweighted-mean diagnostics)
  sample_totals <- stats::aggregate(n_reads ~ sample, data = work, FUN = sum)
  names(sample_totals)[2] <- "total_reads"
  work <- merge(work, sample_totals, by = "sample")
  work$prop <- work$n_reads / work$total_reads

  # Tag control vs field
  work$is_control <- work$sample %in% control_ids

  # Group-level sequencing depth (sum of each sample's own total reads,
  # across ALL taxa) -- the denominator for depth-weighted rates. Computed
  # once, not per taxon: constant across taxa within one call.
  field_depth   <- sum(sample_totals$total_reads[sample_totals$sample %in% field_ids])
  control_depth <- sum(sample_totals$total_reads[sample_totals$sample %in% control_ids])

  # Get all unique taxa
  all_taxa <- unique(work$taxon)
  n_controls_total <- length(control_ids)

  results <- lapply(all_taxa, function(tx) {
    tx_rows <- work[work$taxon == tx, , drop = FALSE]
    field_rows <- tx_rows[!tx_rows$is_control, , drop = FALSE]
    control_rows <- tx_rows[tx_rows$is_control, , drop = FALSE]

    # Informational only (Session 151): unweighted mean of per-sample
    # proportions -- no longer feeds contaminant_score.
    mean_prop_field <- if (nrow(field_rows) > 0L) mean(field_rows$prop) else 0
    mean_prop_control <- if (nrow(control_rows) > 0L) mean(control_rows$prop) else 0

    n_field_present    <- length(unique(field_rows$sample))
    n_controls_present <- length(unique(control_rows$sample))

    # Depth-weighted rate per group: taxon reads / total sequencing depth
    # of that group. Equivalent to a reads-weighted mean of per-sample
    # proportions -- normalizing by each group's OWN total depth (not a
    # shared pool) keeps the comparison scale-free even when field and
    # control pools have very different total sequencing depth (the common
    # real case: many field samples, few small blanks).
    taxon_field_reads   <- sum(field_rows$n_reads)
    taxon_control_reads <- sum(control_rows$n_reads)
    field_rate   <- if (field_depth   > 0) taxon_field_reads   / field_depth   else 0
    control_rate <- if (control_depth > 0) taxon_control_reads / control_depth else 0

    # Raw (un-shrunk) ratio, same structural form as the pre-Session-151
    # formula, just with depth-weighted rates in place of unweighted
    # per-sample-proportion means.
    rate_sum  <- field_rate + control_rate
    raw_score <- if (rate_sum > 0) field_rate / rate_sum else 0.5

    # Empirical Bayes shrinkage of the FINAL ratio toward 0.5 (maximally
    # uncertain), weighted by total READ count (n_reads_total summed across
    # both groups) -- w = n_reads_total / (n_reads_total + prior_weight).
    # Session 152: this was sample count (n_field_present + n_controls_present)
    # through Session 151, which conflated a 2-read detection with a
    # 500,000-read detection whenever both happened to come from a single
    # sample -- see this function's "Reads, not samples" roxygen section for
    # the real-data evidence this was wrong. Shrinking the ratio itself,
    # rather than shrinking field_rate/control_rate separately toward some
    # shared reference rate, avoids a subtle bug: an early version of this
    # fix shrunk each rate toward their taxon-specific pooled average, which
    # let a taxon's own (usually much larger) field read volume leak into
    # its control-side prior, systematically understating genuinely clean
    # taxa's scores whenever field depth dominated control depth -- exactly
    # the group-depth-imbalance problem depth-weighting was supposed to
    # avoid. Shrinking the ratio by read count instead keeps the two groups'
    # magnitudes fully independent, same as the sample-count version did.
    n_reads_total <- taxon_field_reads + taxon_control_reads
    w <- n_reads_total / (n_reads_total + prior_weight)
    score <- w * raw_score + (1 - w) * 0.5

    data.frame(
      taxon              = tx,
      mean_prop_field    = mean_prop_field,
      mean_prop_control  = mean_prop_control,
      field_rate         = field_rate,
      control_rate       = control_rate,
      n_field_present    = n_field_present,
      n_controls_present = n_controls_present,
      n_controls_total   = n_controls_total,
      n_reads_total      = n_reads_total,
      contaminant_score  = score,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, results)
}

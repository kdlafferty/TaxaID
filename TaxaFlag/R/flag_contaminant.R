utils::globalVariables(c(
  "n_reads", "total_reads", "prop", "mean_prop",
  "is_control", "n_controls_present", "n_controls_total",
  "mean_prop_field", "mean_prop_control",
  "n_reads_total", "contaminant_score"
))

#' Flag Potential Contaminants by Comparison to Control Samples
#'
#' Compares detection proportions between field samples and control samples
#' (negative controls or positive controls) to identify taxa that may be
#' contaminants. Supports any labelled control samples (extraction, PCR, or
#' field blanks; for non-sequence data, a blank photo/recording or a
#' negative-control site) plus positive controls.
#'
#' The algorithm computes a depth-weighted detection rate per taxon in
#' field samples vs. controls, then an Empirical Bayes-shrunk score
#' comparing them (\code{.compute_contaminant_scores()}'s own internal
#' documentation has the full mechanism and the real-data motivation for
#' it). Taxa with a higher rate in controls than field samples receive low
#' scores (likely contaminants); taxa strongly favoring field samples
#' receive scores approaching, but not reaching, 1.0 -- shrinkage means no
#' taxon gets an absolute 0 or 1 score purely from having little total read
#' support (shrinkage strength is measured in reads, not samples; see
#' \code{.compute_contaminant_scores()}'s documentation).
#'
#' \strong{This score is a ranked screening statistic, not a calibrated
#' probability}: no generative model of contamination is fit, and the score
#' is not validated against known-true contamination status. Use it to rank
#' taxa for review against \code{score_thresholds}, not as a literal
#' posterior probability.
#'
#' For positive controls, the interpretation is inverted: taxa from the
#' positive control appearing in field samples indicate cross-contamination.
#'
#' @section Unified validity schema:
#' Output column NAMES are fixed (\code{observation_validity}/
#' \code{validity_flag}/\code{validity_reason}) rather than parameterized by
#' \code{contaminant_type} -- every TaxaFlag flag_*() mechanism (see also
#' \code{\link{flag_handler}}) shares this one schema, matching the "one
#' column, type-qualified values" pattern \code{\link{add_posthoc_assessment}}
#' uses. The \code{contaminant_type} string appears in \code{validity_flag}'s
#' VALUES (\code{"invalid_{contaminant_type}"}/\code{"questionable_
#' {contaminant_type}"}) instead of in a column name.
#' \code{report_flags()} auto-detects this schema by inspecting
#' \code{validity_flag}'s values, not just the column's presence, since the
#' column name alone does not identify which check produced it.
#'
#' @param input_df Data frame in long format with at minimum columns for sample
#'   identification, taxon identification, and count data (e.g. read counts,
#'   detection counts).
#' @param event_col Character. Column name identifying collection events
#'   (e.g., individual filters, bottles, or deployments). Default
#'   \code{"event_id"}.
#' @param taxon_col Character. Column name identifying taxa (species, ESV,
#'   ASV, etc.). Default \code{"taxon_name"}.
#' @param count_col Character. Column name with integer count data. Default
#'   \code{"count"}.
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
#'   being assessed, embedded in \code{validity_flag}'s values (e.g.
#'   \code{"invalid_lab_contaminant"}) -- see \code{@return} below. Does NOT
#'   change output column NAMES (see Details); those are fixed
#'   (\code{observation_validity}/\code{validity_flag}/
#'   \code{validity_reason}) so every TaxaFlag flag_*() mechanism shares one
#'   schema. Common values: \code{"lab_contaminant"},
#'   \code{"field_contaminant"}, \code{"positive_control"}. Default
#'   \code{"lab_contaminant"}.
#' @section DO NOT FILTER ON validity_flag != "valid":
#' This was always a fragile idiom and \code{require_control_evidence = TRUE}
#' makes it catastrophic. Under the gate the honest-unknown state
#' \code{"no_control_evidence"} is not \code{"valid"}, and it is normally the
#' overwhelming majority: on a real 12S run it covered 16,695 of 16,826 ESVs
#' (99.2%) and on COI 32,162 of 34,899 (92.2%). A downstream
#' \code{validity_flag != "valid"} filter would therefore delete nearly the whole
#' dataset, where the same filter without the gate deletes a merely
#' implausible 73%.
#'
#' \code{"not_control_enriched"} and \code{"single_site_enriched"} are also not
#' \code{"valid"}, and they are the states that exist precisely to say DO NOT
#' REMOVE THIS. Neither is \code{"insufficient_control_evidence"}, which means the
#' question was not answerable on the evidence available.
#'
#' The removal predicate is the \code{invalid_} prefix, never the negation of
#' \code{"valid"}:
#' \preformatted{
#'   # correct
#'   to_remove <- startsWith(flagged$validity_flag, "invalid_")
#'   # also correct, if you want one named type
#'   to_remove <- flagged$validity_flag == "invalid_lab_contaminant"
#'   # WRONG, and much worse under require_control_evidence = TRUE
#'   to_remove <- flagged$validity_flag != "valid"
#' }
#' Anything filtering on the negation of \code{"valid"} sweeps the whole middle
#' tier in whether or not that tier is ever printed.
#'
#' @section Evidence-gated states (require_control_evidence = TRUE):
#' \code{validity_flag} takes these values instead of the score bands:
#' \itemize{
#'   \item \code{"no_control_evidence"} -- never detected in any control, so no
#'     assessment is possible. An honest unknown, and expected to be the large
#'     majority: on a real 12S run 13,554 of 13,597 taxa were in this state.
#'   \item \code{"invalid_{contaminant_type}"} -- control rate above sample rate.
#'     The name is kept so existing downstream filters on \code{invalid_*} keep
#'     working.
#'   \item \code{"not_control_enriched"} -- present in a control but at or below
#'     its sample rate. Signal leaking sample -> control, the OPPOSITE direction of
#'     travel. Must not be filtered; this is the state the score-band design could
#'     not express, and it is what made abundant local taxa look like contaminants.
#'     Named for what was measured rather than for a mechanism: a rate
#'     comparison alone cannot establish a direction of travel, so the label
#'     states only that the taxon is not enriched in controls.
#'   \item \code{"insufficient_control_evidence"} -- seen in at least one control
#'     but fewer than \code{min_control_obs}. Not assessable, because a rate built
#'     on one observation is not comparable to a rate built on hundreds.
#'   \item \code{"single_site_enriched"} -- control-enriched, but confined to one
#'     site whose samples also carry it. Local, not a systemic source. Distinct
#'     from \code{"not_control_enriched"}: this taxon IS enriched in controls, so
#'     the two labels make opposite claims and must not share a name.
#'   \item \code{"questionable_{contaminant_type}"} -- present in a control with
#'     rates that do not separate.
#' }
#' With \code{site_col}, three columns are added --
#' \code{site_breadth_control}, \code{site_breadth_sample},
#' \code{control_sites_shared} -- and a control-enriched taxon confined to ONE
#' site whose samples also carry it is downgraded to
#' \code{"single_site_enriched"}.
#'
#' @param require_control_evidence Logical. When TRUE, an ESV that was never
#'   detected in ANY control is labelled \code{"no_control_evidence"} instead of
#'   being scored, and ESVs that ARE seen in a control are split by DIRECTION.
#'   Default \code{FALSE}, which emits a warning when it bites (see below);
#'   \code{TRUE} is the defensible setting for new work.
#'
#'   Why: the shrunken score is driven by READ DEPTH when control detections are
#'   rare, so it assigns a contamination verdict to ESVs with no contamination
#'   evidence at all. Measured on a real 12S run: of 13,597 ESVs only 43 were ever
#'   detected in a single control, yet 10,300 were labelled
#'   \code{questionable_lab_contaminant} -- the whole middle tier had ZERO blank
#'   evidence, and the rate was 75-81% in every marker and workflow checked
#'   because it reflects the read-depth distribution rather than contamination.
#'
#'   DIRECTION IS THE POINT. Contamination flows control -> sample; CARRYOVER flows
#'   sample -> control, which is what happens when a blank picks up a little of an
#'   abundant local taxon. The first must be filtered and the second must not, and
#'   a symmetric score cannot tell them apart.
#' @param site_col Character or NULL. Column giving each event's site. When
#'   supplied, site breadth is computed per taxon and used as a DISCRIMINANT, not
#'   merely as extra power: a systemic contaminant (reagent, water supply) appears
#'   in controls at MANY sites regardless of which sites' samples carry it, whereas
#'   a local source appears in controls at the ONE site whose samples are full of it.
#'   This is what dissolves the pooling-versus-pairing dilemma -- pooling controls
#'   buys power but lets one trip's contamination speak for another's, while
#'   pairing by event buys specificity at the cost of power (on real data,
#'   event-paired controls emptied the invalid tier completely: 0 ESVs, against 43
#'   and 323 in pooled runs). Using the cross-site PATTERN keeps both.
#' @param min_sites_systemic Integer. How many distinct sites must show a control
#'   detection before it counts as systemic rather than local. Default 2. Only
#'   used when \code{site_col} is supplied.
#' @param min_control_obs Integer. Minimum number of distinct controls a taxon must
#'   appear in before the rate comparison is allowed to condemn it. Default 2.
#'   Only used when \code{require_control_evidence = TRUE}.
#'
#'   This exists because the direction test is a BARE RATE INEQUALITY, and rates
#'   built on one observation are not comparable to rates built on hundreds: with
#'   91 controls against 1,052 samples, one stray read in one blank scores
#'   1/91 = 0.011 and outvotes two genuine detections at 2/1052 = 0.0019. On real
#'   data 55-63 per cent of everything the gate condemned rested on a single
#'   control observation, and the tail contained genuine organisms. Setting this to
#'   1 restores the unfloored behaviour; a proper one-sided significance test with
#'   a multiple-testing correction would be the principled replacement and is NOT
#'   implemented.
#' @param score_thresholds Numeric vector of length 2. Thresholds for
#'   converting \code{observation_validity} to \code{validity_flag}. Values
#'   at or below the first are \code{"invalid_{contaminant_type}"} (probable
#'   contaminant); at or below the second, \code{"questionable_{contaminant_type}"};
#'   higher values are \code{"valid"} (likely a genuine detection). Default
#'   \code{c(0.5, 0.9)}.
#' @param prior_weight Numeric (default \code{20}). Empirical Bayes shrinkage
#'   strength, in units of "equivalent reads" (see
#'   \code{.compute_contaminant_scores()}'s own documentation for why reads,
#'   not samples). Controls how strongly
#'   the final field-vs-control ratio is pulled toward 0.5 (maximally
#'   uncertain) when a taxon has little total read support overall. Higher
#'   values shrink harder (more conservative, less willing to call a
#'   thinly-supported taxon confidently clean or contaminated); \code{0}
#'   disables shrinkage entirely, restoring the raw depth-weighted ratio.
#' @param verbose Logical. Print summary messages. Default \code{TRUE}.
#'
#' @return A data frame with one row per taxon, sorted by
#'   \code{observation_validity} (most likely contaminants first). Columns:
#' \describe{
#'   \item{\code{{taxon_col}}}{Taxon identifier (from input).}
#'   \item{\code{observation_validity}}{Numeric 0--1. Empirical
#'     Bayes-shrunk ratio of the depth-weighted field rate to the total
#'     (field + control) rate. Higher = more likely a real, genuine
#'     detection; lower = more likely a contaminant. Approaches, but does
#'     not reach, 1.0 for taxa absent from controls -- see Details. A ranked
#'     screening statistic, not a calibrated probability.}
#'   \item{\code{validity_flag}}{Character. \code{"invalid_{contaminant_type}"}
#'     (probable contaminant), \code{"questionable_{contaminant_type}"}
#'     (uncertain), or \code{"valid"} (likely genuine detection) -- see
#'     \code{@section Unified validity schema} above. Fixed column name
#'     across every TaxaFlag flag_*() mechanism; the specific type of concern
#'     lives in the value, not the column name.}
#'   \item{\code{validity_reason}}{Character. Plain-English
#'     explanation including depth-weighted rates and control detection counts.}
#'   \item{\code{mean_prop_field}}{Informational only, does not drive the
#'     score: unweighted mean of within-sample proportions in field samples.}
#'   \item{\code{mean_prop_control}}{Informational only, does not drive the
#'     score: unweighted mean of within-sample proportions in control
#'     samples.}
#'   \item{\code{field_rate}}{Depth-weighted detection rate in field samples
#'     (taxon reads / total field sequencing depth), before shrinkage.}
#'   \item{\code{control_rate}}{Depth-weighted detection rate in control
#'     samples, before shrinkage.}
#'   \item{\code{n_field_present}}{Number of field samples in which the taxon
#'     was detected. Informational only -- does not drive the shrinkage
#'     weight (see \code{n_reads_total}).}
#'   \item{\code{n_controls_present}}{Number of controls in which the taxon was
#'     detected. Informational only.}
#'   \item{\code{n_controls_total}}{Total number of controls.}
#'   \item{\code{n_reads_total}}{Total reads for this taxon across field +
#'     control samples combined. This, not sample count, is what the
#'     shrinkage weight (\code{prior_weight}) is measured against -- see
#'     \code{.compute_contaminant_scores()} for why.}
#' }
#'
#' @seealso \code{\link{flag_handler}}, \code{\link{review_assignments}}
#'
#' @examples
#' reads_long <- data.frame(
#'   event_id = c(
#'     "Palmyra01", "Palmyra01", "Palmyra02", "Palmyra02",
#'     "Palmyra30", "Palmyra30"
#'   ),
#'   taxon_name = c(
#'     "Kyphosus vaigiensis", "Homo sapiens",
#'     "Kyphosus vaigiensis", "Homo sapiens",
#'     "Kyphosus vaigiensis", "Homo sapiens"
#'   ),
#'   count = c(48000, 12, 51000, 8, 5, 4200)
#' )
#'
#' # Identify extraction control columns, flag contaminants
#' flagged <- flag_contaminant(
#'   input_df         = reads_long,
#'   control_samples  = "Palmyra30",
#'   contaminant_type = "lab_contaminant"
#' )
#'
#' \dontrun{
#' # Using sample_type column instead
#' flagged <- flag_contaminant(
#'   input_df = reads_long,
#'   sample_type_col = "sample_type",
#'   control_types = c("extraction_blank", "pcr_blank"),
#'   contaminant_type = "lab_contaminant"
#' )
#'
#' # Flag positive control leakage
#' flagged <- flag_contaminant(
#'   input_df = reads_long,
#'   control_samples = c("Palmyra32", "Palmyra64"),
#'   exclude_samples = c("Palmyra30", "Palmyra31", "Palmyra62", "Palmyra63"),
#'   contaminant_type = "positive_control"
#' )
#' }
#'
#' \dontrun{
#' # Non-sequencing example: camera-trap image detection counts, with an
#' # unbaited station standing in for a negative control
#' image_counts <- data.frame(
#'   event_id = c(
#'     "StationA", "StationA", "StationB", "StationB",
#'     "UnbaitedStation", "UnbaitedStation"
#'   ),
#'   taxon_name = c(
#'     "Odocoileus hemionus", "Procyon lotor",
#'     "Odocoileus hemionus", "Procyon lotor",
#'     "Odocoileus hemionus", "Procyon lotor"
#'   ),
#'   count = c(340, 12, 298, 9, 1, 47)
#' )
#' flagged_images <- flag_contaminant(
#'   input_df         = image_counts,
#'   control_samples  = "UnbaitedStation",
#'   contaminant_type = "lab_contaminant"
#' )
#' }
#'
#' @export
flag_contaminant <- function(input_df,
                             event_col = "event_id",
                             taxon_col = "taxon_name",
                             count_col = "count",
                             control_samples = NULL,
                             sample_type_col = NULL,
                             control_types = NULL,
                             exclude_samples = NULL,
                             contaminant_type = "lab_contaminant",
                             score_thresholds = c(0.5, 0.9),
                             prior_weight = 20,
                             require_control_evidence = FALSE,
                             site_col = NULL,
                             min_sites_systemic = 2L,
                             min_control_obs = 2L,
                             verbose = TRUE) {
  # --- Input validation ---
  if (!is.data.frame(input_df)) stop("'input_df' must be a data frame.", call. = FALSE)

  for (col in c(event_col, taxon_col, count_col)) {
    if (!col %in% names(input_df)) {
      stop(sprintf("Column '%s' not found in input_df.", col), call. = FALSE)
    }
  }

  if (!is.numeric(input_df[[count_col]])) {
    stop(sprintf("Column '%s' must be numeric.", count_col), call. = FALSE)
  }

  if (!is.numeric(prior_weight) || length(prior_weight) != 1L ||
    is.na(prior_weight) || prior_weight < 0) {
    stop("'prior_weight' must be a single non-negative numeric value.", call. = FALSE)
  }

  if (is.null(control_samples) && is.null(sample_type_col)) {
    stop("Supply either 'control_samples' or 'sample_type_col' to identify controls.",
      call. = FALSE
    )
  }

  if (!is.null(control_samples) && !is.null(sample_type_col)) {
    stop("Supply 'control_samples' OR 'sample_type_col', not both.", call. = FALSE)
  }

  if (!is.null(sample_type_col)) {
    if (!sample_type_col %in% names(input_df)) {
      stop(sprintf("Column '%s' not found in input_df.", sample_type_col), call. = FALSE)
    }
    if (is.null(control_types) || length(control_types) == 0L) {
      stop("'control_types' required when using 'sample_type_col'.", call. = FALSE)
    }
  }

  if (!is.null(site_col) && !site_col %in% names(input_df)) {
    stop(sprintf("Column '%s' not found in input_df.", site_col), call. = FALSE)
  }
  if (!is.numeric(min_control_obs) || min_control_obs < 1) {
    stop("'min_control_obs' must be an integer >= 1.", call. = FALSE)
  }
  if (!is.numeric(min_sites_systemic) || min_sites_systemic < 1) {
    stop("'min_sites_systemic' must be an integer >= 1.", call. = FALSE)
  }
  if (!is.numeric(score_thresholds) || length(score_thresholds) != 2L) {
    stop("'score_thresholds' must be a numeric vector of length 2.", call. = FALSE)
  }

  if (!is.character(contaminant_type) || length(contaminant_type) != 1L) {
    stop("'contaminant_type' must be a single character string.", call. = FALSE)
  }

  # --- Resolve control vs field samples ---
  all_samples <- unique(input_df[[event_col]])

  # Exclude samples first

  if (!is.null(exclude_samples)) {
    input_df <- input_df[!input_df[[event_col]] %in% exclude_samples, , drop = FALSE]
    all_samples <- setdiff(all_samples, exclude_samples)
  }

  # Identify controls
  if (!is.null(control_samples)) {
    control_ids <- intersect(control_samples, all_samples)
    if (length(control_ids) == 0L) {
      stop("None of 'control_samples' found in input_df after exclusions.", call. = FALSE)
    }
  } else {
    control_ids <- unique(input_df[[event_col]][input_df[[sample_type_col]] %in% control_types])
    if (length(control_ids) == 0L) {
      stop(
        sprintf(
          "No samples match control_types '%s' in column '%s'.",
          paste(control_types, collapse = "', '"), sample_type_col
        ),
        call. = FALSE
      )
    }
  }

  field_ids <- setdiff(all_samples, control_ids)
  if (length(field_ids) == 0L) {
    stop("No field samples remaining after identifying controls and exclusions.",
      call. = FALSE
    )
  }

  if (verbose) {
    message(sprintf(
      "flag_contaminant (%s): %d control(s), %d field sample(s), %d excluded.",
      contaminant_type, length(control_ids), length(field_ids),
      length(if (is.null(exclude_samples)) character(0) else exclude_samples)
    ))
  }

  # --- Compute scores ---
  scores <- .compute_contaminant_scores(
    input_df = input_df,
    event_col = event_col,
    taxon_col = taxon_col,
    count_col = count_col,
    control_ids = control_ids,
    field_ids = field_ids,
    prior_weight = prior_weight
  )

  # --- Apply thresholds to get validity levels ---
  # score = shrunk field rate / (shrunk field rate + shrunk control rate);
  # low score = probable contaminant = "invalid_{contaminant_type}". Type
  # qualifier embedded in the VALUE, not the column name -- see @section
  # Unified validity schema.
  invalid_label <- paste0("invalid_", contaminant_type)
  questionable_label <- paste0("questionable_", contaminant_type)
  scores$flag <- dplyr::case_when(
    scores$contaminant_score <= score_thresholds[1] ~ invalid_label,
    scores$contaminant_score <= score_thresholds[2] ~ questionable_label,
    TRUE ~ "valid"
  )

  # --- Site breadth as a DISCRIMINANT (opt-in via site_col) ------------------
  if (!is.null(site_col)) {
    .sb <- unique(data.frame(
      taxon = as.character(input_df[[taxon_col]]),
      site  = as.character(input_df[[site_col]]),
      is_ctl = input_df[[event_col]] %in% control_ids,
      stringsAsFactors = FALSE))
    .ctl_sites <- unique(.sb[.sb$is_ctl, c("taxon", "site")])
    .sam_sites <- unique(.sb[!.sb$is_ctl, c("taxon", "site")])
    .n_ctl <- table(.ctl_sites$taxon); .n_sam <- table(.sam_sites$taxon)
    # how many of a taxon's CONTROL sites are also sites where SAMPLES have it:
    # high concordance means the control detections track the samples, i.e. the
    # signature of a LOCAL source rather than of a systemic one
    .both <- merge(.ctl_sites, .sam_sites, by = c("taxon", "site"))
    .n_both <- table(.both$taxon)
    scores$site_breadth_control <- as.integer(.n_ctl[scores$taxon]); scores$site_breadth_control[is.na(scores$site_breadth_control)] <- 0L
    scores$site_breadth_sample  <- as.integer(.n_sam[scores$taxon]); scores$site_breadth_sample[is.na(scores$site_breadth_sample)]  <- 0L
    scores$control_sites_shared <- as.integer(.n_both[scores$taxon]); scores$control_sites_shared[is.na(scores$control_sites_shared)] <- 0L
  }

  # --- Evidence gate, then direction (opt-in) --------------------------------
  if (require_control_evidence) {
    .seen   <- scores$n_controls_present > 0
    # EVIDENCE FLOOR. The direction test below is a bare rate inequality, and
    # rates built on ONE control observation are not comparable to rates built on
    # hundreds of samples: with 91 controls against 1,052 field samples, a single
    # stray read in a single blank gives 1/91 = 0.011 and beats two genuine
    # detections at 2/1052 = 0.0019. Measured on the California Intertidal
    # archive, 55-63 per cent of everything the gate condemned rested on exactly
    # one control observation, and the tail included real organisms -- a tidepool
    # sculpin, two red macroalgae, a sand dollar. Taxa below the floor are
    # reported as untested rather than condemned on one observation.
    .thin   <- .seen & scores$n_controls_present < min_control_obs
    .enrich <- scores$control_rate > scores$field_rate
    scores$flag <- ifelse(
      !.seen, "no_control_evidence",
      ifelse(.thin, "insufficient_control_evidence",
        ifelse(.enrich, invalid_label,
               ifelse(scores$control_rate < scores$field_rate,
                      "not_control_enriched", questionable_label))))
    # Site-breadth refinement: a control-enriched taxon seen at only ONE site whose samples
    # also carry it is LOCAL, not a systemic source. Downgrading here is the whole
    # value of having more than one site with controls.
    #
    # This gets its own label rather than sharing one with the rate-based state
    # above. The two mean opposite things about enrichment -- "not enriched in
    # controls" versus "enriched, but at a single site" -- so one name covering
    # both would be false for whichever case it was not written for.
    if (!is.null(site_col)) {
      .local <- scores$flag == invalid_label &
                scores$site_breadth_control < min_sites_systemic &
                scores$control_sites_shared >= scores$site_breadth_control
      scores$flag[.local] <- "single_site_enriched"
    }
  }

  # Warn only where this actually bites, and report the real count -- a blanket
  # warning on every call is noise, and noise gets switched off.
  if (!require_control_evidence) {
    .no_ev_flagged <- sum(scores$n_controls_present == 0 & scores$flag != "valid")
    if (.no_ev_flagged > 0)
      warning(sprintf(paste0("flag_contaminant: %d of %d taxa received a ",
        "contamination verdict WITHOUT EVER BEING DETECTED IN A CONTROL -- they are ",
        "scored on read-depth shrinkage alone. On a real 12S run this labelled ",
        "10,300 of 13,597 taxa questionable when only 43 had ever appeared in a ",
        "control. Set require_control_evidence = TRUE to report those as ",
        "'no_control_evidence' instead."), .no_ev_flagged, nrow(scores)), call. = FALSE)
  }

  # --- Build reason strings ---
  # Reports the depth-weighted rates that actually drive observation_validity,
  # not the unweighted mean_prop_field/mean_prop_control (still returned, but
  # purely informational -- see roxygen).
  scores$reason <- sprintf(
    "field rate %.5f, control rate %.5f (depth-weighted, shrunk by %d total read(s)), score %.3f; detected in %d field / %d/%d control sample(s)",
    scores$field_rate, scores$control_rate, scores$n_reads_total,
    scores$contaminant_score, scores$n_field_present,
    scores$n_controls_present, scores$n_controls_total
  )

  # --- Build per-taxon result ---
  # Fixed column names -- see @section Unified validity schema.
  # Selects straight out of `scores` (dropping only its internal `contaminant_score`/
  # `flag`/`reason` working names) rather than rebuilding every value by hand --
  # `.compute_contaminant_scores()`'s own output columns stay the single source
  # of truth. Column NAMES still can't be supplied as literal data.frame()
  # arguments here (taxon_col/score_col/etc. are runtime strings, not syntactic
  # names), so a select-then-rename via names<- is the direct way to do this in
  # base R -- stats::setNames() would be equivalent, not simpler.
  .extra <- intersect(c("site_breadth_control", "site_breadth_sample",
                        "control_sites_shared"), names(scores))
  result <- scores[, c(
    "taxon", "contaminant_score", "flag", "reason",
    "mean_prop_field", "mean_prop_control",
    "field_rate", "control_rate",
    "n_field_present", "n_controls_present", "n_controls_total",
    "n_reads_total", .extra
  ), drop = FALSE]
  flag_col <- "validity_flag"
  score_col <- "observation_validity"
  reason_col <- "validity_reason"
  names(result) <- c(
    taxon_col, score_col, flag_col, reason_col,
    "mean_prop_field", "mean_prop_control",
    "field_rate", "control_rate",
    "n_field_present", "n_controls_present", "n_controls_total",
    "n_reads_total", .extra
  )

  # Sort by score (most likely contaminants first)
  result <- result[order(result[[score_col]]), , drop = FALSE]
  rownames(result) <- NULL

  if (verbose) {
    n_invalid <- sum(result[[flag_col]] == invalid_label)
    n_questionable <- sum(result[[flag_col]] == questionable_label)
    n_valid <- sum(result[[flag_col]] == "valid")
    message(sprintf(
      "  %d taxa scored: %d invalid (%s), %d questionable, %d valid.",
      nrow(result), n_invalid, contaminant_type, n_questionable, n_valid
    ))
  }

  result
}


#' Compute Contaminant Scores from Read Proportions
#'
#' Internal helper. Computes within-sample proportions for each taxon, a
#' read-depth-weighted rate per group (field vs. control), then an Empirical
#' Bayes-shrunk score comparing them.
#'
#' @section Depth-weighting and shrinkage:
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
#'     shrinkage), but measured in reads, not samples (see below). A taxon
#'     with little total read support, however lopsided its
#'     raw ratio, no longer gets an overconfident 0 or 1; a taxon with
#'     substantial read support keeps close to its raw ratio regardless of
#'     how few samples it came from.
#' }
#' Shrinkage is applied to the FINAL ratio, not to `field_rate`/
#' `control_rate` individually toward some shared reference rate: shrinking
#' each rate toward the taxon's own pooled (field+control) rate would let a
#' taxon's own field read volume leak into its control-side prior and would
#' systematically understate genuinely clean taxa's scores whenever field
#' depth dominated control depth (re-introducing the exact
#' group-depth-imbalance problem depth-weighting exists to avoid).
#' `mean_prop_field`/`mean_prop_control` (the unweighted per-sample means)
#' are still returned as informational diagnostics, but do not feed
#' `contaminant_score`.
#'
#' @section Reads, not samples, as the shrinkage denominator:
#' Shrinking by SAMPLE count (`n_field_present + n_controls_present`) instead
#' of read count would conflate two very different evidence strengths: a
#' taxon detected via 2 reads in one sample and a taxon detected via 500,000
#' reads in one sample are both `n_present = 1` and would be shrunk
#' identically -- capping BOTH at the same distance from 0.5 regardless of
#' how much real evidence either one actually carries. Real PtConception
#' data (both 12S and 18S) confirms this: at `prior_weight = 2` (the
#' sample-count-shrinkage equivalent), no taxon detected in 1-8 total
#' samples could reach the `"low"` risk tier even with overwhelming,
#' unambiguous read support -- and the median real taxon in both
#' PtConception datasets is detected in exactly 1 field sample, so
#' sample-count shrinkage caps the vast majority of legitimately clean
#' detections at `"moderate"` (12S: 97% of taxa, 18S: 88%) purely as an
#' artifact of sample count, not evidence quality.
#'
#' Read count avoids this and needs no change to the 0.5 shrink target
#' (already correct in depth-normalized rate space, per the
#' Depth-weighting section above). A read-FRACTION-based alternative (shrink
#' toward the study's own control:field depth ratio rather than 0.5) was
#' also tried and rejected: it requires anchoring to that ratio explicitly
#' and does not transfer across studies with very different ratios --
#' verified directly against both real datasets, where it either missed or
#' downgraded taxa the read-count approach correctly flags `"high"`.
#'
#' Empirically validated against real PtConception 12S and 18S data at
#' `prior_weight` (read-equivalent units) of 20, 50, 100, and 500: the known
#' `"high"`-risk taxa are recovered with 100% sensitivity and zero false
#' positives at every value tested, on both datasets, while a much larger
#' fraction of well-supported clean detections correctly reach `"low"`
#' instead of being capped at `"moderate"`. Default chosen:
#' `prior_weight = 20` -- recovers the most `"low"`-tier informativeness of
#' the values tested while still correctly keeping thin (~20-30 total read)
#' single-detections at `"moderate"`, not `"low"` (a genuinely
#' well-supported single-sample detection with tens of thousands of reads
#' does reach `"low"`, as it should).
#'
#' @param input_df Data frame in long format.
#' @param event_col,taxon_col,count_col Column name strings.
#' @param control_ids,field_ids Character vectors of sample IDs.
#' @param prior_weight Numeric. Equivalent read count for shrinking the final
#'   ratio toward 0.5. Higher values pull harder toward 0.5 for taxa with
#'   little total read
#'   support (field + control combined).
#'
#' @return Data frame with one row per taxon and columns: \code{taxon},
#'   \code{mean_prop_field}, \code{mean_prop_control}, \code{field_rate},
#'   \code{control_rate}, \code{n_field_present}, \code{n_controls_present},
#'   \code{n_controls_total}, \code{n_reads_total}, \code{contaminant_score}.
#'
#' @noRd
.compute_contaminant_scores <- function(input_df, event_col, taxon_col, count_col,
                                        control_ids, field_ids,
                                        prior_weight = 20) {
  # Standardise column names for internal use
  work <- data.frame(
    sample = input_df[[event_col]],
    taxon = input_df[[taxon_col]],
    n_reads = input_df[[count_col]],
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
  field_depth <- sum(sample_totals$total_reads[sample_totals$sample %in% field_ids])
  control_depth <- sum(sample_totals$total_reads[sample_totals$sample %in% control_ids])

  # Get all unique taxa
  all_taxa <- unique(work$taxon)
  n_controls_total <- length(control_ids)

  results <- lapply(all_taxa, function(tx) {
    tx_rows <- work[work$taxon == tx, , drop = FALSE]
    field_rows <- tx_rows[!tx_rows$is_control, , drop = FALSE]
    control_rows <- tx_rows[tx_rows$is_control, , drop = FALSE]

    # Informational only: unweighted mean of per-sample proportions -- does
    # not feed contaminant_score.
    mean_prop_field <- if (nrow(field_rows) > 0L) mean(field_rows$prop) else 0
    mean_prop_control <- if (nrow(control_rows) > 0L) mean(control_rows$prop) else 0

    n_field_present <- length(unique(field_rows$sample))
    n_controls_present <- length(unique(control_rows$sample))

    # Depth-weighted rate per group: taxon reads / total sequencing depth
    # of that group. Equivalent to a reads-weighted mean of per-sample
    # proportions -- normalizing by each group's OWN total depth (not a
    # shared pool) keeps the comparison scale-free even when field and
    # control pools have very different total sequencing depth (the common
    # real case: many field samples, few small blanks).
    taxon_field_reads <- sum(field_rows$n_reads)
    taxon_control_reads <- sum(control_rows$n_reads)
    field_rate <- if (field_depth > 0) taxon_field_reads / field_depth else 0
    control_rate <- if (control_depth > 0) taxon_control_reads / control_depth else 0

    # Raw (un-shrunk) ratio: field_rate / (field_rate + control_rate), using
    # depth-weighted rates in place of unweighted per-sample-proportion means.
    rate_sum <- field_rate + control_rate
    raw_score <- if (rate_sum > 0) field_rate / rate_sum else 0.5

    # Empirical Bayes shrinkage of the FINAL ratio toward 0.5 (maximally
    # uncertain), weighted by total READ count (n_reads_total summed across
    # both groups) -- w = n_reads_total / (n_reads_total + prior_weight).
    # Read count rather than sample count, since sample count would conflate
    # a 2-read detection with a 500,000-read detection whenever both happened
    # to come from a single sample -- see this function's "Reads, not
    # samples" roxygen section for the real-data evidence for this choice.
    # Shrinking the ratio itself, rather than shrinking field_rate/
    # control_rate separately toward some shared reference rate, avoids a
    # subtle bug: shrinking each rate toward the taxon's own pooled
    # (field+control) average would let a taxon's own (usually much larger)
    # field read volume leak into its control-side prior, systematically
    # understating genuinely clean taxa's scores whenever field depth
    # dominated control depth -- exactly the group-depth-imbalance problem
    # depth-weighting is meant to avoid. Shrinking the ratio by read count
    # instead keeps the two groups' magnitudes fully independent.
    n_reads_total <- taxon_field_reads + taxon_control_reads
    w <- n_reads_total / (n_reads_total + prior_weight)
    score <- w * raw_score + (1 - w) * 0.5

    data.frame(
      taxon = tx,
      mean_prop_field = mean_prop_field,
      mean_prop_control = mean_prop_control,
      field_rate = field_rate,
      control_rate = control_rate,
      n_field_present = n_field_present,
      n_controls_present = n_controls_present,
      n_controls_total = n_controls_total,
      n_reads_total = n_reads_total,
      contaminant_score = score,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, results)
}

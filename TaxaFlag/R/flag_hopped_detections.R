# Exports: flag_hopped_detections
# Internal helpers: .hop_poisson_upper, .hop_fit_control_rate, .hop_run_rates

#' Flag Detections Explained by Read Spillover Between Samples on a Run
#'
#' Flags individual detections (one feature in one sample) whose read count is
#' no larger than what spillover from the SAME feature elsewhere on the same
#' sequencing run would be expected to deposit there. Spillover covers Illumina
#' index hopping, tag jumps and Nanopore barcode misassignment: every mechanism
#' in which a small fraction of a feature's reads are credited to other samples
#' in the same pool.
#'
#' @section Why a flat read threshold does not work:
#' Spilled reads scale with how abundant a feature is ELSEWHERE on the run, not
#' with a constant. A floor of, say, 100 reads is simultaneously too lax for a
#' feature carrying millions of reads on the run (it can spill hundreds into
#' every sample) and too strict for a genuinely rare feature (which spills
#' essentially nothing, so its 30-read detection is real). On one real
#' three-marker study a flat 100-read floor removed 57-85\% of all detections.
#' This function therefore compares each detection with its OWN expected
#' spillover.
#'
#' @section The model:
#' For feature \eqn{i} and receiving sample \eqn{j} on one run,
#' \deqn{E_{ij} = r \times S_{ij} \times w_j}
#' where \eqn{S_{ij}} is the feature's reads in every OTHER sample on the run
#' (the source), \eqn{w_j} is sample \eqn{j}'s share of what spills, and
#' \eqn{r} is the run's spillover rate: the fraction of a feature's reads that
#' end up credited to some other sample. A sample that holds all of a
#' feature's reads on the run has no source and can never be flagged.
#'
#' \code{receiver_share = "equal"} (the default) gives every other sample on the
#' run the same share, \eqn{1/(n-1)}. \code{"depth"} makes the share
#' proportional to the sample's reads. \code{"depth"} CANNOT be estimated from
#' negative controls: a blank holding nothing but spilled reads has a depth
#' made of those same reads, so its share is caused by the spillover it is
#' meant to measure and the estimated rate comes out near 1 whatever the truth.
#' It is only meaningful with a spike, whose receivers are field samples with
#' their own DNA; with a spike, fit both and compare.
#'
#' \eqn{r} is ESTIMATED PER RUN from the data, never assumed, from one of two
#' kinds of evidence:
#' \itemize{
#'   \item \strong{A non-native spike} (\code{spike_taxa} in
#'     \code{spike_samples}). Every spike read outside its positive control is
#'     spillover, with nothing else that can explain it, and every other sample
#'     on the run is a receiver. This is the better estimator and is used
#'     whenever a run has one.
#'   \item \strong{Negative controls} (\code{control_samples}). A control's reads
#'     of a feature are spillover or contamination, and the two are separated
#'     by shape: spillover is proportional to the feature's source, so all
#'     spilling features share one rate, whereas a contaminant carries far more
#'     control reads than its source can explain. The rate is fitted, every
#'     feature whose control reads are improbably high under it (one-sided
#'     Poisson, \code{alpha}) is excluded, and the rate is refitted until no
#'     further feature is excluded. Excluded features are reported in
#'     \code{attr(, "control_excess")} as reagent contamination candidates -- a
#'     different problem, for \code{\link{flag_contaminant}}. Low-level
#'     contamination by a feature that is also common in the field cannot be
#'     told apart from spillover and inflates \eqn{r}, which errs toward
#'     flagging more.
#' }
#' The estimate is \eqn{\hat r = k / M}, with \eqn{k} the spilled reads observed
#' and \eqn{M} their expected count at \eqn{r = 1} (the exposure): the Poisson
#' maximum likelihood estimate. The upper bound \eqn{r_{up}} is the exact
#' one-sided Poisson upper confidence limit on \eqn{k} at level
#' \code{1 - alpha}, divided by \eqn{M}.
#'
#' @section Verdicts:
#' A detection with \eqn{x} reads is compared with a Poisson count of mean
#' \eqn{E}. It is:
#' \itemize{
#'   \item \code{"invalid_index_hop"} when \eqn{P(X \ge x) > } \code{alpha} at
#'     \eqn{\hat r}: the estimated rate alone explains it. Requires \eqn{k > 0},
#'     i.e. spillover was actually observed on that run.
#'   \item \code{"questionable_index_hop"} when it is explained only at the upper
#'     bound \eqn{r_{up}}. On a run whose controls held NO spilled reads
#'     (\eqn{k = 0}) this is the only tier available, and how much it flags
#'     depends on how much the controls could have caught: a clean run with
#'     many controls and abundant sources bounds \eqn{r} tightly and flags
#'     little. The reason string says which case applies.
#'   \item \code{"valid"} otherwise.
#'   \item \code{NA} (not assessed) for control and spike samples, zero-count
#'     rows, and every row of a run with no usable evidence. A run without
#'     evidence is reported, never given a verdict: see \code{attr(, "run_rates")}.
#' }
#' Any read of a spike feature outside \code{spike_samples} is
#' \code{"invalid_index_hop"} regardless of the test, because a non-native spike
#' cannot be genuinely present in a field sample.
#'
#' Spillover counts are over-dispersed relative to a Poisson; this under-flags
#' at the \code{invalid} tier, which the \code{questionable} tier partly offsets.
#' The flags are a screening statistic; the workflow decides what to drop.
#'
#' @section What to pass in:
#' Pass the WHOLE run table, including controls, every feature and samples you
#' do not intend to analyse: sources \eqn{S_{ij}} and sample counts are computed
#' from it, and a pre-filtered table understates both. Pass one marker/assay at
#' a time. \code{run_col} must identify the physical pool that was sequenced
#' together, which is not necessarily a field trip or collection event.
#'
#' \strong{A clean control must still be present.} A long table that keeps only
#' positive counts has no row at all for a control that sequenced nothing, and
#' that control then counts for nothing: its run can read as having no evidence
#' when it in fact has the best evidence there is. Give each such control one
#' zero-count row carrying its \code{run_col}. A control listed in
#' \code{control_samples} but absent from \code{input_df} is reported in
#' \code{attr(, "controls_absent")}.
#'
#' @param input_df Long-format data frame, one row per feature x sample.
#' @param event_col Character. Column identifying the sequenced sample
#'   (library, replicate or recording unit). Default \code{"event_id"}.
#' @param taxon_col Character. Column identifying the feature. A fine-grained
#'   feature id (ESV/ASV, or a call/image id for non-sequence data) is
#'   preferable to a taxon name, because spillover acts on the feature and
#'   does not depend on assignment succeeding. Default \code{"taxon_name"}.
#' @param count_col Character. Numeric count column. Default \code{"count"}.
#' @param run_col Character or NULL. Column identifying the run (the pool in
#'   which spillover can occur). When NULL the whole table is treated as one
#'   run and a warning says so.
#' @param control_samples Character vector of \code{event_col} values that are
#'   negative controls (field, extraction or PCR blanks). May be NULL when
#'   \code{spike_taxa} is supplied.
#' @param spike_taxa Character vector of \code{taxon_col} values that are a
#'   NON-NATIVE positive-control spike: a feature that cannot genuinely occur in
#'   any field sample. Do not list a native spike here; its field detections
#'   would all be flagged. Default NULL.
#' @param spike_samples Character vector of \code{event_col} values holding the
#'   spike (positive controls). Required with \code{spike_taxa}.
#' @param receiver_share Character. \code{"equal"} (default) or \code{"depth"};
#'   see The model. \code{"depth"} requires a spike on every assessed run.
#' @param alpha Numeric in (0, 1). Tail probability used three ways: a
#'   detection more improbable than this under spillover is \code{"valid"}; a
#'   control feature more improbable than this is excluded as contamination;
#'   and \code{1 - alpha} is the confidence level of the rate's upper bound.
#'   Default 0.01.
#' @param verbose Logical. Print a per-run summary. Default TRUE.
#'
#' @return \code{input_df} in its original row order with these columns added:
#' \describe{
#'   \item{\code{observation_validity}}{Numeric 0--1, \eqn{x / (x + E)}: the
#'     share of the detection's reads that expected spillover does not account
#'     for. Higher = more likely genuine. A ranked screening statistic, not a
#'     probability. \code{NA} where not assessed.}
#'   \item{\code{validity_flag}}{\code{"invalid_index_hop"},
#'     \code{"questionable_index_hop"}, \code{"valid"} or \code{NA} -- see
#'     Verdicts. Shares TaxaFlag's unified validity schema, so
#'     \code{\link{report_flags}} picks it up.}
#'   \item{\code{validity_reason}}{Plain-English explanation, including why a
#'     row was not assessed.}
#'   \item{\code{hop_source_reads}}{\eqn{S_{ij}}.}
#'   \item{\code{hop_receiver_share}}{\eqn{w_j}.}
#'   \item{\code{hop_expected}, \code{hop_expected_upper}}{\eqn{E} at \eqn{\hat r}
#'     and at \eqn{r_{up}}.}
#'   \item{\code{hop_p_spill}}{\eqn{P(X \ge x)} at \eqn{\hat r}.}
#'   \item{\code{hop_basis}}{\code{"spike"} or \code{"controls"}.}
#' }
#' Attribute \code{"run_rates"}: one row per run with \code{n_samples},
#' \code{n_controls}, \code{n_spike_samples}, \code{control_reads}, the evidence
#' used (\code{basis}), \eqn{k} (\code{spill_reads}), \eqn{M}
#' (\code{exposure}), \code{rate}, \code{rate_upper}, the separate
#' \code{rate_controls}/\code{rate_spike} estimates, \code{n_control_excess},
#' \code{hop_signature} (Spearman correlation, across features, between
#' control reads and source reads after exclusion: positive is the spillover
#' signature, near zero means the control reads look like something else) and
#' \code{evidence}: \code{"estimated"}, \code{"bound_only"} (no spilled reads
#' observed) or \code{"none"} (nothing to estimate from). Attribute
#' \code{"control_excess"}: the run x feature pairs excluded as contamination,
#' with their control reads, source reads and implied rate. Attribute
#' \code{"controls_absent"}: \code{control_samples} with no rows in
#' \code{input_df}.
#'
#' @section Before trusting a negative result:
#' "Nothing flagged" on a run whose \code{evidence} is \code{"bound_only"}
#' means the test had limited power, not that there was no spillover. Read
#' \code{rate_upper}: it is the largest rate the controls cannot exclude.
#'
#' @seealso \code{\link{flag_contaminant}} for reagent contamination (whole
#'   features more abundant in controls than in the field), and
#'   \code{\link{validate_controls}}, which should pass before either is trusted.
#'
#' @examples
#' # One run: an abundant feature spills a few reads into every sample and into
#' # the blank; a rare feature's small detection is genuine.
#' reads_long <- data.frame(
#'   event_id   = c("S1", "S2", "S3", "S1", "S2", "S3", "Blank1", "S3"),
#'   taxon_name = c("Abundant", "Abundant", "Abundant", "Other", "Other",
#'                  "Other", "Abundant", "Rare"),
#'   count      = c(200000, 25, 30, 5000, 60000, 55000, 22, 28),
#'   run        = "Run1"
#' )
#' res <- flag_hopped_detections(
#'   reads_long,
#'   run_col = "run",
#'   control_samples = "Blank1"
#' )
#' res[, c("event_id", "taxon_name", "count", "validity_flag")]
#' attr(res, "run_rates")
#'
#' # Non-sequencing example: a camera-trap upload batch where images are
#' # occasionally filed under the wrong station, with a lens-capped camera as
#' # the control.
#' images <- data.frame(
#'   event_id   = c("CamA", "CamB", "CamC", "CamA", "CamB", "Capped"),
#'   taxon_name = c("Deer", "Deer", "Deer", "Fox", "Fox", "Deer"),
#'   count      = c(4000, 3, 250, 40, 900, 2),
#'   batch      = "Upload1"
#' )
#' flag_hopped_detections(images, run_col = "batch", control_samples = "Capped",
#'                        verbose = FALSE)
#' @export
flag_hopped_detections <- function(input_df,
                                   event_col = "event_id",
                                   taxon_col = "taxon_name",
                                   count_col = "count",
                                   run_col = NULL,
                                   control_samples = NULL,
                                   spike_taxa = NULL,
                                   spike_samples = NULL,
                                   receiver_share = c("equal", "depth"),
                                   alpha = 0.01,
                                   verbose = TRUE) {
  # --- Input validation ---
  if (!is.data.frame(input_df)) stop("'input_df' must be a data frame.", call. = FALSE)
  for (col in c(event_col, taxon_col, count_col, run_col)) {
    if (!col %in% names(input_df)) {
      stop(sprintf("Column '%s' not found in input_df.", col), call. = FALSE)
    }
  }
  if (!is.numeric(input_df[[count_col]])) {
    stop(sprintf("Column '%s' must be numeric.", count_col), call. = FALSE)
  }
  if (!is.numeric(alpha) || length(alpha) != 1L || is.na(alpha) || alpha <= 0 || alpha >= 1) {
    stop("'alpha' must be a single number in (0, 1).", call. = FALSE)
  }
  receiver_share <- match.arg(receiver_share)
  if (is.null(control_samples) && is.null(spike_taxa)) {
    stop("Supply 'control_samples', 'spike_taxa' + 'spike_samples', or both: ",
      "the spillover rate is estimated from them, never assumed.",
      call. = FALSE
    )
  }
  if (!is.null(spike_taxa) && is.null(spike_samples)) {
    stop("'spike_samples' is required with 'spike_taxa'.", call. = FALSE)
  }
  both <- intersect(control_samples, spike_samples)
  if (length(both)) {
    stop("A sample cannot be both a negative control and a spike sample: ",
      paste(both, collapse = ", "),
      call. = FALSE
    )
  }
  all_events <- unique(as.character(input_df[[event_col]]))
  if (!is.null(control_samples) && !any(control_samples %in% all_events)) {
    stop("None of 'control_samples' found in input_df. A control with no reads at all has ",
      "no rows in a long table that keeps only positive counts; give each such control ",
      "one zero-count row carrying its run so it is counted (see 'What to pass in').",
      call. = FALSE
    )
  }
  if (!is.null(spike_samples) && !any(spike_samples %in% all_events)) {
    stop("None of 'spike_samples' found in input_df.", call. = FALSE)
  }
  if (!is.null(spike_taxa) && !any(spike_taxa %in% input_df[[taxon_col]])) {
    stop("None of 'spike_taxa' found in input_df.", call. = FALSE)
  }
  controls_absent <- setdiff(control_samples, all_events)
  if (length(controls_absent)) {
    warning(sprintf(
      "%d control sample(s) have no rows in input_df and count for nothing: %s. A control that sequenced nothing needs one zero-count row carrying its run.",
      length(controls_absent), paste(utils::head(controls_absent, 8), collapse = ", ")
    ), call. = FALSE)
  }
  if (is.null(run_col)) {
    warning("run_col is NULL: the whole table is treated as ONE run. Spillover ",
      "happens within a sequencing pool; pooling several runs mixes their ",
      "rates and sources.",
      call. = FALSE
    )
  }

  # --- Standardise to internal columns ---
  d <- data.frame(
    run = if (is.null(run_col)) "all" else as.character(input_df[[run_col]]),
    event = as.character(input_df[[event_col]]),
    taxon = as.character(input_df[[taxon_col]]),
    reads = input_df[[count_col]],
    stringsAsFactors = FALSE
  )
  d$reads[is.na(d$reads)] <- 0
  if (any(d$reads < 0)) {
    stop(sprintf("Column '%s' has negative counts.", count_col), call. = FALSE)
  }
  d$role <- ifelse(d$event %in% control_samples, "control",
    ifelse(d$event %in% spike_samples, "spike_sample", "field")
  )
  d$spike <- d$taxon %in% spike_taxa

  # Per-cell reads (a feature split across several rows of one sample is
  # summed), per-feature run totals, and each sample's receiver share.
  ev_key <- paste(d$run, d$event, sep = "\r")
  cell_key <- paste(ev_key, d$taxon, sep = "\r")
  ft_key <- paste(d$run, d$taxon, sep = "\r")
  cell <- tapply(d$reads, cell_key, sum)
  ftot <- tapply(d$reads, ft_key, sum)
  d$own <- as.numeric(cell[cell_key])
  d$source <- as.numeric(ftot[ft_key]) - d$own
  if (receiver_share == "depth") {
    depth <- tapply(d$reads, ev_key, sum)
    run_total <- tapply(d$reads, d$run, sum)
    d$share <- as.numeric(depth[ev_key]) / as.numeric(run_total[d$run])
  } else {
    n_ev_run <- tapply(d$event, d$run, function(x) length(unique(x)))
    d$share <- 1 / pmax(as.numeric(n_ev_run[d$run]) - 1, 1)
  }

  # --- Per-run rate ---
  fit <- .hop_run_rates(d, alpha = alpha, receiver_share = receiver_share)
  rates <- fit$rates

  # --- Per-detection test ---
  ri <- match(d$run, rates$run)
  k <- rates$spill_reads[ri]
  mu <- rates$rate[ri] * d$source * d$share
  mu_up <- rates$rate_upper[ri] * d$source * d$share
  x <- d$own
  p_spill <- stats::ppois(x - 1, mu, lower.tail = FALSE)
  p_spill_up <- stats::ppois(x - 1, mu_up, lower.tail = FALSE)

  is_det <- d$role == "field" & d$reads > 0
  testable <- is_det & !is.na(mu_up)
  inv <- testable & k > 0 & p_spill > alpha
  que <- testable & !inv & p_spill_up > alpha
  spike_leak <- is_det & d$spike
  no_ev <- is_det & is.na(mu_up)

  flag <- rep(NA_character_, nrow(d))
  flag[testable] <- "valid"
  flag[que] <- "questionable_index_hop"
  flag[inv | spike_leak] <- "invalid_index_hop"

  fmt <- function(v) formatC(v, format = "g", digits = 3)
  reason <- rep(NA_character_, nrow(d))
  reason[testable] <- sprintf(
    paste0(
      "%s reads vs %s expected from spillover (%s at the rate's upper bound) ",
      "of %s source reads elsewhere on run %s"
    ),
    format(x[testable], big.mark = ","), fmt(mu[testable]), fmt(mu_up[testable]),
    format(d$source[testable], big.mark = ","), d$run[testable]
  )
  bound_only <- que & k == 0
  reason[bound_only] <- paste0(
    reason[bound_only],
    "; no spillover was observed in this run's controls, so this rests on the rate's upper bound only"
  )
  reason[spike_leak] <- "non-native spike feature outside its positive control: spillover by definition"
  reason[d$role == "control"] <- "negative control sample: not assessed"
  reason[d$role == "spike_sample"] <- "spike (positive control) sample: not assessed"
  reason[d$role == "field" & d$reads == 0] <- "zero reads: not a detection"
  reason[no_ev & !spike_leak] <- sprintf(
    "run %s has no usable control or spike evidence: not assessed", d$run[no_ev & !spike_leak]
  )

  assessed <- !is.na(flag)
  mu0 <- ifelse(is.na(mu), 0, mu)
  out <- input_df
  out$observation_validity <- ifelse(assessed, x / (x + mu0), NA_real_)
  out$observation_validity[spike_leak] <- 0
  out$validity_flag <- flag
  out$validity_reason <- reason
  out$hop_source_reads <- ifelse(testable, d$source, NA_real_)
  out$hop_receiver_share <- ifelse(testable, d$share, NA_real_)
  out$hop_expected <- ifelse(testable, mu, NA_real_)
  out$hop_expected_upper <- ifelse(testable, mu_up, NA_real_)
  out$hop_p_spill <- ifelse(testable, p_spill, NA_real_)
  out$hop_basis <- ifelse(testable, rates$basis[ri], NA_character_)

  # --- Loud reporting ---
  if (verbose) {
    message(sprintf(
      "flag_hopped_detections: %d run(s), receiver_share = \"%s\", alpha = %s",
      nrow(rates), receiver_share, format(alpha)
    ))
    for (i in seq_len(nrow(rates))) {
      rr <- rates[i, ]
      sel <- d$run == rr$run & assessed
      message(sprintf(
        "  %-12s %-8s %-10s rate %-9s upper %-9s | %d invalid, %d questionable of %d detections",
        rr$run, ifelse(is.na(rr$basis), "-", rr$basis), rr$evidence,
        fmt(rr$rate), fmt(rr$rate_upper),
        sum(flag[sel] == "invalid_index_hop"), sum(flag[sel] == "questionable_index_hop"),
        sum(sel)
      ))
    }
    if (nrow(fit$control_excess)) {
      message(
        sprintf("  %d run x feature pair(s) carry more control reads than spillover explains: ", nrow(fit$control_excess)),
        "contamination, excluded from the rate. See attr(, \"control_excess\") and flag_contaminant()."
      )
    }
  }
  if (any(rates$evidence == "none")) {
    warning(sprintf(
      "%d run(s) have no usable control or spike evidence and were NOT assessed: %s. %s detection(s) carry NA.",
      sum(rates$evidence == "none"), paste(rates$run[rates$evidence == "none"], collapse = ", "),
      format(sum(no_ev & !spike_leak), big.mark = ",")
    ), call. = FALSE)
  }

  attr(out, "run_rates") <- rates
  attr(out, "control_excess") <- fit$control_excess
  attr(out, "controls_absent") <- controls_absent
  out
}

#' Exact one-sided Poisson upper confidence limit on a count
#'
#' The mean at which observing \code{k} or fewer events has probability
#' \code{alpha}: \code{qgamma(1 - alpha, k + 1)}. For \code{k = 0} this is
#' \code{-log(alpha)} (about 4.6 at alpha = 0.01).
#' @noRd
.hop_poisson_upper <- function(k, alpha) stats::qgamma(1 - alpha, shape = k + 1)

#' Fit the spillover rate from negative-control cells, excluding contaminants
#'
#' \code{x} = control reads, \code{m} = exposure (source x share) per control
#' cell, \code{taxon} = feature. Fits r = sum(x)/sum(m), drops every feature
#' with a cell improbably high under it (one-sided Poisson at alpha), refits,
#' and repeats until nothing more is dropped. Exclusion only ever removes the
#' high side, so r is non-increasing and the loop terminates.
#' @noRd
.hop_fit_control_rate <- function(x, m, taxon, alpha) {
  keep <- m > 0
  repeat {
    k <- sum(x[keep])
    mm <- sum(m[keep])
    if (mm <= 0) break
    r <- k / mm
    high <- keep & stats::ppois(x - 1, r * m, lower.tail = FALSE) < alpha
    if (!any(high)) break
    keep <- keep & !taxon %in% taxon[high]
  }
  list(k = sum(x[keep]), m = sum(m[keep]), keep = keep)
}

#' Per-run spillover rate from spike or control evidence
#'
#' Takes the standardised table built inside flag_hopped_detections() (columns
#' run, event, taxon, role, spike, own, source, share) and returns list(rates =
#' one row per run, control_excess = excluded run x feature pairs). A spike is
#' preferred when a run has one.
#' @noRd
.hop_run_rates <- function(d, alpha, receiver_share) {
  cells <- d[!duplicated(paste(d$run, d$event, d$taxon, sep = "\r")), ]
  per_run <- lapply(unique(d$run), function(rn) {
    cr <- cells[cells$run == rn, ]
    n_ctl <- length(unique(cr$event[cr$role == "control"]))
    n_spk <- length(unique(cr$event[cr$role == "spike_sample"]))
    excess <- NULL
    k_c <- 0
    m_c <- 0
    sig <- NA_real_

    # Negative controls. "depth" shares are circular for a blank (see roxygen),
    # so controls only contribute under "equal".
    if (n_ctl > 0 && receiver_share == "equal") {
      ctl <- cr[cr$role == "control" & !cr$spike & cr$own > 0, ]
      # Zero-read cells are observations too: a feature abundant in the field
      # but ABSENT from a control is evidence of a low rate. Add them back as
      # one exposure term per (control, field feature) pair.
      fld_tot <- tapply(cr$own[cr$role != "control"], cr$taxon[cr$role != "control"], sum)
      fld_tot <- fld_tot[fld_tot > 0 & !names(fld_tot) %in% cr$taxon[cr$spike]]
      ctl_ids <- unique(cr$event[cr$role == "control"])
      share <- cr$share[1]
      grid <- expand.grid(event = ctl_ids, taxon = names(fld_tot), stringsAsFactors = FALSE)
      hit <- match(paste(grid$event, grid$taxon), paste(ctl$event, ctl$taxon))
      gx <- ifelse(is.na(hit), 0, ctl$own[hit])
      # source for a control cell = the feature's reads everywhere else on the run
      all_tot <- tapply(cr$own, cr$taxon, sum)
      gsrc <- as.numeric(all_tot[grid$taxon]) - gx
      # features present ONLY in controls have no source: pure contamination
      only_ctl <- setdiff(unique(ctl$taxon), names(fld_tot))
      f <- .hop_fit_control_rate(gx, gsrc * share, grid$taxon, alpha)
      k_c <- f$k
      m_c <- f$m
      dropped <- unique(grid$taxon[!f$keep & gx > 0])
      ex_taxa <- c(dropped, only_ctl)
      if (length(ex_taxa)) {
        cx <- tapply(ctl$own, ctl$taxon, sum)[ex_taxa]
        src <- as.numeric(all_tot[ex_taxa]) - as.numeric(cx)
        excess <- data.frame(
          run = rn, feature = ex_taxa, control_reads = as.numeric(cx),
          source_reads = src,
          implied_rate = ifelse(src > 0, as.numeric(cx) / (src * share * n_ctl), Inf),
          stringsAsFactors = FALSE
        )
      }
      kept <- f$keep
      if (sum(kept) > 2L && length(unique(gsrc[kept])) > 2L) {
        sig <- suppressWarnings(stats::cor(gx[kept], gsrc[kept], method = "spearman"))
      }
    }

    # Spike: every spike read outside its positive control is spillover.
    k_s <- 0
    m_s <- 0
    spk_src <- cr$own[cr$spike & cr$role == "spike_sample"]
    if (n_spk > 0 && sum(spk_src) > 0) {
      recv <- cr[cr$role != "spike_sample", ]
      recv <- recv[!duplicated(recv$event), c("event", "share")]
      k_s <- sum(cr$own[cr$spike & cr$role != "spike_sample"])
      m_s <- sum(spk_src) * sum(recv$share)
    }

    basis <- if (m_s > 0) "spike" else if (m_c > 0) "controls" else NA_character_
    k <- if (is.na(basis)) NA_real_ else if (basis == "spike") k_s else k_c
    m <- if (is.na(basis)) NA_real_ else if (basis == "spike") m_s else m_c
    list(
      rates = data.frame(
        run = rn,
        n_samples = length(unique(cr$event)),
        n_controls = n_ctl,
        n_spike_samples = n_spk,
        control_reads = sum(cr$own[cr$role == "control"]),
        basis = basis,
        spill_reads = k,
        exposure = m,
        rate = k / m,
        rate_upper = .hop_poisson_upper(k, alpha) / m,
        rate_controls = if (m_c > 0) k_c / m_c else NA_real_,
        rate_spike = if (m_s > 0) k_s / m_s else NA_real_,
        n_control_excess = if (is.null(excess)) 0L else nrow(excess),
        hop_signature = sig,
        evidence = if (is.na(basis)) "none" else if (k > 0) "estimated" else "bound_only",
        stringsAsFactors = FALSE
      ),
      excess = excess
    )
  })
  rates <- do.call(rbind, lapply(per_run, `[[`, "rates"))
  ex <- lapply(per_run, `[[`, "excess")
  ex <- ex[!vapply(ex, is.null, logical(1))]
  control_excess <- if (length(ex)) {
    do.call(rbind, ex)
  } else {
    data.frame(
      run = character(0), feature = character(0), control_reads = numeric(0),
      source_reads = numeric(0), implied_rate = numeric(0)
    )
  }
  rownames(rates) <- NULL
  rownames(control_excess) <- NULL
  list(rates = rates, control_excess = control_excess)
}

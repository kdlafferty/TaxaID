utils::globalVariables(c(
  "..column_id", "..site", "..is_control", "..reads", "..taxon", "..prop"
))

#' Validate That Control Samples Actually Look Like Controls
#'
#' Tests whether each column labelled a control is compositionally consistent
#' with being one, and -- in the other direction -- whether any column labelled
#' a field sample looks like a control. Mislabelling runs both ways, and a
#' mislabelled field sample sitting in the control set is the more damaging of
#' the two: it makes the real community look like contamination, so
#' \code{\link{flag_contaminant}} then filters genuine signal.
#'
#' @section The principle:
#' \strong{A control is defined by what it LACKS, not by what it contains.}
#' Whatever the medium -- tapwater, sterilised seawater, molecular-grade water,
#' air -- a control's defining property is that its composition is not drawn
#' from the sampled habitat. Everything here follows from that, which is why
#' the test needs no taxonomy, no habitat model, no marker-specific tuning and
#' no assumption about what the blank medium is.
#'
#' @section Why the reference must come from the data:
#' The test statistic is each control's median compositional distance to the
#' FIELD SAMPLES IT SITS WITH, compared against the null distribution of
#' sample-to-sample distance \emph{at that same site}. A fixed cutoff cannot
#' work: measured on one real COI study, the within-site sample-vs-sample
#' median ranged from 0.145 to 0.890 ACROSS SITES IN THAT ONE DATASET. A
#' threshold of 0.8 would have called every control at the tight site a blank
#' and every control at the heterogeneous site a sample, on data where both
#' were in fact fine. Drawing the null from each site's own samples
#' self-calibrates to marker diversity, habitat and sampling design.
#'
#' @section Power is reported, not assumed:
#' Two situations both produce "nothing flagged", for opposite reasons, and
#' this function refuses to let them look alike: a site with many samples and a
#' tight null gives a real negative result; a site with two samples, or a null
#' spanning most of the range, has no power to detect anything. Every site gets
#' an explicit \code{power} verdict and the null's own spread, so a clean result
#' can be distinguished from an untested one.
#'
#' @param input_df Long-format data frame: one row per taxon x column
#'   observation, carrying at least \code{event_col}, \code{taxon_col} and
#'   \code{reads_col}.
#' @param event_col Character. Column identifying the sequenced column
#'   (filter, bottle, replicate). Default \code{"event_id"}.
#' @param taxon_col Character. Column identifying the feature to compare
#'   compositions on -- an ESV/ASV id is preferable to a taxon name, because it
#'   does not depend on assignment succeeding. Default \code{"taxon_name"}.
#' @param reads_col Character. Read-count column. Default \code{"n_reads"}.
#' @param control_samples Character vector of \code{event_col} values that are
#'   labelled controls.
#' @param site_col Character or NULL. Column grouping columns into sites. When
#'   NULL every column is treated as one site, which makes the null a
#'   whole-study one and weakens the test; a warning says so.
#' @param min_samples_per_site Integer. Below this many field samples a site
#'   cannot form its own null. Default 3.
#' @param quantile_threshold Numeric in (0, 1). A control is consistent with
#'   being a control when its median distance to the site's samples is at or
#'   above this quantile of the site's sample-to-sample null. Default 0.90.
#' @param verbose Logical. Print a summary. Default TRUE.
#'
#' @return A data frame, one row per sequenced column, with the column id, its
#'   site, its label, \code{n_taxa}, \code{n_reads}, the test statistic
#'   \code{d_to_samples}, the site null (\code{null_median},
#'   \code{null_threshold}, \code{null_n_pairs}), a \code{power} verdict and a
#'   \code{verdict}. Attribute \code{"site_power"} carries the per-site table.
#'
#'   \code{verdict} takes: \code{"consistent_with_control"},
#'   \code{"RESEMBLES_SAMPLE"} (a control that may be a mislabelled sample),
#'   \code{"consistent_with_sample"}, \code{"RESEMBLES_CONTROL"} (a sample that
#'   may be a mislabelled control), or \code{"untestable"}.
#'
#' @section Before trusting a negative result:
#' Prove both directions on your own data, as with any guard: relabel a known
#' field sample as a control and confirm it is flagged, and confirm a clean
#' control set stays silent. A check demonstrated only in the flagging
#' direction is half-tested, and the untested half is the one that matters when
#' it reports nothing.
#'
#' @seealso \code{\link{flag_contaminant}}, which should only be trusted once
#'   the control set has passed this.
#' @export
validate_controls <- function(input_df,
                              event_col = "event_id",
                              taxon_col = "taxon_name",
                              reads_col = "n_reads",
                              control_samples,
                              site_col = NULL,
                              min_samples_per_site = 3L,
                              quantile_threshold = 0.90,
                              verbose = TRUE) {

  stopifnot(is.data.frame(input_df))
  need <- c(event_col, taxon_col, reads_col)
  miss <- setdiff(need, names(input_df))
  if (length(miss))
    stop("validate_controls: input_df is missing column(s): ",
         paste(miss, collapse = ", "), call. = FALSE)
  if (!is.null(site_col) && !site_col %in% names(input_df))
    stop("validate_controls: site_col '", site_col, "' not found in input_df.",
         call. = FALSE)
  if (missing(control_samples) || !length(control_samples))
    stop("validate_controls: control_samples is required and must be non-empty. ",
         "With no controls there is nothing to validate -- that is an ",
         "'unassessed' state, not a clean one.", call. = FALSE)
  if (!is.numeric(quantile_threshold) || quantile_threshold <= 0 || quantile_threshold >= 1)
    stop("validate_controls: quantile_threshold must be in (0, 1).", call. = FALSE)

  d <- data.frame(
    ..column_id = as.character(input_df[[event_col]]),
    ..taxon     = as.character(input_df[[taxon_col]]),
    ..reads     = as.numeric(input_df[[reads_col]]),
    stringsAsFactors = FALSE)
  d$..site <- if (is.null(site_col)) "__all__" else as.character(input_df[[site_col]])
  d <- d[!is.na(d$..reads) & d$..reads > 0, , drop = FALSE]
  if (!nrow(d))
    stop("validate_controls: no rows with positive reads.", call. = FALSE)
  if (is.null(site_col))
    warning("validate_controls: site_col is NULL, so the null is pooled across the ",
            "whole study. Within-site nulls vary enormously (0.145 to 0.890 in one ",
            "real dataset), so a pooled null is much weaker. Supply site_col if you ",
            "have it.", call. = FALSE)

  d$..is_control <- d$..column_id %in% control_samples

  # Relative abundance within each column. Composition only -- no taxonomy is
  # consulted anywhere, which is what makes this marker-independent.
  tot <- stats::aggregate(list(t = d$..reads), by = list(c = d$..column_id), FUN = sum)
  d$..prop <- d$..reads / tot$t[match(d$..column_id, tot$c)]
  by_col <- split(d[, c("..taxon", "..prop")], d$..column_id)

  # Bray-Curtis on relative abundance: 1 - sum of shared minima. 0 identical,
  # 1 disjoint. Implemented directly to avoid a vegan dependency.
  .bray <- function(a, b) {
    m <- merge(a, b, by = "..taxon", all = TRUE)
    x <- m$..prop.x; y <- m$..prop.y
    x[is.na(x)] <- 0; y[is.na(y)] <- 0
    1 - sum(pmin(x, y))
  }
  .med_to <- function(id, others) {
    others <- setdiff(others, id)
    if (!length(others)) return(NA_real_)
    stats::median(vapply(others, function(o) .bray(by_col[[id]], by_col[[o]]),
                         numeric(1)), na.rm = TRUE)
  }

  meta <- unique(d[, c("..column_id", "..site", "..is_control")])
  meta$n_taxa  <- as.integer(table(d$..column_id)[meta$..column_id])
  meta$n_reads <- tot$t[match(meta$..column_id, tot$c)]

  out <- list(); site_power <- list()
  for (st in unique(meta$..site)) {
    ms  <- meta[meta$..site == st, , drop = FALSE]
    sam <- ms$..column_id[!ms$..is_control]
    ctl <- ms$..column_id[ ms$..is_control]

    if (length(sam) >= min_samples_per_site && length(sam) >= 2L) {
      nullv <- c()
      for (i in seq_along(sam)) for (j in seq_along(sam)) if (i < j)
        nullv <- c(nullv, .bray(by_col[[sam[i]]], by_col[[sam[j]]]))
      null_med <- stats::median(nullv, na.rm = TRUE)
      null_thr <- as.numeric(stats::quantile(nullv, quantile_threshold, na.rm = TRUE))
      null_n   <- length(nullv)
      spread   <- diff(as.numeric(stats::quantile(nullv, c(.05, .95), na.rm = TRUE)))
      # A null spanning most of [0,1] cannot separate anything. Say so rather
      # than emitting confident verdicts from it.
      pw <- if (spread > 0.6) "low_wide_null" else "ok"
    } else {
      null_med <- NA_real_; null_thr <- NA_real_; null_n <- 0L; spread <- NA_real_
      pw <- "none_too_few_samples"
    }
    site_power[[length(site_power) + 1L]] <- data.frame(
      site = st, n_samples = length(sam), n_controls = length(ctl),
      null_median = null_med, null_threshold = null_thr,
      null_n_pairs = null_n, null_spread_90 = spread, power = pw,
      stringsAsFactors = FALSE)

    for (k in seq_len(nrow(ms))) {
      id <- ms$..column_id[k]
      d_s <- .med_to(id, sam)
      d_c <- if (length(ctl) > 1L || (!ms$..is_control[k] && length(ctl) >= 1L))
               .med_to(id, ctl) else NA_real_
      verdict <-
        if (pw == "none_too_few_samples" || is.na(d_s)) {
          "untestable"
        } else if (ms$..is_control[k]) {
          if (d_s >= null_thr) "consistent_with_control" else "RESEMBLES_SAMPLE"
        } else {
          # A sample is suspect only if it is BOTH an outlier from the other
          # samples AND closer to the controls than to them. Either alone is
          # ordinary: real samples are sometimes odd, and at a site whose
          # controls are mild everything is "close" to them.
          if (!is.na(d_c) && d_s >= null_thr && d_c < d_s) "RESEMBLES_CONTROL"
          else "consistent_with_sample"
        }
      out[[length(out) + 1L]] <- data.frame(
        column_id = id, site = st,
        label = if (ms$..is_control[k]) "control" else "sample",
        n_taxa = ms$n_taxa[k], n_reads = ms$n_reads[k],
        d_to_samples = d_s, d_to_controls = d_c,
        null_median = null_med, null_threshold = null_thr, null_n_pairs = null_n,
        power = pw, verdict = verdict, stringsAsFactors = FALSE)
    }
  }

  res <- do.call(rbind, out)
  sp  <- do.call(rbind, site_power)
  res <- res[order(res$site, res$label, res$column_id), , drop = FALSE]
  rownames(res) <- NULL
  attr(res, "site_power") <- sp

  n_ctl <- sum(res$label == "control")
  n_bad <- sum(res$verdict == "RESEMBLES_SAMPLE")
  if (verbose) {
    message(sprintf("validate_controls: %d column(s) across %d site(s); %d control(s).",
                    nrow(res), nrow(sp), n_ctl))
    print(table(res$label, res$verdict))
    if (any(sp$power != "ok"))
      message(sprintf("  %d of %d site(s) have reduced or no power: %s",
                      sum(sp$power != "ok"), nrow(sp),
                      paste(unique(sp$power[sp$power != "ok"]), collapse = ", ")))
    if (sum(res$verdict == "untestable"))
      message(sprintf("  %d column(s) UNTESTABLE -- absence of a flag there is not ",
                      sum(res$verdict == "untestable")), "evidence of a clean label.")
  }
  # If every testable control looks like a sample, the control set is compromised
  # and any contaminant list built on it would filter real signal.
  testable <- res$label == "control" & res$verdict != "untestable"
  if (sum(testable) && all(res$verdict[testable] == "RESEMBLES_SAMPLE"))
    warning("validate_controls: EVERY testable control resembles a field sample. ",
            "Treat the control set as compromised and do not build a contaminant ",
            "list from it until the labels are resolved.", call. = FALSE)
  res
}

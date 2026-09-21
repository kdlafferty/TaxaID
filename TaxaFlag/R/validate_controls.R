utils::globalVariables(c(
  "..column_id", "..site", "..is_control", "..reads", "..taxon", "..prop"
))

#' Bray-Curtis distance between two columns of a taxon x column matrix
#'
#' \code{1 - sum(pmin(m[, a], m[, b]))} on relative-abundance columns: 0
#' identical, 1 disjoint. Lifted to package level (not a closure inside
#' \code{\link{validate_controls}}) purely so \code{\link{.med_to_m}} below
#' -- and this function's own correctness -- can be exercised directly by
#' tests, without depending on anything \code{validate_controls()} captures
#' in its own local environment; both are pure functions of their arguments.
#' @param m Taxon x column matrix of relative abundances.
#' @param a,b Column names (or indices) into \code{m}.
#' @return Numeric scalar between 0 and 1.
#' @noRd
.bray_m <- function(m, a, b) 1 - sum(pmin(m[, a], m[, b]))

#' id's median Bray-Curtis distance to a SET of other columns
#'
#' This is what determines every column's own verdict in
#' \code{\link{validate_controls}}, so unlike that function's null estimate
#' (capped at \code{max_null_pairs}, a coarser calibration statistic that can
#' tolerate subsampling) it is never subsampled: every one of \code{others}
#' is used, however many there are.
#'
#' Vectorised as ONE compositional-distance-to-many-columns matrix operation
#' instead of a per-\code{other} loop over \code{\link{.bray_m}}: \code{id}'s
#' own column is a length(taxa) vector, \code{others}' columns are a
#' taxa x length(others) matrix, and \code{pmin()} recycles the vector down
#' each column correctly (both are laid out taxon-major), so the whole set of
#' pairwise minima-sums comes back from one \code{pmin()} + \code{colSums()}
#' call. Mathematically identical to the per-pair loop (same additions, same
#' summation order -- bit-identical, not just numerically close) but removes
#' the O(n) R-level function-call overhead that made the loop version the
#' actual bottleneck: measured 68.8 s at a real 1,151-sample site under the
#' loop version, under 1 s vectorised on an equivalent synthetic case.
#'
#' @param m Taxon x column matrix of relative abundances.
#' @param id Character. The column to measure distance FROM.
#' @param others Character vector of column names to measure distance TO.
#'   \code{id} itself is dropped if present.
#' @return Numeric scalar between 0 and 1, or \code{NA_real_} if \code{others} is
#'   empty once \code{id} is removed from it.
#' @noRd
.med_to_m <- function(m, id, others) {
  others <- setdiff(others, id)
  if (!length(others)) return(NA_real_)
  sub <- m[, others, drop = FALSE]
  pm  <- pmin(m[, id], sub)
  dim(pm) <- dim(sub) # pmin() does not preserve the matrix's own dim
  stats::median(1 - colSums(pm), na.rm = TRUE)
}

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
#'   \code{count_col}.
#' @param event_col Character. Column identifying the sampled/observed unit
#'   (filter, bottle, replicate, recording, or image batch). Default
#'   \code{"event_id"}.
#' @param taxon_col Character. Column identifying the feature to compare
#'   compositions on -- a fine-grained candidate/detection ID (e.g. ESV/ASV
#'   for sequence data, a call/image ID for acoustic/image data) is
#'   preferable to a taxon name, because it does not depend on assignment
#'   succeeding. Default \code{"taxon_name"}.
#' @param count_col Character. Count column. Default \code{"count"}.
#' @param control_samples Character vector of \code{event_col} values that are
#'   labelled controls.
#' @param site_col Character or NULL. Column grouping columns into sites. When
#'   NULL every column is treated as one site, which makes the null a
#'   whole-study one and weakens the test; a warning says so.
#' @param min_samples_per_site Integer. Below this many field samples a site
#'   cannot form its own null. Default 3.
#' @param headroom_fraction Numeric in (0, 1). A control is consistent with being
#'   a control when its median distance to the site's samples is at least this
#'   far along the room remaining above the sample median:
#'   \code{threshold = median(null) + headroom_fraction * (1 - median(null))}.
#'   Default 0.5, i.e. halfway between "as distant as the samples are from each
#'   other" and "completely disjoint".
#'
#'   THIS FORM WAS ARRIVED AT BY FAILING TWICE ON REAL DATA, and both failures are
#'   worth knowing because each looked reasonable:
#'   \itemize{
#'     \item A high QUANTILE of the null (0.90) is in-range but not robust. A
#'       control mislabelled as a sample sits inside the sample set and inflates
#'       the very null it is tested against -- with 8 samples plus one disjoint
#'       hidden control, 22% of sample-pair distances go to ~1.0 and drag the
#'       quantile into the contaminated tail. It also has no headroom at
#'       heterogeneous sites: a real site with 1,151 samples had a 0.90-quantile of
#'       exactly 1.000, so nothing could pass.
#'     \item An additive robust fence, \code{median + 3 * MAD}, is robust but
#'       LEAVES THE METRIC'S RANGE. Bray-Curtis is bounded at 1, and on real sites
#'       this produced thresholds of 1.54 and 1.62, after which the headroom guard
#'       fired on 59 of 84 controls. Robustness is not worth an impossible cutoff.
#'   }
#'   Scaling into the remaining headroom is bounded by construction (it can never
#'   exceed 1) and depends only on the median, so it keeps the 50% breakdown point
#'   that made MAD attractive.
#' @param headroom_limit Numeric. If a site's null threshold reaches this value
#'   the test has no headroom above the samples and cannot pass anything: a
#'   control would have to be MORE disjoint than the samples already are from
#'   each other. Such columns are reported \code{"untestable_no_headroom"}
#'   rather than given a confident verdict. Found on real data: a site with 1,151
#'   samples had a null 0.90-quantile of exactly 1.000, which flagged genuine
#'   6-taxon controls as resembling 34-taxon samples. Default 0.98.
#' @param max_null_pairs Integer. Cap on the number of sample-pair distances used
#'   to estimate a site's null. The null is O(n^2) in samples, and a real site
#'   here had 213 samples = 22,578 pairs, which made the first version of this
#'   function unusable (still running after 19 minutes). A few hundred pairs
#'   estimate a median and a 0.90 quantile perfectly well, so pairs are sampled
#'   at random above this cap and \code{null_n_pairs} records how many were
#'   actually used. Default 500.
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
#'   may be a mislabelled control), \code{"untestable"} (no null available),
#'   \code{"untestable_no_headroom"} (the null reaches the metric's ceiling), or
#'   \code{"no_detections"} (every read for this column is 0 or NA, so it has
#'   no composition to compare against anything -- \code{d_to_samples}/
#'   \code{d_to_controls} are \code{NA}, \code{power} reads
#'   \code{"none_no_detections"}). \code{confidence} is \code{"low"} wherever
#'   the site's power is not \code{"ok"}; filter on it, because a verdict from
#'   a wide null is weak evidence and must not read like one from a tight
#'   null.
#'
#'   A column with no positive reads at all still gets its own row here --
#'   the "one row per sequenced column" contract above holds even for it --
#'   rather than silently disappearing because there was nothing to compute a
#'   distance from.
#'
#'   \strong{A site with two samples and a site with twenty both return "nothing
#'   flagged".} Only one of those is evidence. \code{power},
#'   \code{null_n_pairs} and \code{confidence} are what separate them, and the
#'   function says so on the console as well as here.
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
#'
#' @examples
#' reads_long <- data.frame(
#'   event_id   = c(rep(c("S1", "S2", "S3"), each = 3), "Blank1"),
#'   taxon_name = c(rep(c("TaxonA", "TaxonB", "TaxonC"), times = 3), "TaxonD"),
#'   count      = c(500, 300, 50, 480, 310, 40, 520, 290, 60, 5)
#' )
#' validate_controls(
#'   input_df        = reads_long,
#'   control_samples = "Blank1"
#' )
#'
#' # Non-sequencing example: acoustic call-detection counts, with a
#' # silent-recorder deployment standing in for a negative control
#' call_counts <- data.frame(
#'   event_id   = c(rep(c("Site1", "Site2", "Site3"), each = 2), "SilentControl"),
#'   taxon_name = c(rep(c("SpeciesA", "SpeciesB"), times = 3), "NoiseArtifact"),
#'   count      = c(40, 15, 38, 18, 44, 12, 1)
#' )
#' validate_controls(
#'   input_df        = call_counts,
#'   control_samples = "SilentControl"
#' )
#' @export
validate_controls <- function(input_df,
                              event_col = "event_id",
                              taxon_col = "taxon_name",
                              count_col = "count",
                              control_samples,
                              site_col = NULL,
                              min_samples_per_site = 3L,
                              headroom_fraction = 0.5,
                              headroom_limit = 0.98,
                              max_null_pairs = 500L,
                              verbose = TRUE) {

  stopifnot(is.data.frame(input_df))
  need <- c(event_col, taxon_col, count_col)
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
  if (!is.numeric(headroom_fraction) || headroom_fraction <= 0 || headroom_fraction >= 1)
    stop("validate_controls: headroom_fraction must be in (0, 1).", call. = FALSE)

  d <- data.frame(
    ..column_id = as.character(input_df[[event_col]]),
    ..taxon     = as.character(input_df[[taxon_col]]),
    ..reads     = as.numeric(input_df[[count_col]]),
    stringsAsFactors = FALSE)
  d$..site <- if (is.null(site_col)) "__all__" else as.character(input_df[[site_col]])
  # Site membership for EVERY column, read before the positive-reads filter
  # below -- a column whose every read is 0 or NA has no row left in `d`
  # afterward to read its own site from.
  raw_id_site <- unique(d[, c("..column_id", "..site")])
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
  # Bray-Curtis on relative abundance: 1 - sum of shared minima. 0 identical,
  # 1 disjoint. Implemented directly to avoid a vegan dependency.
  #
  # Computed from a per-site taxon x column MATRIX rather than by merging each
  # pair. The merge-per-pair version was correct but unusably slow: a real site
  # with 213 samples needs 22,578 pair distances and the function was still
  # running after 19 minutes. Aligning taxa once per site turns each distance
  # into a single vectorised pmin(), which is what makes this tractable.
  .site_mat <- function(ids) {
    sub <- d[d$..column_id %in% ids, , drop = FALSE]
    tx  <- sort(unique(sub$..taxon))
    m   <- matrix(0, nrow = length(tx), ncol = length(ids),
                  dimnames = list(tx, ids))
    m[cbind(match(sub$..taxon, tx), match(sub$..column_id, ids))] <- sub$..prop
    m
  }
  # .bray_m()/.med_to_m() are package-level (not closures here) -- see their
  # own roxygen above, just above this function.

  meta <- unique(d[, c("..column_id", "..site", "..is_control")])
  meta$n_taxa  <- as.integer(table(d$..column_id)[meta$..column_id])
  meta$n_reads <- tot$t[match(meta$..column_id, tot$c)]

  # Columns with no row surviving the positive-reads filter above (every read
  # 0 or NA) are still a real sampled/observed unit and must not silently
  # vanish from the output -- see the documented "one row per sampled unit"
  # contract. They get their own zero_meta table (n_taxa = n_reads = 0,
  # composition undefined) so the per-site loop below emits an explicit,
  # untestable row for each rather than just omitting it.
  zero_ids  <- setdiff(raw_id_site$..column_id, meta$..column_id)
  # Always a data frame (0 rows when there is nothing to add), never NULL --
  # nrow(NULL) is NULL, not 0, which would break seq_len(nrow(zms)) below for
  # every site whenever there happened to be no zero-detection columns at
  # all (i.e. almost always).
  zero_meta <- if (length(zero_ids)) {
    zm <- raw_id_site[match(zero_ids, raw_id_site$..column_id), , drop = FALSE]
    data.frame(
      ..column_id = zm$..column_id, ..site = zm$..site,
      ..is_control = zm$..column_id %in% control_samples,
      n_taxa = 0L, n_reads = 0,
      stringsAsFactors = FALSE)
  } else {
    data.frame(
      ..column_id = character(0), ..site = character(0),
      ..is_control = logical(0), n_taxa = integer(0), n_reads = numeric(0),
      stringsAsFactors = FALSE)
  }

  out <- list()
  site_power <- list()
  for (st in union(unique(meta$..site), unique(zero_meta$..site))) {
    ms  <- meta[meta$..site == st, , drop = FALSE]
    zms <- zero_meta[zero_meta$..site == st, , drop = FALSE]
    sam <- ms$..column_id[!ms$..is_control]
    ctl <- ms$..column_id[ms$..is_control]

    M <- .site_mat(ms$..column_id)
    if (length(sam) >= min_samples_per_site && length(sam) >= 2L) {
      pr <- utils::combn(length(sam), 2L)
      if (ncol(pr) > max_null_pairs)
        pr <- pr[, sample.int(ncol(pr), max_null_pairs), drop = FALSE]
      nullv <- vapply(seq_len(ncol(pr)),
                      function(k) .bray_m(M, sam[pr[1, k]], sam[pr[2, k]]),
                      numeric(1))
      null_med <- stats::median(nullv, na.rm = TRUE)
      null_mad <- stats::mad(nullv, na.rm = TRUE)
      # Bounded by construction: scales into the room left above the sample
      # median, so it can never exceed 1 however heterogeneous the site is.
      null_thr <- null_med + headroom_fraction * (1 - null_med)
      null_n   <- length(nullv)
      spread   <- diff(as.numeric(stats::quantile(nullv, c(.05, .95), na.rm = TRUE)))
      # A null spanning most of [0,1] cannot separate anything. Say so rather
      # than emitting confident verdicts from it.
      pw <- if (spread > 0.6) "low_wide_null" else "ok"
    } else {
      null_med <- NA_real_
      null_mad <- NA_real_
      null_thr <- NA_real_
      null_n <- 0L
      spread <- NA_real_
      pw <- "none_too_few_samples"
    }
    site_power[[length(site_power) + 1L]] <- data.frame(
      site = st, n_samples = length(sam), n_controls = length(ctl),
      null_median = null_med, null_mad = null_mad, null_threshold = null_thr,
      null_n_pairs = null_n, null_spread_90 = spread, power = pw,
      stringsAsFactors = FALSE)

    for (k in seq_len(nrow(ms))) {
      id <- ms$..column_id[k]
      d_s <- .med_to_m(M, id, sam)
      d_c <- if (length(ctl) > 1L || (!ms$..is_control[k] && length(ctl) >= 1L))
               .med_to_m(M, id, ctl) else NA_real_
      verdict <-
        if (pw == "none_too_few_samples" || is.na(d_s)) {
          "untestable"
        } else if (!is.na(null_thr) && null_thr >= headroom_limit) {
          # No headroom: the samples are already as dissimilar from each other as
          # the metric allows, so nothing can sit above them. Reporting
          # RESEMBLES_SAMPLE here would be an artefact of the threshold, not a
          # finding about the column.
          "untestable_no_headroom"
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
        power = pw,
        # A verdict from a wide null is weak evidence, and must not read the same
        # as one from a tight null. Callers should filter on this, not just on
        # verdict.
        confidence = if (pw == "ok") "ok" else "low",
        verdict = verdict, stringsAsFactors = FALSE)
    }

    # A column with no positive reads at all has no composition to compare
    # against anything -- d_to_samples/d_to_controls are NA by construction,
    # never estimated as 0/identical. The site's own null (whatever was
    # computed above from its real samples, if any) is still recorded
    # alongside it for context, exactly as an "untestable" row above does.
    for (k in seq_len(nrow(zms))) {
      out[[length(out) + 1L]] <- data.frame(
        column_id = zms$..column_id[k], site = st,
        label = if (zms$..is_control[k]) "control" else "sample",
        n_taxa = zms$n_taxa[k], n_reads = zms$n_reads[k],
        d_to_samples = NA_real_, d_to_controls = NA_real_,
        null_median = null_med, null_threshold = null_thr, null_n_pairs = null_n,
        power = "none_no_detections",
        confidence = "low",
        verdict = "no_detections", stringsAsFactors = FALSE)
    }
  }

  res <- do.call(rbind, out)
  sp  <- do.call(rbind, site_power)
  res <- res[order(res$site, res$label, res$column_id), , drop = FALSE]
  rownames(res) <- NULL
  attr(res, "site_power") <- sp

  n_ctl <- sum(res$label == "control")
  if (verbose) {
    message(sprintf("validate_controls: %d column(s) across %d site(s); %d control(s).",
                    nrow(res), nrow(sp), n_ctl))
    print(table(res$label, res$verdict))
    if (any(sp$power != "ok")) {
      message(sprintf("  %d of %d site(s) have reduced or no power: %s",
                      sum(sp$power != "ok"), nrow(sp),
                      paste(unique(sp$power[sp$power != "ok"]), collapse = ", ")))
      # Say this at RUN TIME, not only in the manual page. A clean-looking result
      # from a site that cannot test anything is the failure mode most likely to
      # be believed, and nobody reads ?validate_controls before reading the
      # console.
      message("  A SITE WITH TWO SAMPLES AND A SITE WITH TWENTY BOTH PRINT ",
              "'nothing flagged'. Read site_power and the per-row `confidence` ",
              "before treating a clean result as evidence of clean labels.")
    }
    if (sum(res$verdict == "untestable"))
      message(sprintf("  %d column(s) UNTESTABLE -- absence of a flag there is not ",
                      sum(res$verdict == "untestable")), "evidence of a clean label.")
    if (sum(res$verdict == "no_detections"))
      message(sprintf("  %d column(s) have NO DETECTIONS at all (every read 0 or NA) -- ",
                      sum(res$verdict == "no_detections")),
              "no composition to test; not evidence of a clean or contaminated label either way.")
  }
  # If every testable control looks like a sample, the control set is compromised
  # and any contaminant list built on it would filter real signal. A
  # no-detections control is excluded from "testable" for the same reason
  # untestable/untestable_no_headroom are: there is no evidence either way,
  # so it must not silently count as "not RESEMBLES_SAMPLE" here.
  testable <- res$label == "control" &
              !res$verdict %in% c("untestable", "untestable_no_headroom", "no_detections")
  if (sum(testable) && all(res$verdict[testable] == "RESEMBLES_SAMPLE"))
    warning("validate_controls: EVERY testable control resembles a field sample. ",
            "Treat the control set as compromised and do not build a contaminant ",
            "list from it until the labels are resolved.", call. = FALSE)
  res
}

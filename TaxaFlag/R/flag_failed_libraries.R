# Exports: flag_failed_libraries
# Internal helpers: .ffl_sample_effect, .ffl_n_other, .ffl_absent, .ffl_fmt,
#   .ffl_run_reason, .ffl_library_reason

#' Flag Sequencing Libraries and Runs That Failed
#'
#' Asks, before anything else is computed from a run, whether each library
#' actually sequenced. A library is one sample amplified with one marker; a
#' run is the set of libraries of one marker sequenced together. A failed
#' library looks like a sample with few species, and nothing downstream can
#' tell the difference: richness, occupancy and read shares all shrink, and
#' control checks such as \code{\link{validate_controls}} lose the power to
#' fail anything, which they report as a pass.
#'
#' @section Why failure is not "few reads":
#' A genuinely low-biomass sample can yield few reads, so a read-count floor
#' cannot tell a failed library from a sparse but valid sample. The evidence
#' that separates them is the SAME extract sequenced with OTHER markers. If a
#' sample yields 59,000 reads for one marker and 580 for another, the extract
#' was fine and the second library failed. If it is low in every marker, the
#' sample itself is sparse, which is a result, not a failure.
#'
#' @section Taxonomically narrow markers:
#' Cross-marker evidence shows that the EXTRACT was fine, not that the
#' marker's target taxa were present in it. For a marker that amplifies a
#' narrow group (12S for vertebrates, say), a sample with no such DNA looks
#' exactly like a failed library: low for its marker, fine in the others. On
#' such a marker read \code{"failed"} as "failed, or target absent". Agreement
#' among a sample's replicate libraries of the same marker is the evidence that
#' separates the two; this function does not use it, so check it before acting
#' on a scattered failure in a narrow marker.
#'
#' @section The test:
#' Depths are compared on a log10 scale. For each marker, the reference depth
#' is the median, over runs, of each run's median field-library depth; a
#' median of run medians, so one failed or unusually deep run does not define
#' normal. Each field library then gets two deviations:
#' \itemize{
#'   \item \strong{own-marker deviation}: its depth relative to its marker's
#'     reference.
#'   \item \strong{cross-marker residual}: its own-marker deviation minus the
#'     median own-marker deviation of the same sample's libraries in the OTHER
#'     markers. It is how far below this sample's other markers the library
#'     fell. Libraries judged failed in a first pass are left out of the
#'     second pass as predictors for the sample's other markers.
#' }
#' With \eqn{T = \log_{10}}(\code{fold_threshold}), a field library is:
#' \itemize{
#'   \item \code{"failed"} when BOTH deviations are at or below \eqn{-T}: it
#'     is low for its marker AND low relative to its own sample's other
#'     markers. Requiring both guards against a run on which the other
#'     markers were simply sequenced unusually deep.
#'   \item \code{"low_yield"} when it is low for its marker but the sample's
#'     other markers are comparably low: a sample-level cause (low biomass,
#'     poor extraction), not a library failure. Not excluded.
#'   \item \code{"low_yield_undetermined"} when it is low for its marker and
#'     the sample has no other marker to compare with. A single-marker rule
#'     cannot tell failure from low biomass, and this says so rather than
#'     guess. Not excluded, but reported.
#'   \item \code{"pass"} otherwise.
#'   \item \code{NA} (not assessed) for control libraries.
#' }
#'
#' @section Two granularities:
#' A run fails as a whole when a fault hits the library pool (chemistry,
#' loading, a demultiplexing error): every library on it is low. Reporting that
#' as dozens of individual failures would hide the single cause, so each run
#' (run x marker) also gets a verdict, in \code{attr(, "runs")}:
#' \itemize{
#'   \item \code{"failed"}: at least \code{run_fail_fraction} of its field
#'     libraries failed. Every library on the run, controls included, is
#'     excluded, and \code{failure_scope} is \code{"run"}.
#'   \item \code{"low_yield"}: at least \code{run_fail_fraction} of its field
#'     libraries are low for the marker, but without cross-marker support. The
#'     whole run is weak and the data cannot say why. Not excluded; read it.
#'   \item \code{"pass"}: neither. Individual failed libraries may still be
#'     present (\code{n_failed}); they are excluded one by one.
#'   \item \code{"not_testable"}: the marker has fewer than
#'     \code{min_reference_runs} runs and no \code{reference_depth}, so its
#'     reference IS this run and a whole-run failure cannot be seen.
#'     Individual libraries are still tested against the run. This is a
#'     distinct outcome from \code{"pass"}.
#' }
#'
#' @section Controls:
#' Blanks on a failed run are usually as depth-starved as the field libraries
#' and can be as rich or richer, and control-based tests then have no
#' contrast to work with. Each run reports \code{control_depth_ratio} and
#' \code{control_richness_ratio} (median control over median field library)
#' and \code{control_contrast}: \code{"collapsed"} when the richness ratio is
#' at least \code{control_contrast_max}, \code{"informative"} below it,
#' \code{"no_controls"} when the run has none. Richness, not depth, is the
#' informative ratio: sequencing providers often pool libraries to equal
#' depth, so a clean blank can carry as many reads as a field sample while
#' holding a fraction of its features. A collapsed contrast can also occur on
#' a run that sequenced normally, when its blanks carry field-like reads; it
#' is reported, never used to exclude anything.
#'
#' @section What to pass in:
#' Pass every marker of the study in one table: the cross-marker comparison
#' is the point, and it cannot be made one marker at a time. Include control
#' libraries and samples you do not intend to analyse. \code{sample_col}
#' must identify the physical extract that every marker was amplified from,
#' so that the same value appears under each marker.
#'
#' A library that sequenced nothing has no rows in a long table that keeps
#' only positive counts. Give it one zero-count row, or list it in
#' \code{expected_libraries}; otherwise it is invisible. Samples that have
#' libraries in some markers of a run but none at all in another marker of
#' the same run are listed in \code{attr(, "libraries_absent")}; they are not
#' given a verdict because the table cannot say whether the library was ever
#' made.
#'
#' @param input_df Long-format data frame, one row per feature x library.
#' @param library_col Character. Column identifying the sequenced library
#'   (a sample-replicate column). Default \code{"event_id"}.
#' @param sample_col Character. Column identifying the physical sample or
#'   extract shared across markers. Default \code{"sample_id"}.
#' @param marker_col Character. Column identifying the marker or assay.
#'   Default \code{"marker"}.
#' @param run_col Character. Column identifying the sequencing run (the pool
#'   sequenced together); runs are always taken within a marker. Default
#'   \code{"run"}.
#' @param count_col Character. Numeric count column. Default \code{"count"}.
#' @param taxon_col Character or NULL. Feature column, used for richness
#'   (features with a positive count). NULL skips richness and the control
#'   contrast. Default \code{"taxon_name"}.
#' @param control_samples Character vector of \code{library_col} or
#'   \code{sample_col} values that are negative controls. Controls are not
#'   given a library verdict; they feed the control contrast. Default NULL.
#' @param expected_libraries Optional data frame with the columns named by
#'   \code{library_col}, \code{sample_col}, \code{marker_col} and
#'   \code{run_col}: libraries known to have been sequenced. Any with no rows
#'   in \code{input_df} enter at depth 0. Default NULL.
#' @param fold_threshold Numeric > 1. How many times below expectation a
#'   library must be on BOTH deviations to fail. Default 10. On one real
#'   three-marker study the within-sample, cross-marker scatter of healthy
#'   libraries had a median absolute deviation of about 2.1-fold, so 10-fold
#'   sits about three of those out; two whole-run failures there sat
#'   100-fold low.
#' @param run_fail_fraction Numeric in (0, 1]. Share of a run's assessed
#'   field libraries that must fail (or be low, for \code{"low_yield"}) for
#'   the run verdict. Default 0.5.
#' @param min_reference_runs Integer. Runs a marker needs before its
#'   reference can expose a whole-run failure. Default 3.
#' @param reference_depth Optional named numeric vector, one typical
#'   field-library depth per marker (names = marker values). Overrides the
#'   data-derived reference for those markers; use it for a marker sequenced
#'   in fewer than \code{min_reference_runs} runs.
#' @param control_contrast_max Numeric. Control-over-field richness ratio at
#'   or above which the control contrast is reported \code{"collapsed"}.
#'   Default 0.5.
#' @param cleared_runs Character vector of \code{"<run>|<marker>"} keys a
#'   person has reviewed and chosen to analyse despite a \code{"failed"}
#'   verdict. The verdict is kept; only \code{exclude_library} changes, and
#'   the clearance is recorded in \code{attr(, "runs")}. Default NULL.
#' @param verbose Logical. Print a per-run summary. Default TRUE.
#'
#' @return \code{input_df} in its original row order with these columns added:
#' \describe{
#'   \item{\code{library_status}}{\code{"failed"}, \code{"low_yield"},
#'     \code{"low_yield_undetermined"}, \code{"pass"} or \code{NA} (control,
#'     not assessed); see The test.}
#'   \item{\code{library_reason}}{Plain-English explanation with the numbers.}
#'   \item{\code{run_status}}{The run verdict; see Two granularities.}
#'   \item{\code{exclude_library}}{Logical. TRUE for a failed library and for
#'     every library of a failed, uncleared run. The workflow should drop
#'     these rows from richness, occupancy and read-share summaries and say
#'     so in its output.}
#' }
#' Attribute \code{"libraries"}: one row per library with \code{depth},
#' \code{richness}, \code{role}, \code{own_dev} and \code{cross_resid}
#' (log10), \code{n_other_markers}, \code{library_status},
#' \code{failure_scope} (\code{"run"} or \code{"library"}) and
#' \code{exclude_library}. Attribute \code{"runs"}: one row per run x marker
#' with library counts by status, \code{median_depth},
#' \code{reference_depth}, \code{fold_below_reference},
#' \code{median_cross_resid}, \code{reference_basis} (\code{"runs"},
#' \code{"supplied"} or \code{"too_few_runs"}), \code{n_runs_marker}, the
#' control contrast columns,
#' \code{n_absent}, \code{run_status}, \code{cleared} and \code{reason}.
#' Attribute \code{"libraries_absent"}: sample x marker x run combinations
#' with no library although the sample has libraries in another marker of
#' that run.
#'
#' A warning names every failed run and library that is excluded and not
#' cleared: those rows should not be analysed until a person has looked.
#'
#' @seealso \code{\link{validate_controls}} and \code{\link{flag_contaminant}},
#'   whose output is uninformative on a failed run: run this first.
#'
#' @examples
#' # Three samples, two markers. Run B of marker "M2" failed: its libraries
#' # are far below both M2's other runs and the same samples' M1 libraries.
#' # Sample S9 is sparse in BOTH markers: low yield, not a failure.
#' set.seed(1)
#' libs <- expand.grid(sample_id = paste0("S", 1:9), marker = c("M1", "M2"),
#'                     stringsAsFactors = FALSE)
#' libs$run <- paste0(libs$marker, "_", c("A", "A", "A", "B", "B", "B", "C", "C", "C"))
#' libs$count <- round(40000 * exp(rnorm(nrow(libs), 0, 0.3)))
#' libs$count[libs$marker == "M2" & libs$run == "M2_B"] <- c(400, 350, 500)
#' libs$count[libs$sample_id == "S9"] <- c(900, 700)
#' libs$event_id <- paste(libs$sample_id, libs$marker, sep = ".")
#' res <- flag_failed_libraries(libs, taxon_col = NULL, min_reference_runs = 3)
#' attr(res, "runs")[, c("run", "marker", "run_status", "fold_below_reference")]
#' res[, c("event_id", "count", "library_status")]
#' @export
flag_failed_libraries <- function(input_df,
                                  library_col = "event_id",
                                  sample_col = "sample_id",
                                  marker_col = "marker",
                                  run_col = "run",
                                  count_col = "count",
                                  taxon_col = "taxon_name",
                                  control_samples = NULL,
                                  expected_libraries = NULL,
                                  fold_threshold = 10,
                                  run_fail_fraction = 0.5,
                                  min_reference_runs = 3L,
                                  reference_depth = NULL,
                                  control_contrast_max = 0.5,
                                  cleared_runs = NULL,
                                  verbose = TRUE) {
  # --- Input validation ---
  if (!is.data.frame(input_df)) stop("'input_df' must be a data frame.", call. = FALSE)
  cols <- c(library_col, sample_col, marker_col, run_col, count_col, taxon_col)
  for (col in cols) {
    if (!col %in% names(input_df)) {
      stop(sprintf("Column '%s' not found in input_df.", col), call. = FALSE)
    }
  }
  if (!is.numeric(input_df[[count_col]])) {
    stop(sprintf("Column '%s' must be numeric.", count_col), call. = FALSE)
  }
  if (!is.numeric(fold_threshold) || length(fold_threshold) != 1L ||
    is.na(fold_threshold) || fold_threshold <= 1) {
    stop("'fold_threshold' must be a single number > 1.", call. = FALSE)
  }
  if (!is.numeric(run_fail_fraction) || length(run_fail_fraction) != 1L ||
    is.na(run_fail_fraction) || run_fail_fraction <= 0 || run_fail_fraction > 1) {
    stop("'run_fail_fraction' must be a single number in (0, 1].", call. = FALSE)
  }
  if (!is.numeric(control_contrast_max) || length(control_contrast_max) != 1L ||
    is.na(control_contrast_max) || control_contrast_max <= 0) {
    stop("'control_contrast_max' must be a single positive number.", call. = FALSE)
  }
  if (!is.null(reference_depth) &&
    (!is.numeric(reference_depth) || is.null(names(reference_depth)) ||
      any(is.na(reference_depth)) || any(reference_depth <= 0))) {
    stop("'reference_depth' must be a named positive numeric vector (names = markers).",
      call. = FALSE
    )
  }
  if (any(is.na(input_df[[library_col]])) || any(is.na(input_df[[marker_col]])) ||
    any(is.na(input_df[[run_col]]))) {
    stop(sprintf("Columns '%s', '%s' and '%s' must not contain NA.",
      library_col, marker_col, run_col), call. = FALSE)
  }
  T_log <- log10(fold_threshold)

  # --- Aggregate to libraries ---
  d <- data.frame(
    marker = as.character(input_df[[marker_col]]),
    run = as.character(input_df[[run_col]]),
    library = as.character(input_df[[library_col]]),
    sample = as.character(input_df[[sample_col]]),
    reads = input_df[[count_col]],
    stringsAsFactors = FALSE
  )
  d$reads[is.na(d$reads)] <- 0
  if (any(d$reads < 0)) {
    stop(sprintf("Column '%s' has negative counts.", count_col), call. = FALSE)
  }
  d$key <- paste(d$marker, d$run, d$library, sep = "\r")
  first <- !duplicated(d$key)
  lib <- d[first, c("key", "marker", "run", "library", "sample")]
  n_samp <- tapply(d$sample, d$key, function(x) length(unique(x[!is.na(x)])))
  if (any(n_samp > 1L)) {
    stop(sprintf(
      "%d library(ies) map to more than one '%s' value within a marker and run, e.g. %s.",
      sum(n_samp > 1L), sample_col, gsub("\r", " / ", names(n_samp)[n_samp > 1L][1])
    ), call. = FALSE)
  }
  lib$depth <- as.numeric(tapply(d$reads, d$key, sum)[lib$key])
  lib$richness <- if (is.null(taxon_col)) {
    NA_real_
  } else {
    pos <- d$reads > 0
    feat <- paste(d$key, as.character(input_df[[taxon_col]]), sep = "\r")[pos]
    rich <- table(d$key[pos][!duplicated(feat)])
    r <- as.numeric(rich[lib$key])
    r[is.na(r)] <- 0
    r
  }
  lib$source <- "input"

  if (!is.null(expected_libraries)) {
    if (!is.data.frame(expected_libraries)) {
      stop("'expected_libraries' must be a data frame.", call. = FALSE)
    }
    for (col in c(library_col, sample_col, marker_col, run_col)) {
      if (!col %in% names(expected_libraries)) {
        stop(sprintf("Column '%s' not found in expected_libraries.", col), call. = FALSE)
      }
    }
    ex <- data.frame(
      marker = as.character(expected_libraries[[marker_col]]),
      run = as.character(expected_libraries[[run_col]]),
      library = as.character(expected_libraries[[library_col]]),
      sample = as.character(expected_libraries[[sample_col]]),
      stringsAsFactors = FALSE
    )
    ex$key <- paste(ex$marker, ex$run, ex$library, sep = "\r")
    ex <- ex[!ex$key %in% lib$key & !duplicated(ex$key), , drop = FALSE]
    if (nrow(ex)) {
      ex$depth <- 0
      ex$richness <- if (is.null(taxon_col)) NA_real_ else 0
      ex$source <- "expected_libraries"
      lib <- rbind(lib, ex[, names(lib)])
    }
  }

  is_ctl <- lib$library %in% control_samples |
    (!is.na(lib$sample) & lib$sample %in% control_samples)
  lib$role <- ifelse(is_ctl, "control", "field")
  if (!is.null(control_samples) && !any(is_ctl)) {
    warning("None of 'control_samples' matched a library or sample in input_df.",
      call. = FALSE
    )
  }
  lib$ld <- log10(pmax(lib$depth, 1))

  # --- Marker references: median over runs of the run's median field depth ---
  fld <- lib$role == "field"
  markers <- sort(unique(lib$marker))
  ref <- data.frame(marker = markers, stringsAsFactors = FALSE)
  run_med <- tapply(lib$ld[fld], paste(lib$marker[fld], lib$run[fld], sep = "\r"), stats::median)
  run_mk <- sub("\r.*$", "", names(run_med))
  ref$n_runs <- vapply(markers, function(m) sum(run_mk == m), integer(1))
  ref$ref_ld <- vapply(markers, function(m) {
    x <- run_med[run_mk == m]
    if (length(x)) stats::median(x) else NA_real_
  }, numeric(1))
  ref$basis <- ifelse(ref$n_runs >= min_reference_runs, "runs", "too_few_runs")
  sup <- intersect(names(reference_depth), markers)
  if (length(sup)) {
    ref$ref_ld[match(sup, ref$marker)] <- log10(reference_depth[sup])
    ref$basis[match(sup, ref$marker)] <- "supplied"
  }
  unknown <- setdiff(names(reference_depth), markers)
  if (length(unknown)) {
    warning("'reference_depth' names not found among markers: ",
      paste(unknown, collapse = ", "), call. = FALSE)
  }
  lib$ref_ld <- ref$ref_ld[match(lib$marker, ref$marker)]
  lib$own_dev <- lib$ld - lib$ref_ld

  # --- Cross-marker residuals, two passes ---
  lib$other <- .ffl_sample_effect(lib, usable = fld)
  lib$cross_resid <- lib$own_dev - lib$other
  fail1 <- fld & !is.na(lib$cross_resid) & lib$cross_resid <= -T_log & lib$own_dev <= -T_log
  lib$other <- .ffl_sample_effect(lib, usable = fld & !fail1)
  lib$cross_resid <- lib$own_dev - lib$other
  lib$n_other_markers <- .ffl_n_other(lib, usable = fld & !fail1)

  low <- lib$own_dev <= -T_log
  failed <- fld & !is.na(lib$cross_resid) & lib$cross_resid <= -T_log & low
  lib$library_status <- ifelse(!fld, NA_character_,
    ifelse(failed, "failed",
      ifelse(low & is.na(lib$cross_resid), "low_yield_undetermined",
        ifelse(low, "low_yield", "pass")
      )
    )
  )

  # --- Run verdicts ---
  rk <- paste(lib$run, lib$marker, sep = "|")
  lib$run_key <- rk
  runs <- unique(lib[, c("run", "marker", "run_key")])
  runs <- runs[order(runs$marker, runs$run), , drop = FALSE]
  absent <- .ffl_absent(lib)
  by_run <- function(fun) vapply(runs$run_key, function(k) fun(lib[rk == k, , drop = FALSE]), numeric(1))
  runs$n_field <- by_run(function(x) sum(x$role == "field"))
  runs$n_controls <- by_run(function(x) sum(x$role == "control"))
  runs$n_failed <- by_run(function(x) sum(x$library_status %in% "failed"))
  runs$n_low_yield <- by_run(function(x) sum(x$library_status %in% "low_yield"))
  runs$n_low_yield_undetermined <- by_run(function(x) sum(x$library_status %in% "low_yield_undetermined"))
  runs$median_depth <- by_run(function(x) {
    y <- x$depth[x$role == "field"]
    if (length(y)) stats::median(y) else NA_real_
  })
  runs$reference_depth <- round(10^ref$ref_ld[match(runs$marker, ref$marker)])
  runs$fold_below_reference <- round(runs$reference_depth / pmax(runs$median_depth, 1), 1)
  runs$median_cross_resid <- by_run(function(x) {
    y <- x$cross_resid[x$role == "field"]
    if (any(!is.na(y))) round(stats::median(y, na.rm = TRUE), 2) else NA_real_
  })
  runs$reference_basis <- ref$basis[match(runs$marker, ref$marker)]
  runs$n_runs_marker <- ref$n_runs[match(runs$marker, ref$marker)]
  ctl_med <- function(x, v) {
    y <- x[[v]][x$role == "control"]
    if (length(y)) stats::median(y) else NA_real_
  }
  fld_med <- function(x, v) {
    y <- x[[v]][x$role == "field"]
    if (length(y)) stats::median(y) else NA_real_
  }
  runs$control_depth_ratio <- by_run(function(x) round(ctl_med(x, "depth") / max(fld_med(x, "depth"), 1), 2))
  runs$control_richness_ratio <- by_run(function(x) round(ctl_med(x, "richness") / max(fld_med(x, "richness"), 1), 2))
  runs$control_contrast <- ifelse(runs$n_controls == 0, "no_controls",
    ifelse(is.na(runs$control_richness_ratio), NA_character_,
      ifelse(runs$control_richness_ratio >= control_contrast_max, "collapsed", "informative")
    )
  )
  runs$n_absent <- vapply(runs$run_key, function(k) sum(absent$run_key == k), integer(1))

  frac_fail <- runs$n_failed / pmax(runs$n_field, 1)
  frac_low <- (runs$n_failed + runs$n_low_yield + runs$n_low_yield_undetermined) / pmax(runs$n_field, 1)
  runs$run_status <- ifelse(runs$n_field == 0, "no_field_libraries",
    ifelse(frac_fail >= run_fail_fraction, "failed",
      ifelse(frac_low >= run_fail_fraction, "low_yield",
        ifelse(runs$reference_basis == "too_few_runs", "not_testable", "pass")
      )
    )
  )
  bad_clear <- setdiff(cleared_runs, runs$run_key)
  if (length(bad_clear)) {
    warning("'cleared_runs' keys not found (expected \"<run>|<marker>\"): ",
      paste(bad_clear, collapse = ", "), call. = FALSE)
  }
  runs$cleared <- runs$run_key %in% cleared_runs
  runs$reason <- .ffl_run_reason(runs, fold_threshold, run_fail_fraction, min_reference_runs)

  # --- Library gate and reasons ---
  lib$run_status <- runs$run_status[match(rk, runs$run_key)]
  run_failed <- lib$run_status == "failed"
  run_cleared <- runs$cleared[match(rk, runs$run_key)]
  lib$failure_scope <- ifelse(lib$library_status %in% "failed" | (run_failed & fld),
    ifelse(run_failed, "run", "library"), NA_character_
  )
  lib$exclude_library <- (lib$library_status %in% "failed" & !run_failed) |
    (run_failed & !run_cleared)
  lib$library_reason <- .ffl_library_reason(lib, fold_threshold)
  lib$cleared <- run_failed & run_cleared

  # --- Map back to rows ---
  m <- match(d$key, lib$key)
  out <- input_df
  out$library_status <- lib$library_status[m]
  out$library_reason <- lib$library_reason[m]
  out$run_status <- lib$run_status[m]
  out$exclude_library <- lib$exclude_library[m]

  lib_out <- lib[, c(
    "marker", "run", "library", "sample", "role", "source", "depth", "richness",
    "own_dev", "cross_resid", "n_other_markers", "library_status",
    "failure_scope", "run_status", "exclude_library", "cleared", "library_reason"
  )]
  lib_out$own_dev <- round(lib_out$own_dev, 3)
  lib_out$cross_resid <- round(lib_out$cross_resid, 3)
  rownames(lib_out) <- NULL
  runs_out <- runs[, setdiff(names(runs), "run_key")]
  rownames(runs_out) <- NULL
  absent$run_key <- NULL
  attr(out, "libraries") <- lib_out
  attr(out, "runs") <- runs_out
  attr(out, "libraries_absent") <- absent

  # --- Loud reporting ---
  if (verbose) {
    message(sprintf(
      "flag_failed_libraries: %d librar%s on %d run(s) x marker; %d failed run(s), %d failed librar%s outside them.",
      sum(fld), if (sum(fld) == 1) "y" else "ies", nrow(runs), sum(runs$run_status == "failed"),
      sum(lib$library_status %in% "failed" & !run_failed),
      if (sum(lib$library_status %in% "failed" & !run_failed) == 1) "y" else "ies"
    ))
    for (i in seq_len(nrow(runs))) {
      message(sprintf(
        "  %-10s %-8s %-18s %4d field | %3d failed | median %s reads (%sx below ref) | controls: %s",
        runs$marker[i], runs$run[i], runs$run_status[i], runs$n_field[i], runs$n_failed[i],
        .ffl_fmt(runs$median_depth[i]), runs$fold_below_reference[i],
        runs$control_contrast[i]
      ))
    }
  }
  fr <- runs$run_key[runs$run_status == "failed" & !runs$cleared]
  fl <- lib$key[lib$library_status %in% "failed" & !run_failed]
  if (length(fr) || length(fl)) {
    warning(sprintf(
      paste0(
        "DO NOT ANALYSE without review: %d failed run(s)%s and %d individually failed ",
        "librar%s are marked exclude_library = TRUE. Richness, occupancy, read shares and ",
        "control checks on them measure the failure, not the community. See attr(, \"runs\")."
      ),
      length(fr), if (length(fr)) paste0(" (", paste(fr, collapse = ", "), ")") else "",
      length(fl), if (length(fl) == 1) "y" else "ies"
    ), call. = FALSE)
  }
  out
}

#' Median own-marker deviation of each library's sample in the OTHER markers
#' @noRd
.ffl_sample_effect <- function(lib, usable) {
  ok <- usable & !is.na(lib$sample)
  sm <- tapply(lib$own_dev[ok], paste(lib$sample[ok], lib$marker[ok], sep = "\r"), mean)
  s_of <- sub("\r.*$", "", names(sm))
  m_of <- sub("^.*\r", "", names(sm))
  split_s <- split(seq_along(sm), s_of)
  vapply(seq_len(nrow(lib)), function(i) {
    s <- lib$sample[i]
    if (is.na(s) || is.null(split_s[[s]])) return(NA_real_)
    j <- split_s[[s]]
    j <- j[m_of[j] != lib$marker[i]]
    if (length(j)) stats::median(sm[j]) else NA_real_
  }, numeric(1))
}

#' Number of other markers with usable libraries for each library's sample
#' @noRd
.ffl_n_other <- function(lib, usable) {
  ok <- usable & !is.na(lib$sample)
  sm <- unique(data.frame(s = lib$sample[ok], m = lib$marker[ok], stringsAsFactors = FALSE))
  per <- split(sm$m, sm$s)
  vapply(seq_len(nrow(lib)), function(i) {
    if (is.na(lib$sample[i])) return(0L)
    x <- per[[lib$sample[i]]]
    if (is.null(x)) 0L else sum(x != lib$marker[i])
  }, integer(1))
}

#' Samples with libraries in one marker of a run but none in another marker of it
#' @noRd
.ffl_absent <- function(lib) {
  x <- unique(lib[!is.na(lib$sample), c("sample", "run", "marker")])
  if (!nrow(x)) {
    return(data.frame(sample = character(), run = character(), marker = character(),
      run_key = character(), stringsAsFactors = FALSE))
  }
  mk_in_run <- split(x$marker, x$run)
  out <- lapply(split(x, paste(x$sample, x$run, sep = "\r")), function(g) {
    miss <- setdiff(unique(mk_in_run[[g$run[1]]]), g$marker)
    if (!length(miss)) return(NULL)
    data.frame(sample = g$sample[1], run = g$run[1], marker = miss, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, out)
  if (is.null(out)) {
    return(data.frame(sample = character(), run = character(), marker = character(),
      run_key = character(), stringsAsFactors = FALSE))
  }
  out$run_key <- paste(out$run, out$marker, sep = "|")
  rownames(out) <- NULL
  out[order(out$marker, out$run, out$sample), , drop = FALSE]
}

#' @noRd
.ffl_fmt <- function(x) ifelse(is.na(x), "NA", format(round(x), big.mark = ",", trim = TRUE))

#' @noRd
.ffl_run_reason <- function(runs, fold_threshold, run_fail_fraction, min_reference_runs) {
  pct <- function(a, b) sprintf("%d of %d", as.integer(a), as.integer(b))
  vapply(seq_len(nrow(runs)), function(i) {
    r <- runs[i, ]
    base <- switch(r$run_status,
      no_field_libraries = "No field libraries on this run.",
      failed = sprintf(
        "%s field libraries are >= %gx below both the %s reference and their own samples' other markers; median depth %s vs reference %s.",
        pct(r$n_failed, r$n_field), fold_threshold, r$marker,
        .ffl_fmt(r$median_depth), .ffl_fmt(r$reference_depth)
      ),
      low_yield = sprintf(
        "%s field libraries are >= %gx below the %s reference, but the samples' other markers do not show the extracts were fine (low too, or absent). Cannot tell a failed run from uniformly sparse samples.",
        pct(r$n_failed + r$n_low_yield + r$n_low_yield_undetermined, r$n_field),
        fold_threshold, r$marker
      ),
      not_testable = sprintf(
        "%s has %d run(s), fewer than min_reference_runs = %d, and no reference_depth: its reference is this run itself, so a whole-run failure cannot be seen. Individual libraries were still tested.",
        r$marker, as.integer(r$n_runs_marker), as.integer(min_reference_runs)
      ),
      pass = if (r$n_failed > 0) {
        sprintf("%s field libraries failed individually and are excluded one by one.", pct(r$n_failed, r$n_field))
      } else {
        "No failed libraries."
      }
    )
    if (!is.na(r$control_contrast) && r$control_contrast == "collapsed") {
      base <- paste(base, sprintf(
        "Controls are as rich as the field (richness ratio %.2f): control-based checks on this run have no contrast.",
        r$control_richness_ratio
      ))
    }
    if (r$n_absent > 0) {
      base <- paste(base, sprintf(
        "%d sample(s) have libraries in other markers of this run but none in %s.",
        as.integer(r$n_absent), r$marker
      ))
    }
    if (isTRUE(r$cleared)) base <- paste(base, "Cleared for analysis by the user.")
    base
  }, character(1))
}

#' @noRd
.ffl_library_reason <- function(lib, fold_threshold) {
  fold <- function(x) sprintf("%.0fx", 10^(-x))
  vapply(seq_len(nrow(lib)), function(i) {
    x <- lib[i, ]
    if (x$role == "control") {
      return(if (x$run_status == "failed") "Control library on a failed run; excluded with it." else "Control library; not assessed.")
    }
    zero <- if (x$source == "expected_libraries") " (expected library with no reads in input)" else ""
    s <- switch(x$library_status,
      failed = sprintf(
        "%s reads%s: %s below the %s reference and %s below this sample's other markers.",
        .ffl_fmt(x$depth), zero, fold(x$own_dev), x$marker, fold(x$cross_resid)
      ),
      low_yield = sprintf(
        "%s reads: %s below the %s reference, but this sample's other markers are comparably low (%s apart): a sample-level cause such as low biomass, not a library failure.",
        .ffl_fmt(x$depth), fold(x$own_dev), x$marker,
        sprintf("%.1fx", 10^abs(x$cross_resid))
      ),
      low_yield_undetermined = sprintf(
        "%s reads: %s below the %s reference, and this sample has no other marker to compare with, so failure cannot be told from low biomass.",
        .ffl_fmt(x$depth), fold(x$own_dev), x$marker
      ),
      pass = "Within expectation."
    )
    if (x$run_status == "failed") {
      s <- paste(s, "Run failed as a whole; the cause is the run, not this library.")
    }
    s
  }, character(1))
}

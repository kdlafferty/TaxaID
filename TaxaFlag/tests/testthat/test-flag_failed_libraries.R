# Synthetic study: 3 markers x 4 runs x 6 samples; one library per sample x
# marker, each carrying `n_feat` features so richness is defined.
.ffl_study <- function(depth = 40000, n_feat = 20, seed = 1) {
  set.seed(seed)
  libs <- expand.grid(
    s = 1:6, run_i = 1:4, marker = c("M1", "M2", "M3"),
    stringsAsFactors = FALSE
  )
  libs$sample_id <- paste0("R", libs$run_i, "S", libs$s)
  libs$run <- paste0(libs$marker, "_run", libs$run_i)
  libs$event_id <- paste(libs$sample_id, libs$marker, "1", sep = ".")
  libs$depth <- round(depth * exp(stats::rnorm(nrow(libs), 0, 0.2)))
  libs$n_feat <- n_feat
  libs
}

.ffl_long <- function(libs) {
  rows <- lapply(seq_len(nrow(libs)), function(i) {
    k <- libs$n_feat[i]
    data.frame(
      event_id = libs$event_id[i], sample_id = libs$sample_id[i],
      marker = libs$marker[i], run = libs$run[i],
      taxon_name = paste0(libs$marker[i], "_f", seq_len(k)),
      count = if (libs$depth[i] == 0) 0 else as.numeric(stats::rmultinom(1, libs$depth[i], rep(1, k))),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

.ffl_run <- function(df, ...) {
  suppressMessages(flag_failed_libraries(df, verbose = FALSE, ...))
}

test_that("a whole-run failure is one run verdict, every library excluded", {
  libs <- .ffl_study()
  bad <- libs$run == "M2_run2"
  libs$depth[bad] <- 400
  libs$n_feat[bad] <- 3
  expect_warning(res <- .ffl_run(.ffl_long(libs)), "DO NOT ANALYSE")
  runs <- attr(res, "runs")
  expect_equal(runs$run_status[runs$run == "M2_run2"], "failed")
  expect_true(all(runs$run_status[runs$run != "M2_run2"] == "pass"))
  lib <- attr(res, "libraries")
  expect_true(all(lib$library_status[lib$run == "M2_run2"] == "failed"))
  expect_true(all(lib$failure_scope[lib$run == "M2_run2"] == "run"))
  expect_true(all(res$exclude_library[res$run == "M2_run2"]))
  expect_false(any(res$exclude_library[res$run != "M2_run2"]))
})

test_that("the other markers of a failed-run sample are not dragged down", {
  libs <- .ffl_study()
  libs$depth[libs$run == "M2_run2"] <- 400
  res <- suppressWarnings(.ffl_run(.ffl_long(libs)))
  lib <- attr(res, "libraries")
  same_samples <- lib$sample %in% lib$sample[lib$run == "M2_run2"] & lib$marker != "M2"
  expect_true(all(lib$library_status[same_samples] == "pass"))
})

test_that("a single failed library in a healthy run is excluded alone", {
  libs <- .ffl_study()
  i <- which(libs$run == "M3_run1" & libs$s == 2)
  libs$depth[i] <- 150
  expect_warning(res <- .ffl_run(.ffl_long(libs)), "1 individually failed library")
  lib <- attr(res, "libraries")
  hit <- lib$library == libs$event_id[i] & lib$marker == "M3"
  expect_equal(lib$library_status[hit], "failed")
  expect_equal(lib$failure_scope[hit], "library")
  expect_equal(attr(res, "runs")$run_status[attr(res, "runs")$run == "M3_run1"], "pass")
  expect_equal(sum(lib$exclude_library), 1L)
})

test_that("a sample sparse in every marker is low_yield, not failed", {
  libs <- .ffl_study()
  libs$depth[libs$sample_id == "R3S4"] <- 900
  res <- .ffl_run(.ffl_long(libs))
  lib <- attr(res, "libraries")
  x <- lib[lib$sample == "R3S4", ]
  expect_true(all(x$library_status == "low_yield"))
  expect_false(any(x$exclude_library))
  expect_match(x$library_reason[1], "low biomass")
})

test_that("a single-marker sample cannot be decided and says so", {
  libs <- .ffl_study()
  libs <- libs[!(libs$sample_id == "R1S1" & libs$marker != "M1"), ]
  libs$depth[libs$sample_id == "R1S1"] <- 200
  res <- .ffl_run(.ffl_long(libs))
  lib <- attr(res, "libraries")
  x <- lib[lib$sample == "R1S1", ]
  expect_equal(x$library_status, "low_yield_undetermined")
  expect_false(x$exclude_library)
  expect_true(is.na(x$cross_resid))
})

test_that("other markers sequenced unusually deep do not fail a normal library", {
  libs <- .ffl_study()
  deep <- libs$run_i == 1 & libs$marker != "M1"
  libs$depth[deep] <- libs$depth[deep] * 40
  res <- .ffl_run(.ffl_long(libs))
  lib <- attr(res, "libraries")
  expect_false(any(lib$library_status == "failed"))
  expect_true(all(lib$cross_resid[lib$run == "M1_run1"] < -1))
})

test_that("a run that is low with no cross-marker support is low_yield", {
  libs <- .ffl_study()
  libs <- libs[!(libs$run_i == 3 & libs$marker != "M2"), ]
  libs$depth[libs$run == "M2_run3"] <- 300
  res <- .ffl_run(.ffl_long(libs))
  runs <- attr(res, "runs")
  expect_equal(runs$run_status[runs$run == "M2_run3"], "low_yield")
  expect_false(any(res$exclude_library))
})

test_that("too few runs gives not_testable; reference_depth restores the test", {
  libs <- .ffl_study()
  libs <- libs[libs$run_i == 1, ]
  libs$depth[libs$marker == "M2"] <- 300
  res <- .ffl_run(.ffl_long(libs))
  runs <- attr(res, "runs")
  expect_true(all(runs$reference_basis == "too_few_runs"))
  expect_equal(runs$run_status[runs$marker == "M2"], "not_testable")
  expect_match(runs$reason[runs$marker == "M2"], "1 run")

  res2 <- suppressWarnings(.ffl_run(.ffl_long(libs),
    reference_depth = c(M1 = 40000, M2 = 40000, M3 = 40000)
  ))
  runs2 <- attr(res2, "runs")
  expect_equal(runs2$reference_basis[runs2$marker == "M2"], "supplied")
  expect_equal(runs2$run_status[runs2$marker == "M2"], "failed")
})

test_that("cleared_runs keeps the verdict but lifts the exclusion", {
  libs <- .ffl_study()
  libs$depth[libs$run == "M2_run2"] <- 400
  expect_no_warning(res <- .ffl_run(.ffl_long(libs), cleared_runs = "M2_run2|M2"))
  runs <- attr(res, "runs")
  expect_equal(runs$run_status[runs$run == "M2_run2"], "failed")
  expect_true(runs$cleared[runs$run == "M2_run2"])
  expect_false(any(res$exclude_library))
  w <- character()
  withCallingHandlers(.ffl_run(.ffl_long(libs), cleared_runs = "nope|M2"),
    warning = function(cnd) {
      w <<- c(w, conditionMessage(cnd))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("not found", w)))
  expect_true(any(grepl("DO NOT ANALYSE", w)))
})

test_that("an expected library with no rows enters at depth 0 and fails", {
  libs <- .ffl_study()
  df <- .ffl_long(libs)
  gone <- df$event_id == "R2S5.M3.1" & df$marker == "M3"
  df <- df[!gone, ]
  exp_lib <- data.frame(
    event_id = "R2S5.M3.1", sample_id = "R2S5", marker = "M3", run = "M3_run2"
  )
  expect_warning(res <- .ffl_run(df, expected_libraries = exp_lib), "DO NOT ANALYSE")
  lib <- attr(res, "libraries")
  x <- lib[lib$library == "R2S5.M3.1" & lib$marker == "M3", ]
  expect_equal(x$depth, 0)
  expect_equal(x$source, "expected_libraries")
  expect_equal(x$library_status, "failed")
  expect_match(x$library_reason, "expected library")
})

test_that("a library missing from one marker of a run is reported as absent", {
  libs <- .ffl_study()
  libs$run <- paste0("run", libs$run_i)
  df <- .ffl_long(libs)
  df <- df[!(df$sample_id == "R4S6" & df$marker == "M1"), ]
  res <- .ffl_run(df)
  ab <- attr(res, "libraries_absent")
  expect_equal(nrow(ab), 1L)
  expect_equal(ab$sample, "R4S6")
  expect_equal(ab$marker, "M1")
  runs <- attr(res, "runs")
  expect_equal(runs$n_absent[runs$run == "run4" & runs$marker == "M1"], 1L)
})

test_that("controls are unassessed and drive the control contrast", {
  libs <- .ffl_study()
  ctl <- data.frame(
    s = 7, run_i = 1, marker = c("M1", "M2", "M3"), sample_id = "BLANK1",
    run = c("M1_run1", "M2_run1", "M3_run1"),
    event_id = paste("BLANK1", c("M1", "M2", "M3"), "1", sep = "."),
    depth = 40000, n_feat = c(2, 20, 30)
  )
  res <- .ffl_run(.ffl_long(rbind(libs, ctl)), control_samples = "BLANK1")
  lib <- attr(res, "libraries")
  expect_true(all(is.na(lib$library_status[lib$sample == "BLANK1"])))
  runs <- attr(res, "runs")
  r <- runs[runs$run %in% c("M1_run1", "M2_run1", "M3_run1"), ]
  expect_equal(r$control_contrast[r$marker == "M1"], "informative")
  expect_equal(r$control_contrast[r$marker == "M2"], "collapsed")
  expect_equal(r$control_contrast[r$marker == "M3"], "collapsed")
  expect_true(all(runs$control_contrast[!runs$run %in% r$run] == "no_controls"))
})

test_that("controls on a failed run are excluded with it", {
  libs <- .ffl_study()
  libs$depth[libs$run == "M2_run2"] <- 400
  ctl <- data.frame(
    s = 7, run_i = 2, marker = "M2", sample_id = "BLANK2", run = "M2_run2",
    event_id = "BLANK2.M2.1", depth = 500, n_feat = 3
  )
  res <- suppressWarnings(.ffl_run(.ffl_long(rbind(libs, ctl)), control_samples = "BLANK2"))
  expect_true(all(res$exclude_library[res$sample_id == "BLANK2"]))
})

test_that("row order and original columns are preserved", {
  df <- .ffl_long(.ffl_study())
  df <- df[sample(nrow(df)), ]
  res <- .ffl_run(df)
  expect_identical(res[, names(df)], df)
  expect_true(all(c("library_status", "library_reason", "run_status", "exclude_library") %in% names(res)))
})

test_that("taxon_col = NULL skips richness", {
  libs <- .ffl_study()
  df <- .ffl_long(libs)
  res <- .ffl_run(df, taxon_col = NULL)
  expect_true(all(is.na(attr(res, "libraries")$richness)))
})

test_that("input validation", {
  df <- .ffl_long(.ffl_study())
  expect_error(flag_failed_libraries("x"), "data frame")
  expect_error(flag_failed_libraries(df, run_col = "nope"), "not found")
  expect_error(flag_failed_libraries(df, fold_threshold = 1), "> 1")
  expect_error(flag_failed_libraries(df, run_fail_fraction = 0), "\\(0, 1\\]")
  expect_error(flag_failed_libraries(df, reference_depth = c(40000)), "named")
  bad <- df
  bad$count[1] <- -1
  expect_error(flag_failed_libraries(bad, verbose = FALSE), "negative")
  two <- df
  two$sample_id[two$event_id == "R1S1.M1.1"][1] <- "OTHER"
  expect_error(flag_failed_libraries(two, verbose = FALSE), "more than one")
})

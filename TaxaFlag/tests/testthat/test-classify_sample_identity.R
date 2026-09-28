.sig_run <- function(d, ..., blanks = c("CLEAN", "MISLABEL", "PLANKTON")) {
  suppressWarnings(classify_sample_identity(d, control_samples = blanks,
    taxon_label_col = "species", verbose = FALSE, on_pending = "ignore", ...))
}

.unit <- function(res, s, m) {
  u <- attr(res, "units")
  u[u$sample == s & u$marker == m, , drop = FALSE]
}

test_that("each cell of the label x appearance matrix is reached", {
  res <- .sig_run(.sig_fixture())
  expect_equal(.unit(res, "CLEAN", "M1")$identity_status, "concordant")
  expect_equal(.unit(res, "CLEAN", "M1")$identity_appearance, "valid_blank")
  expect_equal(.unit(res, "MISLABEL", "M1")$identity_appearance, "valid_sample")
  expect_equal(.unit(res, "MISLABEL", "M1")$identity_status, "discordant")
  # disjoint from the field, so composition calls it clean; diversity does not
  expect_equal(.unit(res, "PLANKTON", "M1")$identity_appearance, "neither")
  expect_equal(.unit(res, "PLANKTON", "M1")$identity_status, "suspect")
  expect_true(all(attr(res, "units")$identity_status[grepl("^S", attr(res, "units")$sample)] == "concordant"))
})

test_that("only concordant units are admitted, in their labelled role", {
  res <- .sig_run(.sig_fixture())
  u <- attr(res, "units")
  expect_true(all(u$admit == (u$identity_status == "concordant")))
  expect_equal(unique(u$admit_as[u$sample == "CLEAN"]), "control")
  expect_true(all(is.na(u$admit_as[u$sample %in% c("MISLABEL", "PLANKTON")])))
  # row-level gate follows the unit gate
  expect_false(any(res$admit[res$sample_id == "MISLABEL"]))
  expect_true(all(res$admit[res$sample_id == "CLEAN"]))
  expect_equal(nrow(res), nrow(.sig_fixture()))
})

test_that("cross-marker agreement is counted per tube", {
  res <- .sig_run(.sig_fixture())
  x <- .unit(res, "MISLABEL", "M2")
  expect_equal(x$n_markers_flagged, 2L)
  expect_equal(x$n_markers_assessable, 2L)
  expect_equal(.unit(res, "CLEAN", "M1")$n_markers_flagged, 0L)
})

test_that("an identity flag in one marker holds the tube's other markers", {
  d <- .sig_fixture()
  # make PLANKTON look clean in M1 only
  d <- d[!(d$sample_id == "PLANKTON" & d$marker == "M1"), ]
  d <- rbind(d, data.frame(sample_id = "PLANKTON", marker = "M1", run = "R3",
    event_id = "PLANKTON.1", taxon_name = "M1_lab_human", species = "lab_human",
    count = 300, stringsAsFactors = FALSE))
  res <- .sig_run(d)
  m1 <- .unit(res, "PLANKTON", "M1")
  expect_equal(m1$identity_status, "concordant")
  expect_true(m1$tube_flagged)
  expect_true(m1$pending_review)
  expect_false(m1$admit)
  expect_match(m1$reason, "HELD")
  expect_equal(m1$hold_reason, "tube")
  expect_equal(.unit(res, "PLANKTON", "M2")$hold_reason, "own_evidence")
  # a tube-held unit is not counted as a flag of its own
  expect_equal(m1$n_markers_flagged, 1L)
})

test_that("an empty or near-empty blank is a valid blank, never a failure", {
  d <- .sig_fixture()
  d$count[d$sample_id == "CLEAN"] <- 1
  res <- .sig_run(d)
  expect_equal(.unit(res, "CLEAN", "M2")$identity_status, "concordant")
})

test_that("a blank on a failed run is unassessable, never concordant", {
  d <- .sig_fixture(fail_run = "R1")
  ff <- suppressWarnings(flag_failed_libraries(d, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
    verbose = FALSE))
  expect_equal(attr(ff, "runs")$run_status[attr(ff, "runs")$run == "R1" & attr(ff, "runs")$marker == "M2"], "failed")
  res <- .sig_run(d, failed_libraries = ff)
  b <- .unit(res, "CLEAN", "M2")
  expect_equal(b$identity_status, "unassessable")
  expect_false(b$admit)
  # the failure says nothing about the tube's other marker
  expect_true(.unit(res, "CLEAN", "M1")$admit)
  expect_false(.unit(res, "CLEAN", "M1")$tube_flagged)
  # failed field libraries: suspect, library issue, excluded but not pending
  s <- .unit(res, "S11", "M2")
  expect_equal(s$identity_status, "suspect")
  expect_equal(s$issue_type, "library")
  expect_false(s$admit)
  expect_false(s$pending_review)
  expect_true(.unit(res, "S11", "M1")$admit)
  # and the run is reported as having no admitted control
  rr <- attr(res, "runs")
  expect_equal(rr$control_status[rr$marker == "M2" & rr$run == "R1"], "no_admitted_control")
})

test_that("a run with no admitted control warns loudly", {
  d <- .sig_fixture(fail_run = "R1")
  w <- testthat::capture_warnings(
    classify_sample_identity(d, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
      verbose = FALSE, on_pending = "ignore"))
  expect_true(any(grepl("NONE admitted", w)))
})

test_that("unassessable_policy = 'block' also holds unassessable samples", {
  u <- data.frame(unit = "a", sample = "a", marker = "M", run = "R",
    identity_label = "sample", identity_status = "unassessable", issue_type = "identity",
    reason = "", stringsAsFactors = FALSE)
  asym <- .sig_apply_decisions(u, NULL, "asymmetric")
  blk <- .sig_apply_decisions(u, NULL, "block")
  expect_true(asym$admit)
  expect_false(blk$admit)
  u$identity_label <- "blank"
  expect_false(.sig_apply_decisions(u, NULL, "asymmetric")$admit)
})

test_that("on_pending = 'error' stops the run", {
  expect_error(
    suppressWarnings(classify_sample_identity(.sig_fixture(),
      control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
      verbose = FALSE, on_pending = "error")),
    "NOT admitted"
  )
})

test_that("the decision record round-trips and dispositions take effect", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  d <- .sig_fixture()
  .sig_run(d, decisions_path = path)
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  expect_true(all(c("MISLABEL", "PLANKTON") %in% rec$sample))
  expect_false("CLEAN" %in% rec$sample)
  expect_true(all(c("disposition", "reviewer", "note") %in% names(rec)))

  rec$disposition[rec$sample == "MISLABEL" & rec$marker == "M1"] <- "reassign_to_sample"
  rec$disposition[rec$sample == "PLANKTON" & rec$marker == "M1"] <- "exclude_tube"
  rec$note[rec$sample == "MISLABEL"] <- "field sheet shows bag swap"
  utils::write.csv(rec, path, row.names = FALSE, na = "")

  res <- .sig_run(d, decisions_path = path)
  u <- attr(res, "units")
  # identity decisions apply to the whole tube, across markers
  expect_true(all(u$admit[u$sample == "MISLABEL"]))
  expect_equal(unique(u$admit_as[u$sample == "MISLABEL"]), "sample")
  expect_false(any(u$admit[u$sample == "PLANKTON"]))
  expect_false(any(u$pending_review))
  # the user's note survives the rewrite; evidence is pinned at decision time
  rec2 <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  expect_equal(unique(rec2$note[rec2$sample == "MISLABEL"]), "field sheet shows bag swap")
  expect_equal(rec2$status_at_decision[rec2$sample == "MISLABEL" & rec2$marker == "M1"], "discordant")
})

test_that("keep_library lifts a library failure for that unit only", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  d <- .sig_fixture(fail_run = "R1")
  .sig_run(d, decisions_path = path)
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  k <- rec$sample == "S11" & rec$marker == "M2"
  expect_equal(rec$suggested_disposition[k], "exclude_library")
  rec$disposition[k] <- "keep_library"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  res <- .sig_run(d, decisions_path = path)
  expect_true(.unit(res, "S11", "M2")$admit)
  expect_true(all(res$admit[res$sample_id == "S11" & res$marker == "M2"]))
  expect_false(.unit(res, "S12", "M2")$admit)
})

test_that("bad decision records are refused", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  d <- .sig_fixture()
  .sig_run(d, decisions_path = path)
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  rec$disposition[1] <- "looks_fine"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  expect_error(.sig_run(d, decisions_path = path), "unknown disposition")

  rec$disposition <- NA
  rec$disposition[rec$sample == "MISLABEL"] <- c("confirm_blank", "reassign_to_sample")
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  expect_error(.sig_run(d, decisions_path = path), "Conflicting identity dispositions")
})

test_that("a decision made against different evidence is reported", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  d <- .sig_fixture()
  .sig_run(d, decisions_path = path)
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  k <- rec$sample == "MISLABEL" & rec$marker == "M1"
  rec$disposition[k] <- "confirm_blank"
  rec$identity_status[k] <- "suspect"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  w <- testthat::capture_warnings(
    classify_sample_identity(d, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
      decisions_path = path, verbose = FALSE, on_pending = "ignore"))
  expect_true(any(grepl("evidence that has since changed", w)))
})

test_that("input validation", {
  d <- .sig_fixture()
  expect_error(classify_sample_identity(d, verbose = FALSE), "control_samples")
  expect_error(classify_sample_identity(d, control_samples = "CLEAN", taxon_col = "nope",
    verbose = FALSE), "not found")
  d2 <- d
  d2$sample_id[1] <- NA
  expect_error(classify_sample_identity(d2, control_samples = "CLEAN", verbose = FALSE), "must not contain NA")
  expect_error(classify_sample_identity(d, control_samples = "CLEAN", diversity_blank_max = -1,
    verbose = FALSE), "diversity_blank_max")
  expect_error(classify_sample_identity(d, control_samples = "CLEAN",
    failed_libraries = d, verbose = FALSE), "unmodified result")
})

test_that("a single-marker failed run is caught although its libraries read low_yield_undetermined", {
  d <- .sig_fixture(fail_run = "R1")
  d <- d[d$marker == "M2", ]
  ff <- suppressWarnings(flag_failed_libraries(d, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
    verbose = FALSE))
  rr <- attr(ff, "runs")
  expect_equal(rr$run_status[rr$run == "R1"], "failed")
  lib <- attr(ff, "libraries")
  expect_true(all(lib$library_status[lib$run == "R1" & lib$role == "field"] == "low_yield_undetermined"))
  res <- .sig_run(d, failed_libraries = ff)
  s <- .unit(res, "S11", "M2")
  expect_equal(s$identity_status, "suspect")
  expect_equal(s$issue_type, "library")
  expect_false(s$admit)
  expect_equal(.unit(res, "CLEAN", "M2")$identity_status, "unassessable")
  expect_true(.unit(res, "S21", "M2")$admit)
})

test_that("a positive control recorded as a blank can be re-roled", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  d <- .sig_fixture()
  .sig_run(d, decisions_path = path)
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  rec$disposition[rec$sample == "PLANKTON" & rec$marker == "M1"] <- "reassign_to_positive_control"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  res <- .sig_run(d, decisions_path = path)
  u <- attr(res, "units")
  expect_equal(unique(u$admit_as[u$sample == "PLANKTON"]), "positive_control")
  expect_true(all(u$admit[u$sample == "PLANKTON"]))
  # it does not count as an admitted negative control
  rr <- attr(res, "runs")
  expect_equal(rr$n_admitted_controls[rr$run == "R3"], c(0L, 0L))
})

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

test_that("a blank on a failed run is untested (uncomparable), never concordant", {
  d <- .sig_fixture(fail_run = "R1")
  ff <- suppressWarnings(flag_failed_libraries(d, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
    verbose = FALSE))
  expect_equal(attr(ff, "runs")$run_status[attr(ff, "runs")$run == "R1" & attr(ff, "runs")$marker == "M2"], "failed")
  res <- .sig_run(d, failed_libraries = ff)
  b <- .unit(res, "CLEAN", "M2")
  expect_equal(b$identity_status, "untested")
  expect_equal(b$identity_status_reason, "uncomparable")
  # admitted by default (no evidence of a problem), held under "hold_blanks"
  expect_true(b$admit)
  held <- .sig_run(d, failed_libraries = ff, untested_policy = "hold_blanks")
  expect_false(.unit(held, "CLEAN", "M2")$admit)
  rr <- attr(held, "runs")
  expect_equal(rr$control_status[rr$marker == "M2" & rr$run == "R1"], "no_admitted_control")
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
})

test_that("a run with no admitted control warns loudly", {
  d <- .sig_fixture(fail_run = "R1")
  w <- testthat::capture_warnings(
    classify_sample_identity(d, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
      untested_policy = "hold_blanks", verbose = FALSE, on_pending = "ignore"))
  expect_true(any(grepl("NONE admitted", w)))
})

test_that("untested_policy decides what happens to untested and inconclusive units", {
  u <- data.frame(unit = c("a", "b"), sample = c("a", "b"), marker = "M", run = "R",
    identity_label = c("sample", "blank"), identity_status = c("untested", "inconclusive"),
    issue_type = NA_character_, reason = "", stringsAsFactors = FALSE)
  adm <- .sig_apply_decisions(u, NULL, "admit")
  hb <- .sig_apply_decisions(u, NULL, "hold_blanks")
  blk <- .sig_apply_decisions(u, NULL, "block")
  expect_equal(adm$admit, c(TRUE, TRUE))
  expect_equal(hb$admit, c(TRUE, FALSE))
  expect_equal(blk$admit, c(FALSE, FALSE))
  expect_equal(blk$hold_reason, c("untested", "inconclusive"))
  expect_false(any(adm$pending_review))
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
  expect_equal(.unit(res, "CLEAN", "M2")$identity_status, "untested")
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

test_that("a common field taxon that does not dominate the blanks is NOT set aside", {
  d <- .sig_fixture()
  add <- unique(d[d$marker == "M1" & grepl("^S", d$sample_id), c("sample_id", "marker", "run", "event_id")])
  add$taxon_name <- "M1_common"; add$species <- "COMMON"; add$count <- 3000
  res <- .sig_run(rbind(d, add))
  rr <- attr(res, "runs")
  expect_false(any(grepl("COMMON", rr$ubiquitous_taxa), na.rm = TRUE))
})

test_that("a spike-in present in every field unit is reported per run", {
  d <- .sig_fixture()
  add <- unique(d[d$marker == "M1", c("sample_id", "marker", "run", "event_id")])
  add$taxon_name <- "M1_spike"; add$species <- "SPIKE"
  add$count <- ifelse(add$sample_id %in% c("CLEAN", "MISLABEL", "PLANKTON"), 50000, 500)
  res <- .sig_run(rbind(d, add))
  rr <- attr(res, "runs")
  expect_true(all(grepl("SPIKE", rr$ubiquitous_taxa[rr$marker == "M1"])))
  expect_false(any(grepl("SPIKE", rr$ubiquitous_taxa[rr$marker == "M2"]), na.rm = TRUE))
})

test_that("a spike-only blank on a spiked run is a clean blank", {
  d <- .sig_fixture()
  add <- unique(d[, c("sample_id", "marker", "run", "event_id")])
  add$taxon_name <- paste0(add$marker, "_spike"); add$species <- "SPIKE"
  add$count <- ifelse(add$sample_id %in% c("CLEAN", "MISLABEL", "PLANKTON"), 20000, 6000)
  d <- rbind(d, add)
  # CLEAN now holds almost nothing but the spike
  d <- d[!(d$sample_id == "CLEAN" & d$species != "SPIKE"), ]
  res <- .sig_run(d)
  expect_equal(.unit(res, "CLEAN", "M1")$identity_status, "concordant")
  expect_true(.unit(res, "CLEAN", "M1")$admit)
  # the other verdicts do not move
  expect_equal(.unit(res, "MISLABEL", "M1")$identity_status, "discordant")
  expect_equal(.unit(res, "PLANKTON", "M1")$identity_status, "suspect")
  # the spike stays visible
  expect_match(.unit(res, "CLEAN", "M1")$top_taxa, "SPIKE")
  # and NULL keeps every feature
  expect_error(.sig_run(d, ubiquitous_fraction = 2), "ubiquitous_fraction")
})

test_that("a study with no labelled blanks is analysed, every unit untested (no_blanks)", {
  d <- .sig_fixture()
  d <- d[!d$sample_id %in% c("CLEAN", "MISLABEL", "PLANKTON"), ]
  w <- testthat::capture_warnings(
    res <- classify_sample_identity(d, taxon_label_col = "species",
      verbose = FALSE, on_pending = "ignore"))
  expect_true(any(grepl("No labelled controls", w)))
  u <- attr(res, "units")
  expect_true(all(u$identity_status == "untested"))
  expect_true(all(u$identity_status_reason == "no_blanks"))
  expect_true(all(u$admit))
  expect_true(all(res$admit))
})

test_that("a run with no blank leaves its samples untested, not concordant", {
  d <- .sig_fixture()
  d <- d[!(d$sample_id == "CLEAN"), ]   # run R1 now has no blank
  res <- .sig_run(d, blanks = c("MISLABEL", "PLANKTON"))
  s11 <- .unit(res, "S11", "M1")
  expect_equal(s11$identity_status, "untested")
  expect_equal(s11$identity_status_reason, "no_blanks")
  expect_true(s11$admit)
})

test_that("a run-wide artifact warns; a declared spike does not", {
  d <- .sig_fixture()
  add <- unique(d[d$marker == "M1", c("sample_id", "marker", "run", "event_id")])
  add$taxon_name <- "M1_pc"; add$species <- "PositiveControl"
  add$count <- ifelse(add$sample_id %in% c("CLEAN", "MISLABEL", "PLANKTON"), 50000, 500)
  d2 <- rbind(d, add)
  w <- testthat::capture_warnings(
    res <- classify_sample_identity(d2, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
      taxon_label_col = "species", verbose = FALSE, on_pending = "ignore"))
  expect_true(any(grepl("Run-wide artifact", w)))
  expect_false(any(grepl("spike-in, so", w)))
  rr <- attr(res, "runs")
  expect_true(all(grepl("PositiveControl", rr$run_wide_artifacts[rr$marker == "M1"])))
  w2 <- testthat::capture_warnings(
    res2 <- classify_sample_identity(d2, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
      taxon_label_col = "species", spike_taxa = "PositiveControl",
      verbose = FALSE, on_pending = "ignore"))
  expect_false(any(grepl("Run-wide artifact", w2)))
  rr2 <- attr(res2, "runs")
  expect_true(all(is.na(rr2$run_wide_artifacts)))
  expect_true(all(grepl("PositiveControl", rr2$declared_spikes[rr2$marker == "M1"])))
})

test_that("accept_llm_roles admits on llm_role where no person has decided", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  d <- .sig_fixture()
  .sig_run(d, decisions_path = path)
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  rec$llm_role <- ifelse(rec$sample == "MISLABEL", "sample",
    ifelse(rec$sample == "PLANKTON", "blank", NA))
  # a person overrides the LLM for PLANKTON
  rec$disposition[rec$sample == "PLANKTON" & rec$marker == "M1"] <- "exclude_tube"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  off <- attr(.sig_run(d, decisions_path = path), "units")
  expect_false(any(off$admit[off$sample == "MISLABEL"]))
  on <- attr(.sig_run(d, decisions_path = path, accept_llm_roles = TRUE), "units")
  m <- on[on$sample == "MISLABEL", ]
  expect_true(all(m$admit))
  expect_equal(unique(m$admit_as), "sample")
  expect_equal(unique(m$disposition_source), "llm")
  p <- on[on$sample == "PLANKTON", ]
  expect_false(any(p$admit))
  expect_equal(unique(p$disposition_source), "user")
})

test_that("the pending warning separates tube holds from a unit's own evidence", {
  w <- capture_warnings(res <- classify_sample_identity(.sig_fixture(),
    control_samples = c("CLEAN", "MISLABEL", "PLANKTON"), taxon_label_col = "species",
    verbose = FALSE))
  u <- attr(res, "units")
  expect_true("identity_status_reason" %in% names(u))
  expect_false("status_reason" %in% names(u))
  expect_true("identity_status_reason" %in% names(attr(res, "review_queue")))
  pw <- grep("await an identity decision", w, value = TRUE)
  expect_true(any(u$pending_review))
  if (any(u$pending_review)) {
    expect_length(pw, 1L)
    expect_match(pw, sprintf("%d on their own evidence", sum(u$pending_review & !u$hold_reason %in% "tube")))
    if (any(u$pending_review & u$hold_reason %in% "tube"))
      expect_match(pw, "held only because another marker of the same tube was flagged")
  }
})

.one_marker_dirty <- function() {
  d <- .sig_fixture()
  d <- d[!(d$sample_id == "CLEAN" & d$marker == "M2"), ]
  set.seed(7)
  f <- paste0("p", 1:60)
  w <- stats::rlnorm(60)
  rbind(d, data.frame(sample_id = "CLEAN", marker = "M2", run = "R1", event_id = "CLEAN.1",
    taxon_name = paste("M2", f, sep = "_"), species = f, count = pmax(1, round(20000 * w / sum(w))),
    stringsAsFactors = FALSE))
}

test_that("identity is per tube but control usability is per marker", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  d <- .one_marker_dirty()
  res <- .sig_run(d, decisions_path = path)
  expect_true(.unit(res, "CLEAN", "M2")$identity_status %in% c("suspect", "discordant"))
  expect_equal(.unit(res, "CLEAN", "M1")$identity_status, "concordant")
  # the tube is held until its identity is decided
  expect_true(all(.unit(res, "CLEAN", "M1")$pending_review, .unit(res, "CLEAN", "M2")$pending_review))
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  rec$disposition[rec$sample == "CLEAN" & rec$marker == "M1"] <- "confirm_blank"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  res <- .sig_run(d, decisions_path = path)
  m1 <- .unit(res, "CLEAN", "M1"); m2 <- .unit(res, "CLEAN", "M2")
  # confirmed a blank: the clean marker is a control, the contaminated one is not
  expect_true(m1$admit); expect_equal(m1$admit_as, "control"); expect_equal(m1$control_usability, "usable")
  expect_false(m2$admit); expect_equal(m2$control_usability, "contaminated_in_marker")
  expect_false(m2$pending_review)
  expect_match(m2$reason, "NOT A CONTROL IN THIS MARKER")
  expect_false(any(res$admit[res$sample_id == "CLEAN" & res$marker == "M2"]))
  # a person can keep it
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  rec$disposition[rec$sample == "CLEAN" & rec$marker == "M2"] <- "keep_library"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  res <- .sig_run(d, decisions_path = path)
  expect_true(.unit(res, "CLEAN", "M2")$admit)
  expect_equal(.unit(res, "CLEAN", "M2")$control_usability, "kept_by_decision")
})

test_that("sample_viability separates viable, thin-or-failed, and leaves controls NA", {
  res <- .sig_run(.sig_fixture(fail_run = "R1"))
  u <- attr(res, "units")
  expect_equal(.unit(res, "S21", "M1")$sample_viability, "viable")
  expect_equal(.unit(res, "S11", "M2")$sample_viability, "non_viable")
  expect_true(all(is.na(u$sample_viability[u$identity_label == "blank"])))
  expect_true(all(u$sample_viability[!is.na(u$sample_viability)] %in% c("viable", "thin", "non_viable")))
  # thin = low yield with normal composition, when the detector says low_yield
  ly <- u$library_status %in% c("low_yield", "low_yield_undetermined") & u$identity_label == "sample" &
    !(u$n_libraries_kept == 0)
  expect_true(all(u$sample_viability[ly] == "thin"))
  expect_true(all(c("control_usability", "sample_viability") %in% names(res)))
})

test_that("dominance is reported per unit with run-wide artifacts set aside", {
  res <- .sig_run(.sig_fixture())
  u <- attr(res, "units")
  expect_true(all(c("top_taxon", "top_taxon_share") %in% names(u)))
  expect_true(all(u$top_taxon_share > 0 & u$top_taxon_share <= 1, na.rm = TRUE))
  # CLEAN carries two lab taxa: the top one holds at least half its reads
  cl <- .unit(res, "CLEAN", "M1")
  expect_true(cl$top_taxon %in% c("lab_human", "lab_fungus"))
  expect_gte(cl$top_taxon_share, 0.5)
  # a feature in every tube of a run is an artifact, so it never counts as dominant
  d <- .sig_fixture()
  art <- unique(d[d$run == "R2", c("sample_id", "marker", "run", "event_id")])
  art$taxon_name <- paste(art$marker, "SPIKE", sep = "_"); art$species <- "SPIKE"
  art$count <- ifelse(art$sample_id == "MISLABEL", 200000, 5000)
  d2 <- rbind(d, art[, names(d)])
  res2 <- suppressWarnings(classify_sample_identity(d2, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
    taxon_label_col = "species", verbose = FALSE, on_pending = "ignore", spike_taxa = "SPIKE"))
  expect_false(any(attr(res2, "units")$top_taxon %in% "SPIKE"))
})

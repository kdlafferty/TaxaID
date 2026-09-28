# Simulated run with a KNOWN spillover rate. Each field sample carries its own
# genuine community; every feature then spills Poisson(r * source / (n - 1))
# reads into every other sample, controls included -- the "equal" receiver
# model. Genuine and spilled reads are tracked separately so each verdict can be
# checked against the truth.
.sim_run <- function(r = 0.002, n_field = 20, n_ctl = 4, n_feat = 60,
                     run = "R1", seed = 1, contaminant = FALSE) {
  set.seed(seed)
  samples <- c(sprintf("%s_S%02d", run, seq_len(n_field)), sprintf("%s_B%d", run, seq_len(n_ctl)))
  feats <- sprintf("f%02d", seq_len(n_feat))
  genuine <- matrix(0, n_feat, length(samples), dimnames = list(feats, samples))
  abund <- round(10^stats::runif(n_feat, 2, 5.5))
  for (j in seq_len(n_field)) {
    present <- sample(n_feat, 12)
    genuine[present, j] <- stats::rpois(12, abund[present] / 4)
  }
  if (contaminant) genuine["f01", (n_field + 1):length(samples)] <- 5000
  src_tot <- rowSums(genuine)
  n <- length(samples)
  spill <- matrix(0, n_feat, n, dimnames = dimnames(genuine))
  for (j in seq_len(n)) {
    spill[, j] <- stats::rpois(n_feat, r * (src_tot - genuine[, j]) / (n - 1))
  }
  obs <- genuine + spill
  df <- data.frame(
    event_id = rep(samples, each = n_feat),
    taxon_name = rep(feats, times = n),
    count = as.vector(obs),
    genuine = as.vector(genuine),
    run = run,
    stringsAsFactors = FALSE
  )
  # keep controls even when empty: a clean blank must still be present (see roxygen)
  df <- df[df$count > 0 | (df$event_id %in% samples[(n_field + 1):n] & df$taxon_name == feats[1]), ]
  attr(df, "controls") <- samples[(n_field + 1):n]
  df
}

test_that("a known rate is recovered and spilled detections are flagged, genuine ones are not", {
  df <- .sim_run(r = 0.002, seed = 3)
  res <- flag_hopped_detections(df, run_col = "run", control_samples = attr(df, "controls"),
                                verbose = FALSE)
  rr <- attr(res, "run_rates")
  expect_equal(rr$evidence, "estimated")
  expect_gt(rr$rate, 0.002 / 2)
  expect_lt(rr$rate, 0.002 * 2)

  field <- res[!is.na(res$validity_flag), ]
  pure_spill <- field$genuine == 0
  flagged <- field$validity_flag != "valid"
  # the direction that removes spillover...
  expect_gt(mean(flagged[pure_spill]), 0.8)
  # ...and the direction that must stay silent on real detections
  expect_lt(mean(flagged[!pure_spill]), 0.02)
})

test_that("a detection with no source elsewhere on the run is never flagged", {
  df <- data.frame(
    event_id = c("S1", "S2", "S1", "B1"),
    taxon_name = c("A", "A", "Only", "A"),
    count = c(100000, 20, 3, 15),
    run = "R1"
  )
  res <- flag_hopped_detections(df, run_col = "run", control_samples = "B1", verbose = FALSE)
  only <- res[res$taxon_name == "Only", ]
  expect_equal(only$hop_source_reads, 0)
  expect_equal(only$validity_flag, "valid")
  expect_equal(only$observation_validity, 1)
})

test_that("reagent contamination is excluded from the rate and reported separately", {
  clean <- .sim_run(r = 0.002, seed = 5)
  dirty <- .sim_run(r = 0.002, seed = 5, contaminant = TRUE)
  r_clean <- flag_hopped_detections(clean, run_col = "run",
                                    control_samples = attr(clean, "controls"), verbose = FALSE)
  r_dirty <- flag_hopped_detections(dirty, run_col = "run",
                                    control_samples = attr(dirty, "controls"), verbose = FALSE)
  ex <- attr(r_dirty, "control_excess")
  expect_true("f01" %in% ex$feature)
  # the contaminant does not drag the rate up
  expect_lt(attr(r_dirty, "run_rates")$rate, 2 * attr(r_clean, "run_rates")$rate)
})

test_that("runs are estimated independently, and a run without evidence is reported, not judged", {
  a <- .sim_run(run = "RA", seed = 7)
  b <- .sim_run(run = "RB", seed = 8)
  b <- b[!b$event_id %in% attr(b, "controls"), ]     # run B has no controls at all
  df <- rbind(a, b)
  expect_warning(
    res <- flag_hopped_detections(df, run_col = "run", control_samples = attr(a, "controls"),
                                  verbose = FALSE),
    "no usable control or spike evidence"
  )
  rr <- attr(res, "run_rates")
  expect_equal(rr$evidence[rr$run == "RB"], "none")
  rb <- res[res$run == "RB", ]
  expect_true(all(is.na(rb$validity_flag)))
  expect_true(all(grepl("not assessed", rb$validity_reason)))
  expect_true(any(res$run == "RA" & res$validity_flag %in% "invalid_index_hop"))
})

test_that("clean controls give a bound, not a verdict", {
  df <- .sim_run(r = 0, seed = 9)
  res <- flag_hopped_detections(df, run_col = "run", control_samples = attr(df, "controls"),
                                verbose = FALSE)
  rr <- attr(res, "run_rates")
  expect_equal(rr$evidence, "bound_only")
  expect_equal(rr$rate, 0)
  expect_gt(rr$rate_upper, 0)
  expect_false(any(res$validity_flag %in% "invalid_index_hop"))
  q <- res[res$validity_flag %in% "questionable_index_hop", ]
  if (nrow(q)) expect_true(all(grepl("upper bound only", q$validity_reason)))
})

test_that("a non-native spike estimates the rate and its field reads are invalid by definition", {
  set.seed(11)
  field <- sprintf("S%02d", 1:10)
  df <- data.frame(
    event_id = c(rep(field, each = 2), "PC", field[1:3]),
    taxon_name = c(rep(c("A", "B"), times = 10), "Spike", rep("Spike", 3)),
    count = c(stats::rpois(20, 5000), 200000, 30, 25, 40),
    run = "R1"
  )
  res <- flag_hopped_detections(df, run_col = "run", spike_taxa = "Spike",
                                spike_samples = "PC", verbose = FALSE)
  rr <- attr(res, "run_rates")
  expect_equal(rr$basis, "spike")
  expect_equal(rr$spill_reads, 95)
  leak <- res[res$taxon_name == "Spike" & res$event_id != "PC", ]
  expect_true(all(leak$validity_flag == "invalid_index_hop"))
  expect_true(all(leak$observation_validity == 0))
  expect_true(is.na(res$validity_flag[res$event_id == "PC"]))
})

test_that("a spike takes precedence over controls when a run has both", {
  df <- data.frame(
    event_id = c("S1", "S2", "S3", "PC", "S1", "B1", "B1"),
    taxon_name = c("A", "A", "A", "Spike", "Spike", "A", "Spike"),
    count = c(50000, 60000, 40000, 100000, 20, 30, 10),
    run = "R1"
  )
  res <- flag_hopped_detections(df, run_col = "run", control_samples = "B1",
                                spike_taxa = "Spike", spike_samples = "PC", verbose = FALSE)
  rr <- attr(res, "run_rates")
  expect_equal(rr$basis, "spike")
  expect_false(is.na(rr$rate_controls))
  expect_false(is.na(rr$rate_spike))
})

test_that("depth shares are refused for negative controls, which cannot estimate them", {
  df <- .sim_run(seed = 13)
  expect_warning(
    res <- flag_hopped_detections(df, run_col = "run", control_samples = attr(df, "controls"),
                                  receiver_share = "depth", verbose = FALSE),
    "NOT assessed"
  )
  expect_equal(attr(res, "run_rates")$evidence, "none")
})

test_that("the input comes back in order, whole, with the schema columns appended", {
  df <- .sim_run(seed = 15)
  df <- df[sample(nrow(df)), ]
  res <- flag_hopped_detections(df, run_col = "run", control_samples = attr(df, "controls"),
                                verbose = FALSE)
  expect_equal(nrow(res), nrow(df))
  expect_identical(res[, names(df)], df, ignore_attr = TRUE)
  for (col in c("observation_validity", "validity_flag", "validity_reason", "hop_source_reads",
                "hop_receiver_share", "hop_expected", "hop_expected_upper", "hop_p_spill",
                "hop_basis")) {
    expect_true(col %in% names(res), info = col)
  }
  expect_true(all(is.na(res$validity_flag[res$event_id %in% attr(df, "controls")])))
  expect_true(all(res$validity_flag %in% c(NA, "valid", "questionable_index_hop", "invalid_index_hop")))
})

test_that("rows splitting one feature within one sample are summed before testing", {
  one <- data.frame(event_id = c("S1", "S2", "S3", "B1"), taxon_name = "A",
                    count = c(100000, 40, 50000, 20), run = "R1")
  split <- rbind(one, data.frame(event_id = "S2", taxon_name = "A", count = 0, run = "R1"))
  split$count[2] <- 25
  split$count[5] <- 15
  r1 <- flag_hopped_detections(one, run_col = "run", control_samples = "B1", verbose = FALSE)
  r2 <- flag_hopped_detections(split, run_col = "run", control_samples = "B1", verbose = FALSE)
  expect_equal(attr(r1, "run_rates")$rate, attr(r2, "run_rates")$rate)
  expect_equal(unique(r2$validity_flag[r2$event_id == "S2"]), r1$validity_flag[r1$event_id == "S2"])
})

test_that("a NULL run_col warns that everything is one run", {
  df <- .sim_run(seed = 17)
  expect_warning(
    flag_hopped_detections(df, control_samples = attr(df, "controls"), verbose = FALSE),
    "ONE run"
  )
})

test_that("a listed control with no rows is reported, not silently ignored", {
  df <- .sim_run(seed = 23)
  ctl <- attr(df, "controls")
  expect_warning(
    res <- flag_hopped_detections(df, run_col = "run", control_samples = c(ctl, "GhostBlank"),
                                  verbose = FALSE),
    "count for nothing"
  )
  expect_equal(attr(res, "controls_absent"), "GhostBlank")
})

test_that("input validation", {
  df <- .sim_run(seed = 19)
  ctl <- attr(df, "controls")
  expect_error(flag_hopped_detections(list(), control_samples = ctl), "data frame")
  expect_error(flag_hopped_detections(df, run_col = "nope", control_samples = ctl), "not found")
  expect_error(flag_hopped_detections(df, run_col = "run"), "never assumed")
  expect_error(flag_hopped_detections(df, run_col = "run", spike_taxa = "f01"), "spike_samples")
  expect_error(flag_hopped_detections(df, run_col = "run", control_samples = "zzz"), "control_samples")
  expect_error(flag_hopped_detections(df, run_col = "run", control_samples = ctl, alpha = 1), "alpha")
  expect_error(flag_hopped_detections(df, run_col = "run", control_samples = ctl[1],
                                      spike_taxa = "f01", spike_samples = ctl[1]), "both")
  bad <- df
  bad$count[1] <- -1
  expect_error(flag_hopped_detections(bad, run_col = "run", control_samples = ctl), "negative")
})

test_that("report_flags() recognises the index-hop flags", {
  df <- .sim_run(seed = 21)
  res <- flag_hopped_detections(df, run_col = "run", control_samples = attr(df, "controls"),
                                verbose = FALSE)
  expect_no_error(report_flags(res))
})

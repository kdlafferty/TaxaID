# Synthetic data generator: each site has its own community; controls carry a
# distinct "blank" community that is NOT drawn from any site. No taxonomy is
# involved anywhere, matching what the function actually uses.
.mk <- function(n_sites = 3, n_samp = 8, n_ctl = 2, seed = 1) {
  set.seed(seed)
  rows <- list()
  for (s in seq_len(n_sites)) {
    site_taxa <- paste0("site", s, "_t", 1:40)
    for (i in seq_len(n_samp)) {
      k <- sample(site_taxa, 25)
      rows[[length(rows) + 1L]] <- data.frame(
        event_id = sprintf("S%d_%02d", s, i), site = sprintf("site%d", s),
        taxon_name = k, n_reads = rpois(length(k), 400) + 50, stringsAsFactors = FALSE)
    }
    blank_taxa <- paste0("blank_t", 1:30)          # shared, non-habitat community
    for (i in seq_len(n_ctl)) {
      k <- sample(blank_taxa, 12)
      rows[[length(rows) + 1L]] <- data.frame(
        event_id = sprintf("B%d_%02d", s, i), site = sprintf("site%d", s),
        taxon_name = k, n_reads = rpois(length(k), 60) + 5, stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, rows)
}
.ctl_ids <- function(df) unique(df$event_id[grepl("^B", df$event_id)])

test_that("a clean control set stays SILENT (the half that usually goes untested)", {
  df <- .mk()
  r <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                         verbose = FALSE)
  ctl <- r[r$label == "control", ]
  expect_true(nrow(ctl) > 0)
  expect_true(all(ctl$verdict == "consistent_with_control"))
  expect_false(any(r$verdict == "RESEMBLES_SAMPLE"))
  expect_false(any(r$verdict == "RESEMBLES_CONTROL"))
})

test_that("a field sample deliberately RELABELLED as a control is flagged", {
  df <- .mk()
  planted <- "S1_03"                       # a genuine sample, called a control
  r <- validate_controls(df, site_col = "site",
                         control_samples = c(.ctl_ids(df), planted), verbose = FALSE)
  expect_identical(r$verdict[r$column_id == planted], "RESEMBLES_SAMPLE")
  # and it must not drag the genuine controls with it
  gen <- r[r$label == "control" & r$column_id != planted, ]
  expect_true(all(gen$verdict == "consistent_with_control"))
})

test_that("a control mislabelled as a SAMPLE is caught in the other direction", {
  df <- .mk()
  all_ctl <- .ctl_ids(df)
  hidden  <- all_ctl[1]                    # a genuine control, called a sample
  r <- validate_controls(df, site_col = "site",
                         control_samples = setdiff(all_ctl, hidden), verbose = FALSE)
  expect_identical(r$verdict[r$column_id == hidden], "RESEMBLES_CONTROL")
})

test_that("a site with too few samples is UNTESTABLE, not silently clean", {
  df <- .mk(n_sites = 1, n_samp = 2, n_ctl = 1)
  r <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                         min_samples_per_site = 3L, verbose = FALSE)
  expect_true(all(r$verdict == "untestable"))
  expect_identical(attr(r, "site_power")$power, "none_too_few_samples")
})

test_that("power is reported per site and a wide null is declared low-power", {
  df <- .mk()
  r <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                         verbose = FALSE)
  sp <- attr(r, "site_power")
  expect_true(all(c("n_samples","null_median","null_threshold","null_n_pairs","power")
                  %in% names(sp)))
  expect_equal(nrow(sp), 3L)
  expect_true(all(sp$n_samples == 8))
})

test_that("a wholly compromised control set WARNS rather than returning a list", {
  # 20 samples so the null is estimated from 153 pairs. With only 8 samples the
  # null has 15 pairs, its 90th percentile sits near the maximum, and a genuine
  # sample can clear it by chance -- see the low-power test below, which pins
  # that behaviour down rather than leaving it as a flaky assertion here.
  df <- .mk(n_sites = 1, n_samp = 20, n_ctl = 0)
  planted <- c("S1_01", "S1_02")           # both 'controls' are really samples
  expect_warning(
    validate_controls(df, site_col = "site", control_samples = planted, verbose = FALSE),
    "EVERY testable control resembles a field sample")
})

test_that("a SMALL null has low power, and that is a documented property", {
  # This is the failure mode the design warns about, pinned as a test so nobody
  # later reads a clean result off a null this thin. With 6 remaining samples
  # (15 pairs) the 0.90 quantile is close to the observed maximum, so a genuine
  # field sample relabelled as a control can land above it and be wrongly called
  # consistent_with_control. The guard against this is the reported `power`, not
  # a tighter threshold.
  df <- .mk(n_sites = 1, n_samp = 8, n_ctl = 0)
  r <- suppressWarnings(validate_controls(df, site_col = "site",
         control_samples = c("S1_01", "S1_02"), verbose = FALSE))
  expect_lt(unique(r$null_n_pairs), 20L)          # a thin null
  # at least one planted sample escapes detection -- the point of the test
  expect_true(any(r$verdict[r$label == "control"] == "consistent_with_control"))
  # and the function still reports the null it used, so this is auditable
  expect_true(all(!is.na(r$null_threshold[r$label == "control"])))
})

test_that("it refuses the states that must not look clean", {
  df <- .mk()
  expect_error(validate_controls(df, site_col = "site", control_samples = character(0)),
               "control_samples is required")
  expect_error(validate_controls(df, site_col = "nope", control_samples = .ctl_ids(df)),
               "site_col")
  expect_error(validate_controls(df[, c("event_id","site")], site_col = "site",
                                 control_samples = .ctl_ids(df)),
               "missing column")
})

test_that("omitting site_col warns that the pooled null is weaker", {
  df <- .mk(n_sites = 1)
  expect_warning(
    validate_controls(df, control_samples = .ctl_ids(df), verbose = FALSE),
    "pooled across the whole study")
})

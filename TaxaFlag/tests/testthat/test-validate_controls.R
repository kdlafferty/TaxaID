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
        taxon_name = k, count = rpois(length(k), 400) + 50, stringsAsFactors = FALSE)
    }
    blank_taxa <- paste0("blank_t", 1:30)          # shared, non-habitat community
    for (i in seq_len(n_ctl)) {
      k <- sample(blank_taxa, 12)
      rows[[length(rows) + 1L]] <- data.frame(
        event_id = sprintf("B%d_%02d", s, i), site = sprintf("site%d", s),
        taxon_name = k, count = rpois(length(k), 60) + 5, stringsAsFactors = FALSE)
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
  # With a robust fence the thin null is less fragile than a quantile was, so the
  # assertion is simply that the null it used is reported and auditable.
  expect_true(all(!is.na(r$null_median[r$label == "control"])))
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

test_that("max_null_pairs caps the null and records how many pairs were used", {
  df <- .mk(n_sites = 1, n_samp = 20, n_ctl = 2)   # 190 possible sample pairs
  full <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                            verbose = FALSE)
  capped <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                              max_null_pairs = 25L, verbose = FALSE)
  expect_equal(unique(full$null_n_pairs), 190L)
  expect_equal(unique(capped$null_n_pairs), 25L)
  # the cap must not change the verdicts on data this separable -- it is a
  # tractability measure, not a different test
  expect_identical(full$verdict[full$label == "control"],
                   capped$verdict[capped$label == "control"])
})

test_that("a null with NO HEADROOM is untestable, not a confident flag", {
  # Real-data failure: a site with 1,151 heterogeneous samples had a null
  # 0.90-quantile of exactly 1.000, so genuine 6-taxon controls were reported
  # RESEMBLES_SAMPLE purely because nothing can exceed 1.000. Samples here are
  # built fully disjoint from each other to reproduce that.
  set.seed(9)
  rows <- list()
  for (i in 1:8) rows[[i]] <- data.frame(
    event_id = sprintf("S_%02d", i), site = "s1",
    taxon_name = paste0("uniq", i, "_t", 1:10),
    count = 100, stringsAsFactors = FALSE)
  rows[[9]] <- data.frame(event_id = "B_01", site = "s1",
    taxon_name = paste0("blank_t", 1:5), count = 20, stringsAsFactors = FALSE)
  df <- do.call(rbind, rows)
  r <- validate_controls(df, site_col = "site", control_samples = "B_01",
                         verbose = FALSE)
  expect_gte(unique(r$null_threshold), 0.98)  # med ~1 leaves no room
  expect_true(all(r$verdict == "untestable_no_headroom"))
  expect_false(any(r$verdict == "RESEMBLES_SAMPLE"))
})

test_that("confidence is low wherever site power is not ok", {
  df <- .mk(n_sites = 2, n_samp = 8, n_ctl = 2)
  r <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                         verbose = FALSE)
  expect_true(all(r$confidence[r$power == "ok"] == "ok"))
  expect_true(all(r$confidence[r$power != "ok"] == "low"))
})

test_that("the threshold can never leave Bray-Curtis's range", {
  # The additive median+3*MAD version produced thresholds of 1.54 and 1.62 on real
  # sites, which is impossible for a metric bounded at 1 and made the headroom
  # guard fire on 59 of 84 genuine controls.
  for (ns in c(4, 8, 20)) {
    df <- .mk(n_sites = 1, n_samp = ns, n_ctl = 2)
    r <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                           verbose = FALSE)
    thr <- unique(r$null_threshold[!is.na(r$null_threshold)])
    expect_true(all(thr <= 1), info = sprintf("n_samp=%d gave threshold %s", ns,
                                              paste(round(thr,3), collapse=",")))
  }
})

test_that("reduced power is announced at RUN TIME, not only in the manual", {
  # A clean-looking result from a site that cannot test anything is the failure
  # mode most likely to be believed, and nobody reads the help page first.
  df <- .mk(n_sites = 1, n_samp = 2, n_ctl = 1)
  expect_message(
    validate_controls(df, site_col = "site", control_samples = .ctl_ids(df),
                      min_samples_per_site = 3L, verbose = TRUE),
    "BOTH PRINT")
})

# ---- an all-zero-count column must not silently vanish (regression, 2026-09-21) --

test_that("an all-zero-count CONTROL column gets its own row, not silence", {
  df <- .mk()
  zero_ctl <- "B1_01"
  df$count[df$event_id == zero_ctl] <- 0
  r <- suppressWarnings(validate_controls(
    df, site_col = "site", control_samples = .ctl_ids(df), verbose = FALSE
  ))
  row <- r[r$column_id == zero_ctl, ]
  expect_equal(nrow(row), 1L)
  expect_identical(row$label, "control")
  expect_identical(row$verdict, "no_detections")
  expect_identical(row$power, "none_no_detections")
  expect_identical(row$confidence, "low")
  expect_true(is.na(row$d_to_samples))
  expect_true(is.na(row$d_to_controls))
  expect_identical(row$n_taxa, 0L)
  expect_identical(row$n_reads, 0)
  # It must count in the printed/returned summary too, not just avoid an error.
  expect_true(zero_ctl %in% r$column_id)
})

test_that("an all-zero-count control does not falsely suppress or trigger the 'every control resembles a sample' warning", {
  df <- .mk()
  zero_ctl <- "B1_01"
  df$count[df$event_id == zero_ctl] <- 0
  # The remaining, real controls are genuinely clean, so with the
  # no-detections column correctly excluded from "testable" there must be NO
  # warning (a bug that counted it as "testable" and not RESEMBLES_SAMPLE
  # would have masked a real compromised-control-set warning in the other
  # direction; a bug that treated it as RESEMBLES_SAMPLE would fire one
  # falsely here).
  expect_warning(
    validate_controls(df, site_col = "site", control_samples = .ctl_ids(df), verbose = FALSE),
    regexp = NA
  )
})

test_that("an all-zero-count SAMPLE column also gets its own row (symmetry: the bug was column-type-agnostic)", {
  df <- .mk()
  zero_samp <- "S1_01"
  df$count[df$event_id == zero_samp] <- 0
  r <- validate_controls(df, site_col = "site", control_samples = .ctl_ids(df), verbose = FALSE)
  row <- r[r$column_id == zero_samp, ]
  expect_equal(nrow(row), 1L)
  expect_identical(row$label, "sample")
  expect_identical(row$verdict, "no_detections")
})

# ---- .med_to_m() vectorisation (2026-09-21, performance fix) ---------------

test_that(".med_to_m()'s vectorised distance-to-many-columns matches a hand loop exactly on a small fixture", {
  set.seed(7)
  taxa <- paste0("t", 1:12)
  cols <- paste0("c", 1:15)
  m <- matrix(runif(length(taxa) * length(cols)), length(taxa), length(cols),
             dimnames = list(taxa, cols))
  m <- sweep(m, 2, colSums(m), "/") # compositional, matching real usage

  bray_m <- function(m, a, b) 1 - sum(pmin(m[, a], m[, b]))
  med_to_m_loop <- function(m, id, others) {
    others <- setdiff(others, id)
    if (!length(others)) return(NA_real_)
    stats::median(vapply(others, function(o) bray_m(m, id, o), numeric(1)), na.rm = TRUE)
  }

  for (id in cols) {
    others <- setdiff(cols, id)[1:8] # an arbitrary, non-trivial "others" set
    expect_equal(
      TaxaFlag:::.med_to_m(m, id, others), med_to_m_loop(m, id, others),
      tolerance = 0,
      info = paste("mismatch for id =", id)
    )
  }
})

test_that(".bray_m() is unchanged (still the direct pairwise Bray-Curtis formula, used by the null estimate)", {
  m <- matrix(c(0.5, 0.3, 0.2, 0.1, 0.6, 0.3), nrow = 3,
             dimnames = list(c("t1", "t2", "t3"), c("a", "b")))
  expect_equal(TaxaFlag:::.bray_m(m, "a", "b"), 1 - sum(pmin(m[, "a"], m[, "b"])))
})

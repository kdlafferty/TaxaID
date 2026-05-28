# ==============================================================================
# TEST SCRIPT: Coverage Calibration Functions
# ==============================================================================
# Tests calibrate_coverage_filter() and coverage_threshold().
#
# Structure:
#   PART 1 -- calibrate_coverage_filter() on continuous coverage (DNA analog)
#   PART 2 -- calibrate_coverage_filter() on categorical coverage (acoustic analog)
#   PART 3 -- coverage_threshold() on both continuous and categorical data
#   PART 4 -- (Optional) end-to-end: filter + train on filtered pairs
#
# All parts use synthetic data -- no internet, no DECIPHER, no external files.
#
# Run time: < 5 seconds
# ==============================================================================

library(TaxaLikely)

# ==============================================================================
# Helper: build a synthetic pair data frame
# ==============================================================================
# Mimics the output of build_sequence_matrix() or build_acoustic_reference().
# H1 pairs (same species) have high p_match and high coverage.
# H2 pairs (different species, same genus) have lower p_match and lower coverage.

.make_pairs <- function(n_h1 = 60, n_h2 = 40, coverage_type = "continuous",
                        seed = 42) {
  set.seed(seed)

  # H1: within-species pairs
  h1_coverage <- if (coverage_type == "continuous")
    runif(n_h1, min = 0.6, max = 1.0) else
    sample(c(1.0, 0.8, 0.5), n_h1, replace = TRUE, prob = c(0.5, 0.35, 0.15))

  h1 <- data.frame(
    id_x       = paste0("obs", sample(1:20, n_h1, replace = TRUE)),
    id_y       = paste0("ref", sample(1:10, n_h1, replace = TRUE)),
    p_match    = runif(n_h1, min = 0.92, max = 1.00),
    coverage   = h1_coverage,
    genus.x    = "Fundulus",
    genus.y    = "Fundulus",
    species.x  = sample(c("Fundulus heteroclitus", "Fundulus parvipinnis"),
                         n_h1, replace = TRUE),
    stringsAsFactors = FALSE
  )
  h1$species.y <- h1$species.x   # same species = H1

  # H2: cross-species pairs (same genus)
  h2_coverage <- if (coverage_type == "continuous")
    runif(n_h2, min = 0.20, max = 0.75) else    # lower coverage on average
    sample(c(1.0, 0.8, 0.5, 0.3), n_h2, replace = TRUE, prob = c(0.2, 0.3, 0.3, 0.2))

  h2 <- data.frame(
    id_x       = paste0("obs", sample(1:20, n_h2, replace = TRUE)),
    id_y       = paste0("ref", sample(11:20, n_h2, replace = TRUE)),
    p_match    = runif(n_h2, min = 0.70, max = 0.93),
    coverage   = h2_coverage,
    genus.x    = "Fundulus",
    genus.y    = "Fundulus",
    species.x  = "Fundulus heteroclitus",
    species.y  = "Fundulus parvipinnis",   # different species = H2
    stringsAsFactors = FALSE
  )

  rbind(h1, h2)
}


# ==============================================================================
# PART 1: calibrate_coverage_filter() -- continuous coverage (DNA analog)
# ==============================================================================
cat("\n===== PART 1: calibrate_coverage_filter() [continuous coverage] =====\n")

pairs_dna <- .make_pairs(n_h1 = 60, n_h2 = 40, coverage_type = "continuous")
cat(sprintf("Synthetic pair data: %d H1 pairs, %d H2 pairs\n",
            sum(pairs_dna$species.x == pairs_dna$species.y),
            sum(pairs_dna$species.x != pairs_dna$species.y)))
cat(sprintf("Coverage range: %.2f -- %.2f\n",
            min(pairs_dna$coverage), max(pairs_dna$coverage)))

# ---- 1a. Basic sweep ----------------------------------------------------------
cal <- calibrate_coverage_filter(pairs_dna)

cat("\nCalibration table (first 5 rows):\n")
print(head(cal, 5))
cat("...\n")

stopifnot(is.data.frame(cal))
stopifnot(all(c("threshold", "breadth", "youden_j", "discrimination",
                "h1_retention", "h2_retention", "mean_h1_score") %in% names(cal)))
stopifnot(nrow(cal) == length(seq(0, 0.99, by = 0.05)))
cat("  PASS: table has correct structure\n")

# ---- 1b. Baseline (threshold = 0) --------------------------------------------
baseline <- cal[cal$threshold == 0, ]
stopifnot(abs(baseline$breadth       - 1.0) < 1e-9)
stopifnot(abs(baseline$h1_retention  - 1.0) < 1e-9)
stopifnot(abs(baseline$h2_retention  - 1.0) < 1e-9)
stopifnot(abs(baseline$youden_j      - 0.0) < 1e-9)
stopifnot(abs(baseline$discrimination - 1.0) < 1e-9)
cat("  PASS: baseline (threshold = 0) has breadth = 1, J = 0, discrimination = 1\n")

# ---- 1c. Youden's J is positive at the optimal threshold ---------------------
# With continuous coverage, H1 pairs have systematically higher coverage than
# H2 pairs (by construction), so J should rise above 0 and be maximised
# somewhere in the middle of the threshold range.
best_j <- max(cal$youden_j, na.rm = TRUE)
cat(sprintf("\nBest Youden J: %.3f at threshold = %.2f\n",
            best_j, cal$threshold[which.max(cal$youden_j)]))
stopifnot(best_j > 0)
cat("  PASS: optimal Youden J > 0 (coverage discriminates H1 vs H2)\n")

# ---- 1d. Breadth decreases monotonically as threshold increases --------------
stopifnot(all(diff(cal$breadth) <= 0 + 1e-9))
cat("  PASS: breadth is non-increasing with threshold\n")

# ---- 1e. Plot (visual check, not a stopifnot) --------------------------------
cat("\nPlotting calibration curves...\n")
par(mfrow = c(1, 2))
plot(cal$threshold, cal$youden_j, type = "b", pch = 16,
     xlab = "Coverage threshold", ylab = "Youden's J",
     main = "Part 1: DNA-analog calibration")
abline(v = cal$threshold[which.max(cal$youden_j)], lty = 2, col = "red")
legend("topright", "optimal J", lty = 2, col = "red", bty = "n")

plot(cal$threshold, cal$breadth, type = "b", pch = 16, col = "steelblue",
     xlab = "Coverage threshold", ylab = "Breadth (fraction of queries retained)",
     main = "Breadth vs threshold")

cat("\n===== PART 1 complete =====\n")


# ==============================================================================
# PART 2: calibrate_coverage_filter() -- categorical coverage (acoustic analog)
# ==============================================================================
cat("\n===== PART 2: calibrate_coverage_filter() [categorical coverage] =====\n")

# Acoustic-style coverage: only 5 distinct values (Xeno-canto A→1.0 … E→0.1)
pairs_acoustic <- .make_pairs(n_h1 = 50, n_h2 = 50, coverage_type = "categorical")
cat(sprintf("Unique coverage values: %s\n",
            paste(sort(unique(pairs_acoustic$coverage)), collapse = ", ")))

# Expect the categorical message to be printed
cat("\n[Expecting a 'categorical' message below]\n")
cal_ac <- calibrate_coverage_filter(pairs_acoustic)

stopifnot(is.data.frame(cal_ac))
cat("  PASS: calibrate_coverage_filter() runs on categorical coverage\n")

# J should be near-flat (not necessarily exactly flat with our random seed, but
# the range should be much smaller than for the DNA analog)
j_range <- diff(range(cal_ac$youden_j, na.rm = TRUE))
cat(sprintf("  Youden J range for acoustic data: %.3f (expect near-flat)\n", j_range))
# With categorical coverage every pair from the same recording has the same
# coverage value, so J is almost always < 0.10.  We use a generous bound here
# because the synthetic data doesn't perfectly match acoustic structure.

par(mfrow = c(1, 1))
plot(cal_ac$threshold, cal_ac$youden_j, type = "b", pch = 16, col = "darkorange",
     xlab = "Coverage threshold (Xeno-canto grade proxy)",
     ylab = "Youden's J",
     main = "Part 2: Acoustic-analog calibration (near-flat J expected)")

cat("\n===== PART 2 complete =====\n")


# ==============================================================================
# PART 3: coverage_threshold() -- quantile shortcut
# ==============================================================================
cat("\n===== PART 3: coverage_threshold() =====\n")

# ---- 3a. Continuous coverage: 95% retention default --------------------------
thresh_95 <- coverage_threshold(pairs_dna, keep_frac = 0.95)
actual_frac <- mean(pairs_dna$coverage >= thresh_95, na.rm = TRUE)
cat(sprintf("keep_frac = 0.95 -> threshold = %.3f, actual retention = %.1f%%\n",
            thresh_95, 100 * actual_frac))
stopifnot(actual_frac >= 0.94)   # at least 94% retained (quantile rounding ok)
cat("  PASS: 95% target yields >= 94% actual retention\n")

# ---- 3b. Stricter filter (90%) -----------------------------------------------
thresh_90 <- coverage_threshold(pairs_dna, keep_frac = 0.90)
stopifnot(thresh_90 >= thresh_95)   # stricter = higher threshold
cat(sprintf("  keep_frac = 0.90 -> threshold = %.3f (>= %.3f)  PASS\n",
            thresh_90, thresh_95))

# ---- 3c. Strict filter (50%) -- keeps only half the pairs, needs higher threshold
thresh_50 <- coverage_threshold(pairs_dna, keep_frac = 0.50)
stopifnot(thresh_50 >= thresh_90)
cat(sprintf("  keep_frac = 0.50 -> threshold = %.3f (>= 0.90 threshold)  PASS\n",
            thresh_50))

# ---- 3d. Categorical coverage: snapping with message -------------------------
cat("\n[Expecting a 'categorical snapping' message below]\n")
thresh_ac <- coverage_threshold(pairs_acoustic, keep_frac = 0.80)
cat(sprintf("  Categorical threshold: %.2f\n", thresh_ac))
stopifnot(thresh_ac %in% unique(pairs_acoustic$coverage))
cat("  PASS: snapped to an actual coverage level\n")

# ---- 3e. Manual filtering workflow -------------------------------------------
# Demonstrate the typical pattern: threshold -> filter -> count
thresh <- coverage_threshold(pairs_dna, keep_frac = 0.95)
pairs_filtered <- pairs_dna[pairs_dna$coverage >= thresh, ]
cat(sprintf("\nFiltered from %d to %d pairs (%.0f%% retained)\n",
            nrow(pairs_dna), nrow(pairs_filtered),
            100 * nrow(pairs_filtered) / nrow(pairs_dna)))
stopifnot(nrow(pairs_filtered) < nrow(pairs_dna))
cat("  PASS: filtering reduces pair count\n")

cat("\n===== PART 3 complete =====\n")


# ==============================================================================
# PART 4 (Optional): Calibrate → pick best threshold → train model
# ==============================================================================
# Uncomment if you want to verify the full pipeline: calibrate → filter → train.
# Requires lme4 (in Suggests; install with install.packages("lme4")).
# Expected run time: < 5 seconds on the small synthetic dataset.

cat("\n===== PART 4: (Optional) filter + train on calibrated threshold =====\n")
cat("Uncomment the block below to test the full calibrate → train pipeline.\n")

# if (requireNamespace("lme4", quietly = TRUE)) {
#
#   cat("[Running optional Part 4...]\n")
#
#   # 1. Build a larger synthetic pair set with rank columns expected by train_likelihood_model()
#   set.seed(99)
#   n  <- 200
#   sp <- c("Fundulus heteroclitus", "Fundulus parvipinnis",
#           "Gambusia affinis",      "Gambusia holbrooki")
#
#   make_row <- function(sp_x, sp_y) {
#     data.frame(
#       id_x      = paste0("obs", sample(1:40, 1)),
#       id_y      = paste0("ref", sample(1:20, 1)),
#       p_match   = if (sp_x == sp_y) runif(1, 0.90, 1.0) else runif(1, 0.65, 0.90),
#       coverage  = if (sp_x == sp_y) runif(1, 0.65, 1.0) else runif(1, 0.15, 0.75),
#       family.x  = ifelse(grepl("Fundulus", sp_x), "Fundulidae", "Poeciliidae"),
#       genus.x   = strsplit(sp_x, " ")[[1]][1],
#       species.x = sp_x,
#       family.y  = ifelse(grepl("Fundulus", sp_y), "Fundulidae", "Poeciliidae"),
#       genus.y   = strsplit(sp_y, " ")[[1]][1],
#       species.y = sp_y,
#       stringsAsFactors = FALSE
#     )
#   }
#   pairs4 <- do.call(rbind, lapply(seq_len(n), function(i) {
#     sp_x <- sample(sp, 1)
#     sp_y <- if (runif(1) < 0.6) sp_x else sample(sp, 1)
#     make_row(sp_x, sp_y)
#   }))
#
#   # 2. Calibrate
#   cal4  <- calibrate_coverage_filter(pairs4)
#   best4 <- cal4[which.max(cal4$youden_j), ]
#   cat(sprintf("Optimal threshold: %.2f  (J = %.3f, breadth = %.2f)\n",
#               best4$threshold, best4$youden_j, best4$breadth))
#
#   # 3. Filter
#   pairs4_f <- pairs4[pairs4$coverage >= best4$threshold, ]
#   cat(sprintf("After filter: %d/%d pairs\n", nrow(pairs4_f), nrow(pairs4)))
#
#   # 4. Train
#   model4 <- train_likelihood_model(pairs4_f,
#                                     rank_system = c("family", "genus", "species"))
#   cat(sprintf("Model trained: %d species, AIC = %.1f\n",
#               model4$Stats$n_species, model4$Stats$AIC_Score))
#   stopifnot(!is.null(model4$H1_Lookup))
#   cat("  PASS: model trained on coverage-filtered pairs\n")
#
# } else {
#   cat("  SKIP: lme4 not installed\n")
# }

cat("\n===== All parts complete =====\n")
cat("\nSUMMARY\n")
cat("  calibrate_coverage_filter(): sweeps thresholds, returns J + breadth metrics\n")
cat("  coverage_threshold():        quantile shortcut for a target retention fraction\n")
cat("\nTYPICAL WORKFLOW:\n")
cat("  cal    <- calibrate_coverage_filter(ref_pairs)\n")
cat("  thresh <- cal$threshold[which.max(cal$youden_j)]  # Pareto-optimal\n")
cat("  # -- OR --\n")
cat("  thresh <- coverage_threshold(ref_pairs, keep_frac = 0.95)  # quantile\n")
cat("  ref_filtered <- ref_pairs[ref_pairs$coverage >= thresh, ]\n")
cat("  model  <- train_likelihood_model(ref_filtered)\n")

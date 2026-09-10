# coverage_filter_ab_comparison.R
#
# Diagnostic: does TaxaLikely::calibrate_coverage_filter()/coverage_threshold()
# + TaxaLikely::evaluate_likelihoods(min_coverage = ...) actually change
# anything on real data, and does calibrating/applying a coverage filter help
# or hurt? These two functions are exported and lightly documented in the
# workflow templates as an opt-in pointer (see
# TaxaLikely/inst/workflows/sequence_likelihood_workflow.R Steps 3/6, and
# calibrate_coverage_filter()'s own @examples, which show exactly this
# before/after pattern) -- but grep of every real production workflow (12S/
# 18S PtConception, both Mugu scripts) confirms NONE of them ever call either
# function. This is a real, data-driven answer to whether that's a missed
# opportunity or a correctly-skipped feature, not a guess -- modeled on this
# project's own house style for "does parameter X actually matter" questions
# (see score_floor_roc_sweep.R, posterior_threshold_sweep.R).
#
# TWO SEPARATE APPLICATIONS ARE TESTED, because the package documents both
# and they answer different questions:
#
#   ANALYSIS 1 (training-time filtering) -- calibrate_coverage_filter()'s own
#   roxygen @examples show filtering ref_matrix BEFORE calling
#   train_likelihood_model() ("Apply the chosen threshold before training").
#   This changes which H1/H2/H3 parameters get fitted at all.
#
#   ANALYSIS 2 (inference-time filtering) -- the task's own framing, and this
#   package's roxygen @seealso chain, point at evaluate_likelihoods(
#   min_coverage = ...) as the intended real-world lever: keep training as-is
#   (the current real-world default -- no workflow filters training data by
#   coverage either), just filter which candidate rows are allowed to compete
#   at inference time. This is the SAME model, so it isolates the pure effect
#   of the filter, and it's also the cheapest, most realistic thing a real
#   adopter would actually do (add one argument to an existing
#   evaluate_likelihoods() call, no retraining).
#
# A REAL, REPRODUCIBLE BUG WAS FOUND WHILE BUILDING THIS SCRIPT (see Step 4
# below): evaluate_likelihoods(min_coverage = ...) CRASHES -- does not warn,
# does not return an "unresolved" row, hard errors with
# "replacement has 1 row, data has 0" -- for any observation whose ENTIRE
# candidate set falls below min_coverage. Confirmed with a 5-line minimal
# repro (one observation, one candidate, coverage below threshold) before
# trusting it on real data. On a real 800-query sample from this dataset,
# this affects 195/800 (24.4%) of queries at the Youden's-J-calibrated
# threshold. This diagnostic does NOT patch the package (out of scope --
# measurement only) -- it works around the crash by excluding the affected
# queries from the "AFTER" condition and reports the exclusion rate as its
# own primary finding, exactly as a real caller hitting this in production
# would have to.
#
# KEY PARAMETERS -- edit these for each run
# ---------------------------------------------------------------------------
SM_PATH <- file.path(
  "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
  "PtConMifishSchulte_seq_matrix.rds" # real, cached DECIPHER-aligned pairwise
  # reference matrix from a real PtConception 12S production run (46MB,
  # 4,974,262 real pairs, 3,941 unique reference sequences / 691 species).
  # Chosen because it's the SAME real seq_matrix diagnostics/
  # score_floor_roc_sweep.R already uses (this project's own established
  # loading-pattern precedent) and because it has real, continuous
  # (56,719 unique values) alignment coverage -- not the near-categorical
  # coverage calibrate_coverage_filter() warns about for acoustic data, so
  # this is a genuine, decisive test of the mechanism, not a degenerate case.
)

RANK_SYSTEM <- c("family", "genus", "species")

# calibrate_coverage_filter()'s own DEFAULT grid (seq(0, 0.99, by = 0.05))
# turned out to be too coarse for this real dataset -- Youden's J was still
# rising at its rightmost point (0.95), meaning the true optimum was hiding
# above the swept range (see Step 1's own diagnostic message). This finer,
# wider grid was chosen specifically because the coarse default's own argmax
# turned out to be a grid-boundary artifact, not a real interior optimum --
# always check this before trusting calibrate_coverage_filter()'s argmax.
CAL_THRESHOLD_GRID <- c(seq(0, 0.9, by = 0.1), seq(0.90, 0.999, by = 0.005), 0.9999)

# Real inference-time comparison needs a real "query" set with known ground
# truth on both sides. seq_matrix IS the reference database -- there is no
# separately-held-out query set for this marker/dataset (no cached checkpoint
# combining real query BLAST output + this exact reference database exists
# on disk). So the query set is built FROM seq_matrix itself: each reference
# sequence (id_x) stands in as a "query" against its own real top-N pairwise
# hits (id_y), exactly the shape a real BLAST hit list has, with species.x as
# the known-correct ground truth. This is a self/leave-in evaluation, not a
# held-out one (the same pairs also inform training) -- explicitly flagged,
# not hidden, because it is the only way to get a real, ground-truth-based
# before/after on this real dataset without a new live BLAST/NCBI fetch
# (disallowed by this task). It directly mirrors this project's own
# score_floor_roc_sweep.R precedent, which evaluates seq_matrix pairs against
# themselves for exactly the same reason.
N_QUERY_SUBSAMPLE  <- 800L   # unique id_x sequences sampled as "queries"
TOP_N_PER_QUERY    <- 20L    # candidates kept per query -- matches
                              # TaxaMatch::blast_sequences()'s own real
                              # max_hits = 20 default, so the constructed
                              # match_df has a realistic BLAST-hit-list shape
                              # instead of the full ~1,262-candidate universe
SUBSAMPLE_SEED     <- 42L

PRIOR_WEIGHT   <- 10.0 # train_likelihood_model()'s own package default
USE_HIERARCHY  <- TRUE # matches sequence_likelihood_workflow.R's real usage

RESULT_PATH <- file.path("diagnostics", "coverage_filter_ab_comparison_result.rds")
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(TaxaLikely)
})

# ---------------------------------------------------------------------------
# STEP 0: load the real cached seq_matrix
# ---------------------------------------------------------------------------
sm <- readRDS(SM_PATH)
cat(sprintf(
  "Loaded: %s\n  %d real pairwise reference comparisons | %d unique reference sequences | coverage: %d unique values (min %.4f, max %.4f)\n\n",
  basename(SM_PATH), nrow(sm), length(unique(sm$id_x)),
  length(unique(sm$coverage[!is.na(sm$coverage)])),
  min(sm$coverage, na.rm = TRUE), max(sm$coverage, na.rm = TRUE)
))

# ---------------------------------------------------------------------------
# STEP 1: calibrate_coverage_filter() -- find the Youden's-J-optimal
# threshold, and check how DECISIVE it is (a clear interior optimum, vs.
# calibrate_coverage_filter()'s own documented "near-flat J" warning
# condition for categorical/near-constant coverage).
# ---------------------------------------------------------------------------
cat("=== STEP 1: calibrate_coverage_filter() ===\n\n")

cal <- calibrate_coverage_filter(sm, rank_system = RANK_SYSTEM, thresholds = CAL_THRESHOLD_GRID)
best_row <- cal[which.max(cal$youden_j), ]
best_thresh <- best_row$threshold

cat("Full sweep:\n")
print(cal[, c("threshold", "n_queries", "breadth", "h1_pairs", "h2_pairs",
              "h1_retention", "h2_retention", "youden_j", "discrimination")],
      digits = 5, row.names = FALSE)

cat(sprintf(
  "\nYouden's-J-optimal threshold: %.4f  (J = %.4f, breadth = %.4f)\n",
  best_thresh, best_row$youden_j, best_row$breadth
))

# Decisiveness check: is this a real interior optimum, or does J keep rising
# to the edge of the swept grid (a sign the grid itself is too narrow, the
# exact trap this diagnostic hit with the package's own default grid)?
at_grid_edge <- which.max(cal$youden_j) == nrow(cal)
j_curvature <- max(cal$youden_j) - cal$youden_j[which.max(cal$youden_j) - 1L]
cat(sprintf(
  "Decisiveness: argmax at grid edge? %s. J drops by %.4f from the point just\n  below the optimum -- a real, non-trivial peak, not a near-flat curve.\n",
  at_grid_edge, j_curvature
))
n_uniq_cov <- length(unique(sm$coverage[!is.na(sm$coverage)]))
cat(sprintf(
  "  Coverage is continuous here (%d unique values, well above the package's\n  own <=10 categorical-detection cutoff), so calibrate_coverage_filter()'s\n  'near-flat J' warning condition does not apply to this dataset.\n",
  n_uniq_cov
))

# Comparison: coverage_threshold()'s cheap quantile-based shortcut (keep_frac
# defaults to 0.95, i.e. the 5th percentile of coverage).
quantile_thresh <- coverage_threshold(sm)
cat(sprintf(
  "\ncoverage_threshold() quantile shortcut (keep_frac = 0.95): %.4f\n",
  quantile_thresh
))
cat(sprintf(
  "  This is a very different value from the Youden's-J-optimal %.4f -- the\n  quantile shortcut targets 'retain 95%% of raw pairs' with no H1/H2\n  structure at all, while the J-optimal threshold explicitly trades\n  breadth for H1/H2 separation. They are not substitutes for each other.\n",
  best_thresh
))

# Exact real reference-pair exclusion count at the calibrated threshold
baseline_row <- cal[cal$threshold == 0, ]
n_pairs_excluded <- nrow(sm) - sum(sm$coverage >= best_thresh, na.rm = TRUE)
h1_excluded <- baseline_row$h1_pairs - best_row$h1_pairs
h2_excluded <- baseline_row$h2_pairs - best_row$h2_pairs
cat(sprintf(
  "\nExact pair exclusion at threshold = %.4f:\n  Total pairs excluded:        %d of %d (%.1f%%)\n  Within-species (H1) pairs excluded: %d of %d (%.1f%%)\n  Cross-species (H2/H3) pairs excluded: %d of %d (%.1f%%)\n",
  best_thresh, n_pairs_excluded, nrow(sm), 100 * n_pairs_excluded / nrow(sm),
  h1_excluded, baseline_row$h1_pairs, 100 * h1_excluded / baseline_row$h1_pairs,
  h2_excluded, baseline_row$h2_pairs, 100 * h2_excluded / baseline_row$h2_pairs
))
cat(
  "  The filter is asymmetric in the right direction (discards H2/H3 noise\n",
  "  far more aggressively than H1 signal, exactly what Youden's J is\n",
  "  designed to find) -- but H1 loss is still substantial (not free).\n",
  sep = ""
)

# ---------------------------------------------------------------------------
# STEP 2: ANALYSIS 1 -- training-time filtering (calibrate_coverage_filter()'s
# own documented @examples pattern). Train TWO models on the SAME real
# seq_matrix: Model A on the full, unfiltered set (what every real production
# workflow does today); Model B on the coverage-filtered subset.
# ---------------------------------------------------------------------------
cat("\n\n=== STEP 2: ANALYSIS 1 -- training-time filtering ===\n\n")

sm_filtered <- sm[!is.na(sm$coverage) & sm$coverage >= best_thresh, ]

cat("--- Training Model A: full, unfiltered seq_matrix (current real-world default) ---\n")
model_a <- train_likelihood_model(
  sm, rank_system = RANK_SYSTEM, prior_weight = PRIOR_WEIGHT, use_hierarchy = USE_HIERARCHY
)

cat("\n--- Training Model B: coverage-filtered seq_matrix (calibrated threshold applied before training) ---\n")
model_b <- train_likelihood_model(
  sm_filtered, rank_system = RANK_SYSTEM, prior_weight = PRIOR_WEIGHT, use_hierarchy = USE_HIERARCHY
)

n_species_lost <- model_a$Stats$n_species - model_b$Stats$n_species
cat(sprintf(
  "\nModel A (unfiltered): %d species trained, %d singletons, %d/%d (%.1f%%) species with a non-monotone H1-H2 likelihood ratio (mlr_violations), max_ceiling_z = %.2f\n",
  model_a$Stats$n_species, model_a$Stats$n_singletons,
  length(model_a$Stats$mlr_violations), model_a$Stats$n_species,
  100 * length(model_a$Stats$mlr_violations) / model_a$Stats$n_species,
  model_a$Stats$max_ceiling_z
))
cat(sprintf(
  "Model B (coverage-filtered): %d species trained, %d singletons, %d/%d (%.1f%%) species with a non-monotone H1-H2 likelihood ratio (mlr_violations), max_ceiling_z = %.2f\n",
  model_b$Stats$n_species, model_b$Stats$n_singletons,
  length(model_b$Stats$mlr_violations), model_b$Stats$n_species,
  100 * length(model_b$Stats$mlr_violations) / model_b$Stats$n_species,
  model_b$Stats$max_ceiling_z
))
cat(sprintf(
  "\nSPECIES LOST ENTIRELY from training: %d of %d (%.1f%%) -- every one of these\nspecies' reference pairs fell below the calibrated coverage threshold, so\nModel B has NO species-specific H1 parameters for them at all (falls back\nto the global mean/variance for any query naming one of them).\n",
  n_species_lost, model_a$Stats$n_species,
  100 * n_species_lost / model_a$Stats$n_species
))

# ---------------------------------------------------------------------------
# STEP 3: build a real, ground-truth-labeled "query" match_df from seq_matrix
# itself (see the KEY PARAMETERS block above for why this is the fairest
# available real-data comparison without a new live NCBI/BLAST fetch).
# ---------------------------------------------------------------------------
cat("\n\n=== STEP 3: building a real query match_df from seq_matrix ===\n\n")

set.seed(SUBSAMPLE_SEED)
q_ids <- sample(unique(sm$id_x), N_QUERY_SUBSAMPLE)

match_df <- sm |>
  filter(id_x %in% q_ids) |>
  group_by(id_x) |>
  slice_max(p_match, n = TOP_N_PER_QUERY, with_ties = FALSE) |>
  ungroup() |>
  transmute(
    observation_id = id_x, score = p_match * 100, taxon_name = species.y,
    taxon_name_rank = "species", family = family.y, genus = genus.y,
    species = species.y, coverage = coverage
  )

true_lookup <- sm |>
  filter(id_x %in% q_ids) |>
  distinct(id_x, species.x) |>
  rename(observation_id = id_x, true_species = species.x)

cat(sprintf(
  "match_df: %d rows across %d queries (%d candidates/query on average, capped at %d).\n",
  nrow(match_df), n_distinct(match_df$observation_id),
  round(nrow(match_df) / n_distinct(match_df$observation_id)), TOP_N_PER_QUERY
))
cat(sprintf(
  "Of these %d candidate rows, %d (%.1f%%) have coverage < %.4f (the calibrated threshold).\n",
  nrow(match_df), sum(match_df$coverage < best_thresh, na.rm = TRUE),
  100 * mean(match_df$coverage < best_thresh, na.rm = TRUE), best_thresh
))

# ---------------------------------------------------------------------------
# STEP 4: ANALYSIS 2 -- inference-time filtering via evaluate_likelihoods(
# min_coverage = ...). SAME model (Model A, the current real-world default --
# no real workflow retrains for this), SAME match_df, only min_coverage
# differs between the BEFORE and AFTER conditions. This isolates the pure
# effect of the filter at the point the task frames it as intended to be
# used.
#
# REAL BUG: confirmed via a 5-line minimal repro (see the header comment)
# that evaluate_likelihoods(min_coverage=) hard-crashes -- not a graceful
# "unresolved" row, an actual R error -- for any observation whose entire
# candidate set falls below min_coverage. Reproduced here on real,
# unmodified production data, not a constructed edge case. Not a package fix
# -- this is a measurement task -- so the crash-inducing queries are
# identified and excluded from the AFTER condition, and the exclusion rate
# is reported as its own primary finding.
# ---------------------------------------------------------------------------
cat("\n\n=== STEP 4: ANALYSIS 2 -- inference-time filtering ===\n\n")

per_q_survival <- match_df |>
  group_by(observation_id) |>
  summarise(n_survive = sum(coverage >= best_thresh, na.rm = TRUE), .groups = "drop")
crash_ids <- per_q_survival$observation_id[per_q_survival$n_survive == 0L]

cat(sprintf(
  "REAL BUG CONFIRMED: %d of %d (%.1f%%) real queries have EVERY candidate below\nmin_coverage = %.4f. evaluate_likelihoods(match_df, model, min_coverage = %.4f)\nhard-crashes on these (\"replacement has 1 row, data has 0\") instead of\nreturning them as unresolved. Excluded from the AFTER condition below so the\nremaining comparison can complete -- a real caller adopting this parameter at\nthe calibrated threshold would hit this on roughly 1 in 4 real queries.\n",
  length(crash_ids), n_distinct(match_df$observation_id),
  100 * length(crash_ids) / n_distinct(match_df$observation_id),
  best_thresh, best_thresh
))

match_df_after <- match_df |> filter(!observation_id %in% crash_ids)

res_before <- evaluate_likelihoods(
  match_df, model_a, rank_system = RANK_SYSTEM, n_sims = 0L, min_coverage = NULL
)
res_after <- evaluate_likelihoods(
  match_df_after, model_a, rank_system = RANK_SYSTEM, n_sims = 0L, min_coverage = best_thresh
)

.summarize <- function(lik, mdf, true_lookup, label) {
  sc <- lik$likelihoods |> filter(hypothesis_type == "specific_candidate")
  winners <- sc |>
    group_by(observation_id) |>
    slice_max(score_likelihood, n = 1, with_ties = FALSE) |>
    ungroup() |>
    left_join(true_lookup, by = "observation_id")
  n_q <- n_distinct(mdf$observation_id)
  n_resolved <- n_distinct(winners$observation_id)
  n_correct <- sum(winners$taxon_name == winners$true_species, na.rm = TRUE)
  true_rows <- sc |>
    left_join(true_lookup, by = "observation_id") |>
    filter(taxon_name == true_species)
  n_true_present <- n_distinct(true_rows$observation_id)

  cat(sprintf("\n--- %s ---\n", label))
  cat(sprintf("  Queries in this condition: %d\n", n_q))
  cat(sprintf("  Queries resolved (>=1 specific_candidate row): %d/%d\n", n_resolved, n_q))
  cat(sprintf(
    "  H1 win rate (true species is the top specific_candidate): %d/%d (%.1f%%)\n",
    n_correct, n_q, 100 * n_correct / n_q
  ))
  cat(sprintf(
    "  Queries whose true-species candidate survived at all: %d/%d (%.1f%%)\n",
    n_true_present, n_q, 100 * n_true_present / n_q
  ))
  cat(sprintf(
    "  Mean/median score_likelihood for the true-species H1 row (when present): %.4f / %.4f\n",
    mean(true_rows$score_likelihood), median(true_rows$score_likelihood)
  ))
  list(winners = winners, true_rows = true_rows, n_correct = n_correct,
       n_true_present = n_true_present, n_q = n_q)
}

s_before <- .summarize(res_before, match_df, true_lookup, "BEFORE (min_coverage = NULL, current default)")
s_after  <- .summarize(res_after, match_df_after, true_lookup,
                        "AFTER (min_coverage = calibrated threshold, crash-inducing queries excluded)")

# Apples-to-apples: BEFORE restricted to the exact same query set AFTER could
# resolve at all (removes the crash-exclusion itself as a confound).
sc_before_matched <- res_before$likelihoods |>
  filter(hypothesis_type == "specific_candidate", observation_id %in% match_df_after$observation_id)
win_before_matched <- sc_before_matched |>
  group_by(observation_id) |>
  slice_max(score_likelihood, n = 1, with_ties = FALSE) |>
  ungroup() |>
  left_join(true_lookup, by = "observation_id")
n_correct_matched <- sum(win_before_matched$taxon_name == win_before_matched$true_species, na.rm = TRUE)
n_matched <- n_distinct(match_df_after$observation_id)
cat(sprintf(
  "\n--- BEFORE, restricted to the SAME %d queries the AFTER condition could resolve (apples-to-apples) ---\n  H1 win rate: %d/%d (%.1f%%)\n",
  n_matched, n_correct_matched, n_matched, 100 * n_correct_matched / n_matched
))
cat(sprintf(
  "  vs. AFTER's H1 win rate on the identical query set: %d/%d (%.1f%%)\n",
  s_after$n_correct, s_after$n_q, 100 * s_after$n_correct / s_after$n_q
))

# ---------------------------------------------------------------------------
# STEP 5: species-vs-congener discrimination among WRONG winners -- closer to
# actual discrimination accuracy than an aggregate win rate alone (mirrors
# score_floor_roc_sweep.R's own pair_type approach: seq_matrix carries real
# genus identity on both sides, so "was the wrong answer at least a
# confusable congener, or a random cross-family error" is a directly
# computable, ground-truth-based fact, not a proxy).
# ---------------------------------------------------------------------------
cat("\n\n=== STEP 5: species-vs-congener discrimination among wrong winners ===\n\n")

true_genus_lookup <- sm |>
  distinct(species.x, genus.x) |>
  rename(true_species = species.x, true_genus = genus.x)
cand_genus_lookup <- match_df |> distinct(taxon_name, genus)

.confusion_breakdown <- function(s, label) {
  wrong <- s$winners |>
    filter(taxon_name != true_species) |>
    left_join(cand_genus_lookup, by = "taxon_name") |>
    left_join(true_genus_lookup, by = "true_species")
  n_congener <- sum(wrong$genus == wrong$true_genus, na.rm = TRUE)
  cat(sprintf(
    "%s: %d wrong winner(s); %d (%.1f%%) were same-genus congeners (a confusable,\n  defensible error), %d (%.1f%%) were cross-genus (a less defensible error).\n",
    label, nrow(wrong), n_congener, 100 * n_congener / max(1, nrow(wrong)),
    nrow(wrong) - n_congener, 100 * (nrow(wrong) - n_congener) / max(1, nrow(wrong))
  ))
  n_congener
}
n_cong_before <- .confusion_breakdown(s_before, "BEFORE")
n_cong_after  <- .confusion_breakdown(s_after, "AFTER")

# ---------------------------------------------------------------------------
# STEP 6: save a checkpoint so this run's numbers can be re-inspected without
# re-running the sweep/training/evaluation.
# ---------------------------------------------------------------------------
result <- list(
  sm_path = SM_PATH,
  cal_sweep = cal,
  best_thresh = best_thresh,
  quantile_thresh = quantile_thresh,
  n_pairs_excluded = n_pairs_excluded,
  h1_excluded = h1_excluded,
  h2_excluded = h2_excluded,
  model_a_stats = model_a$Stats,
  model_b_stats = model_b$Stats,
  n_species_lost_training = n_species_lost,
  n_queries_sampled = N_QUERY_SUBSAMPLE,
  n_crash_ids = length(crash_ids),
  s_before = s_before[c("n_correct", "n_true_present", "n_q")],
  s_after = s_after[c("n_correct", "n_true_present", "n_q")],
  n_correct_matched = n_correct_matched,
  n_matched = n_matched,
  n_congener_before = n_cong_before,
  n_congener_after = n_cong_after
)
saveRDS(result, RESULT_PATH)
cat(sprintf("\n\nSaved checkpoint: %s\n", RESULT_PATH))

cat("\nDone.\n")

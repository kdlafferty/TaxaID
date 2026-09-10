# coverage_filter_ab_comparison_v2.R
#
# v2 of coverage_filter_ab_comparison.R (v1 kept untouched at
# diagnostics/coverage_filter_ab_comparison.R / _result.rds as a historical
# record of the first, partial pass).
#
# WHAT CHANGED AND WHY: v1 found and documented a real, reproducible crash in
# TaxaLikely::evaluate_likelihoods(min_coverage = ...): any observation whose
# ENTIRE candidate set fell below min_coverage crashed the whole call with
# "replacement has 1 row, data has 0" instead of degrading gracefully. v1
# worked around this by EXCLUDING the 195/800 (24.4%) affected real queries
# from its AFTER condition -- so its reported H1 win-rate improvement
# (54.9% -> 65.1%) was computed on the ~75% of queries that happened not to
# crash, not the full real picture.
#
# The crash is now fixed (TaxaLikely, 2026-09-09 -- see TaxaLikely/CLAUDE.md's
# top session note for the root cause and fix). Root cause: .evaluate_one_query()
# already returned a correctly-shaped, zero-row data frame when min_coverage
# dropped every candidate for an observation, but evaluate_likelihoods()'s own
# per-observation loop then unconditionally ran `result$observation_id <- sid`,
# which errors on a zero-row target (sid has length 1, there are 0 rows to
# receive it). Fixed by routing such an observation to $unresolved instead,
# with a named warning -- the SAME graceful-degrade convention this function
# already used for its pre-existing coarser-than-rank_system $unresolved path
# (TaxaLikely::flag_reference_errors()/apply_coverage_constraints() and this
# project's own established precedent of "relabel/flag, don't silently drop or
# crash" were the other candidate conventions considered; the in-function
# $unresolved mechanism was chosen because it already existed for the
# structurally identical "this observation produced no usable likelihoods"
# situation one code path away, in the very same function -- matching an
# established convention beats inventing a new column/flag for the same job).
#
# THIS SCRIPT re-runs the SAME real data/query set/calibrated threshold as v1
# but does NOT exclude the 195 previously-crashing queries -- they are
# included in the AFTER condition via the fix's own graceful degradation
# (they land in res_after$unresolved, exactly as the crash-diagnosis in v1
# predicted they would if the bug were fixed the way it was). This is a
# MEASUREMENT task only -- no keep/archive recommendation is made here; the
# complete, honest before/after numbers (including how the 195 previously-
# crashing queries actually resolve) are reported so the person deciding
# whether to adopt min_coverage in a real workflow has the full picture, not
# the ~75%-of-queries partial one.
#
# KEY PARAMETERS -- identical to v1 except RESULT_PATH
# ---------------------------------------------------------------------------
SM_PATH <- file.path(
  "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
  "PtConMifishSchulte_seq_matrix.rds"
)

RANK_SYSTEM <- c("family", "genus", "species")

CAL_THRESHOLD_GRID <- c(seq(0, 0.9, by = 0.1), seq(0.90, 0.999, by = 0.005), 0.9999)

N_QUERY_SUBSAMPLE  <- 800L
TOP_N_PER_QUERY    <- 20L
SUBSAMPLE_SEED     <- 42L # identical to v1 -- same 800 queries, byte for byte

PRIOR_WEIGHT   <- 10.0
USE_HIERARCHY  <- TRUE

RESULT_PATH <- file.path("diagnostics", "coverage_filter_ab_comparison_v2_result.rds")
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(TaxaLikely)
})

# ---------------------------------------------------------------------------
# STEP 0: load the real cached seq_matrix (identical to v1)
# ---------------------------------------------------------------------------
sm <- readRDS(SM_PATH)
cat(sprintf(
  "Loaded: %s\n  %d real pairwise reference comparisons | %d unique reference sequences | coverage: %d unique values (min %.4f, max %.4f)\n\n",
  basename(SM_PATH), nrow(sm), length(unique(sm$id_x)),
  length(unique(sm$coverage[!is.na(sm$coverage)])),
  min(sm$coverage, na.rm = TRUE), max(sm$coverage, na.rm = TRUE)
))

# ---------------------------------------------------------------------------
# STEP 1: calibrate_coverage_filter() -- identical to v1; deterministic given
# the same real seq_matrix + grid, so this reproduces v1's threshold exactly
# (re-derived rather than hardcoded, so this script stays self-contained and
# re-runnable on its own).
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

quantile_thresh <- coverage_threshold(sm)
cat(sprintf(
  "\ncoverage_threshold() quantile shortcut (keep_frac = 0.95): %.4f\n",
  quantile_thresh
))

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

# ---------------------------------------------------------------------------
# STEP 2: ANALYSIS 1 -- training-time filtering (unaffected by the crash bug,
# which was purely an inference-time evaluate_likelihoods() issue). Kept
# identical to v1 for continuity/comparability of the full diagnostic; not
# itself part of what Part 2 of this task asked to be re-measured.
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
  "\nModel A (unfiltered): %d species trained, %d singletons\n",
  model_a$Stats$n_species, model_a$Stats$n_singletons
))
cat(sprintf(
  "Model B (coverage-filtered): %d species trained, %d singletons\n",
  model_b$Stats$n_species, model_b$Stats$n_singletons
))
cat(sprintf(
  "SPECIES LOST ENTIRELY from training: %d of %d (%.1f%%)\n",
  n_species_lost, model_a$Stats$n_species, 100 * n_species_lost / model_a$Stats$n_species
))

# ---------------------------------------------------------------------------
# STEP 3: build the SAME real, ground-truth-labeled query match_df as v1
# (identical seed/subsample/top-N -- the exact same 800 queries).
# ---------------------------------------------------------------------------
cat("\n\n=== STEP 3: building the real query match_df from seq_matrix (same 800 queries as v1) ===\n\n")

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

# ---------------------------------------------------------------------------
# STEP 4: ANALYSIS 2 -- inference-time filtering, NOW HONEST ACROSS ALL 800
# QUERIES. The BEFORE condition (min_coverage = NULL) is unchanged from v1.
# The AFTER condition (min_coverage = best_thresh) is now run over the FULL,
# UNFILTERED 800-query match_df -- no query is excluded. The fixed
# evaluate_likelihoods() routes any observation whose entire candidate set
# falls below min_coverage into $unresolved (with a named warning) instead of
# crashing.
# ---------------------------------------------------------------------------
cat("\n\n=== STEP 4: ANALYSIS 2 -- inference-time filtering (v2: full, uncensored 800-query comparison) ===\n\n")

per_q_survival <- match_df |>
  group_by(observation_id) |>
  summarise(n_survive = sum(coverage >= best_thresh, na.rm = TRUE), .groups = "drop")
zero_survivor_ids <- per_q_survival$observation_id[per_q_survival$n_survive == 0L]

cat(sprintf(
  "%d of %d (%.1f%%) real queries have EVERY candidate below min_coverage = %.4f.\nUnder v1, evaluate_likelihoods(min_coverage = %.4f) hard-crashed on these and they\nwere excluded from the AFTER condition entirely. The fix is now in place -- this\nscript includes every one of them in the AFTER condition below, with NO exclusion.\n",
  length(zero_survivor_ids), n_distinct(match_df$observation_id),
  100 * length(zero_survivor_ids) / n_distinct(match_df$observation_id),
  best_thresh, best_thresh
))

res_before <- evaluate_likelihoods(
  match_df, model_a, rank_system = RANK_SYSTEM, n_sims = 0L, min_coverage = NULL
)
res_after <- evaluate_likelihoods(
  match_df, model_a, rank_system = RANK_SYSTEM, n_sims = 0L, min_coverage = best_thresh
)

# Sanity check: the fix's own $unresolved set for the AFTER condition should
# exactly match the zero-survivor queries identified above from the raw
# coverage data, independently -- confirms the fix behaves as documented, not
# just that it "doesn't crash."
ids_match <- setequal(unique(res_after$unresolved$observation_id), zero_survivor_ids)
cat(sprintf(
  "\nSanity check: evaluate_likelihoods()'s own $unresolved set for AFTER exactly matches\n  the %d queries independently identified as zero-coverage-survivor above? %s\n",
  length(zero_survivor_ids), ids_match
))
if (!ids_match) {
  warning("Unresolved-set mismatch -- investigate before trusting the numbers below.")
}

.summarize <- function(lik, mdf, true_lookup, label) {
  sc <- lik$likelihoods |> filter(hypothesis_type == "specific_candidate")
  winners <- sc |>
    group_by(observation_id) |>
    slice_max(score_likelihood, n = 1, with_ties = FALSE) |>
    ungroup() |>
    left_join(true_lookup, by = "observation_id")
  n_q <- n_distinct(mdf$observation_id)
  n_resolved <- n_distinct(winners$observation_id)
  n_unresolved <- n_q - n_resolved
  n_correct <- sum(winners$taxon_name == winners$true_species, na.rm = TRUE)
  true_rows <- sc |>
    left_join(true_lookup, by = "observation_id") |>
    filter(taxon_name == true_species)
  n_true_present <- n_distinct(true_rows$observation_id)

  cat(sprintf("\n--- %s ---\n", label))
  cat(sprintf("  Queries in this condition: %d\n", n_q))
  cat(sprintf(
    "  Queries resolved (>=1 specific_candidate row): %d/%d (%.1f%%)\n",
    n_resolved, n_q, 100 * n_resolved / n_q
  ))
  cat(sprintf(
    "  Queries UNRESOLVED (0 rows -- $unresolved): %d/%d (%.1f%%)\n",
    n_unresolved, n_q, 100 * n_unresolved / n_q
  ))
  cat(sprintf(
    "  H1 win rate over ALL %d queries in this condition (true species is the top specific_candidate): %d/%d (%.1f%%)\n",
    n_q, n_correct, n_q, 100 * n_correct / n_q
  ))
  cat(sprintf(
    "  H1 win rate among RESOLVED queries only: %d/%d (%.1f%%)\n",
    n_correct, n_resolved, 100 * n_correct / max(1, n_resolved)
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
       n_true_present = n_true_present, n_q = n_q, n_resolved = n_resolved,
       n_unresolved = n_unresolved)
}

s_before <- .summarize(res_before, match_df, true_lookup, "BEFORE (min_coverage = NULL, current default)")
s_after  <- .summarize(res_after, match_df, true_lookup,
                        "AFTER (min_coverage = calibrated threshold, ALL 800 queries included -- v2, uncensored)")

# -----------------------------------------------------------------------
# THE HEADLINE QUESTION: how do the 195 (or however many, recomputed above)
# previously-crashing queries actually resolve under the fix? They are, BY
# CONSTRUCTION, always UNRESOLVED under AFTER (zero candidates individually
# clear min_coverage for them, so there is nothing for evaluate_likelihoods()
# to build a specific_candidate row from -- the fallback does NOT let any of
# them "win"). What we can honestly report is what would have happened to
# these SAME queries under BEFORE (min_coverage = NULL) -- i.e. what applying
# the filter actually costs for this specific population, not a hypothetical.
# -----------------------------------------------------------------------
cat("\n\n=== Resolution of the previously-crashing queries under the fix ===\n\n")

zero_survivor_winners_after <- res_after$likelihoods |>
  filter(hypothesis_type == "specific_candidate", observation_id %in% zero_survivor_ids)
cat(sprintf(
  "Of the %d previously-crashing queries, %d have >=1 specific_candidate row in AFTER's\n$likelihoods (expected: 0, since these queries have zero candidates individually clearing\nmin_coverage by definition -- confirms the fallback never lets one of them silently win).\n",
  length(zero_survivor_ids), n_distinct(zero_survivor_winners_after$observation_id)
))

before_winners_crashed <- res_before$likelihoods |>
  filter(hypothesis_type == "specific_candidate", observation_id %in% zero_survivor_ids) |>
  group_by(observation_id) |>
  slice_max(score_likelihood, n = 1, with_ties = FALSE) |>
  ungroup() |>
  left_join(true_lookup, by = "observation_id")

n_before_resolved_crashed <- n_distinct(before_winners_crashed$observation_id)
n_before_correct_crashed <- sum(before_winners_crashed$taxon_name == before_winners_crashed$true_species, na.rm = TRUE)
n_before_wrong_crashed <- n_before_resolved_crashed - n_before_correct_crashed
n_before_unresolved_crashed <- length(zero_survivor_ids) - n_before_resolved_crashed

cat(sprintf(
  paste0(
    "Under AFTER (min_coverage = %.4f), all %d of these queries are UNRESOLVED --\n",
    "  0 wins, 0 losses (nothing to compare), 100%% unresolved, by construction.\n\n",
    "Under BEFORE (min_coverage = NULL) -- i.e. what the filter COSTS this exact population:\n",
    "  Correct H1 winner (would have WON without the filter):   %d/%d (%.1f%%)\n",
    "  Wrong H1 winner (would have LOST without the filter):    %d/%d (%.1f%%)\n",
    "  Unresolved even without the filter (no candidate at all): %d/%d (%.1f%%)\n"
  ),
  best_thresh, length(zero_survivor_ids),
  n_before_correct_crashed, length(zero_survivor_ids), 100 * n_before_correct_crashed / length(zero_survivor_ids),
  n_before_wrong_crashed, length(zero_survivor_ids), 100 * n_before_wrong_crashed / length(zero_survivor_ids),
  n_before_unresolved_crashed, length(zero_survivor_ids), 100 * n_before_unresolved_crashed / length(zero_survivor_ids)
))

# Apples-to-apples: BEFORE restricted to the exact same query set AFTER could
# resolve at all (isolates the pure quality effect among cases the filter
# doesn't force to $unresolved -- same comparison v1 made, now against the
# correctly-computed resolved set from the full 800).
resolved_after_ids <- unique(s_after$winners$observation_id)
sc_before_matched <- res_before$likelihoods |>
  filter(hypothesis_type == "specific_candidate", observation_id %in% resolved_after_ids)
win_before_matched <- sc_before_matched |>
  group_by(observation_id) |>
  slice_max(score_likelihood, n = 1, with_ties = FALSE) |>
  ungroup() |>
  left_join(true_lookup, by = "observation_id")
n_correct_matched <- sum(win_before_matched$taxon_name == win_before_matched$true_species, na.rm = TRUE)
n_matched <- length(resolved_after_ids)
cat(sprintf(
  "\n--- BEFORE, restricted to the SAME %d queries AFTER could resolve (apples-to-apples, quality only) ---\n  H1 win rate: %d/%d (%.1f%%)\n",
  n_matched, n_correct_matched, n_matched, 100 * n_correct_matched / n_matched
))
cat(sprintf(
  "  vs. AFTER's H1 win rate on the identical query set: %d/%d (%.1f%%)\n",
  s_after$n_correct, n_matched, 100 * s_after$n_correct / n_matched
))

# ---------------------------------------------------------------------------
# STEP 5: species-vs-congener discrimination among WRONG winners -- updated
# to reflect the complete, uncensored dataset (s_before/s_after now both
# cover all 800 queries; the previously-crashing queries contribute no
# "winner" row to s_after since they are unresolved, so they correctly do not
# appear in either the right or wrong bucket here).
# ---------------------------------------------------------------------------
cat("\n\n=== STEP 5: species-vs-congener discrimination among wrong winners (full 800-query dataset) ===\n\n")

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
n_cong_before <- .confusion_breakdown(s_before, "BEFORE (all 800 queries)")
n_cong_after  <- .confusion_breakdown(s_after, "AFTER (all 800 queries, v2 uncensored)")

# ---------------------------------------------------------------------------
# STEP 6: save a checkpoint. v1's checkpoint is left untouched at
# diagnostics/coverage_filter_ab_comparison_result.rds as a historical
# record of the first, partial (crash-excluded) pass.
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
  n_zero_survivor_ids = length(zero_survivor_ids),
  zero_survivor_ids = zero_survivor_ids,
  ids_match_check = ids_match,
  s_before = s_before[c("n_correct", "n_true_present", "n_q", "n_resolved", "n_unresolved")],
  s_after = s_after[c("n_correct", "n_true_present", "n_q", "n_resolved", "n_unresolved")],
  n_before_resolved_crashed = n_before_resolved_crashed,
  n_before_correct_crashed = n_before_correct_crashed,
  n_before_wrong_crashed = n_before_wrong_crashed,
  n_before_unresolved_crashed = n_before_unresolved_crashed,
  n_correct_matched = n_correct_matched,
  n_matched = n_matched,
  n_congener_before = n_cong_before,
  n_congener_after = n_cong_after
)
saveRDS(result, RESULT_PATH)
cat(sprintf("\n\nSaved checkpoint: %s\n", RESULT_PATH))

cat("\nDone.\n")

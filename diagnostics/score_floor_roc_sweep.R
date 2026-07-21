# score_floor_roc_sweep.R
#
# Diagnostic: what score floor should TaxaAssign::score_consensus()'s
# min_score (default 0) and TaxaAssign::assign_taxa_llm()'s score_threshold
# (default 80) actually use? Extends seq_matrix_score_distribution.R's own
# suggested extension (see that script's closing comment: "extending to
# max-score ... requires computing these rates at the marker's empirical
# maximum retained score ... replace the == 1.0 comparisons with >= threshold
# comparisons") into a full ROC-style sweep.
#
# Unlike the min_posterior/cumulative_threshold (posterior_threshold_sweep.R)
# and score_sharpness/unknown_lik_weight/prior_phi/absent_detection_prob
# (llm_prior_shape_sweep.R) diagnostics, THIS one has real ground truth: every
# pair in seq_matrix has known species/genus/family identity on both sides, so
# "is this pair actually within-species" is a fact, not a proxy. That lets us
# compute real TPR/FPR at each threshold, not just resolution rate/confidence.
#
# At threshold T (in percent-identity terms, matching min_score/
# score_threshold's own 0-100 scale):
#   TPR              = fraction of WITHIN-SPECIES pairs with p_match*100 >= T
#                       (how much real same-species signal a floor of T keeps)
#   FPR_congeneric    = fraction of CONGENERIC pairs with p_match*100 >= T
#                       (the hardest, most consequential confusion -- a
#                       same-genus different-species false positive)
#   FPR_confamilial   = fraction of CONFAMILIAL pairs with p_match*100 >= T
#   FPR_crossfamily   = fraction of CROSS-FAMILY pairs with p_match*100 >= T
#
# KEY PARAMETERS — edit these for each run
# ---------------------------------------------------------------------------
SM_PATH <- file.path(
  "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
  "PtConMifishSchulte_seq_matrix.rds"       # swap for 18S: PtCon18SSchulte_seq_matrix.rds
)

EXCLUDE_FAMILIES <- character(0)

# Same thinning as seq_matrix_score_distribution.R, applied to within-species
# pairs only (the category with extreme per-species duplication).
MAX_WITHIN_SPECIES_PAIRS_PER_SP <- 20L
SET_SEED <- 42L

THRESHOLD_GRID <- seq(70, 100, by = 1)   # percent-identity scale, matching min_score/score_threshold

CURRENT_DEFAULTS <- c(score_consensus_min_score = 0, assign_taxa_llm_score_threshold = 80)
GITA_JV_THRESHOLDS <- c(species = 98, genus = 95, family = 90, phylum = 85)  # documented conventional thresholds (4th tier corrected order->phylum 2026-07-20)
# ---------------------------------------------------------------------------

library(ggplot2)
library(dplyr)

set.seed(SET_SEED)

sm_raw <- readRDS(SM_PATH)
cat(sprintf("Loaded: %s (%d rows)\n", basename(SM_PATH), nrow(sm_raw)))
if (length(EXCLUDE_FAMILIES) > 0L) {
  sm_raw <- sm_raw |> filter(!(family.x %in% EXCLUDE_FAMILIES))
}

sm <- sm_raw |>
  mutate(
    same_species = !is.na(species.x) & !is.na(species.y) & species.x == species.y,
    same_genus   = !is.na(genus.x)   & !is.na(genus.y)   & genus.x   == genus.y,
    same_family  = !is.na(family.x)  & !is.na(family.y)  & family.x  == family.y,
    pair_type = case_when(
      same_species                   ~ "within-species",
      !same_species & same_genus     ~ "congeneric",
      !same_genus   & same_family    ~ "confamilial",
      TRUE                           ~ "cross-family"
    ),
    pct_identity = p_match * 100
  ) |>
  filter(species.x != "" & !is.na(species.x))   # blank-name filter (same as seq_matrix_score_distribution.R)

cat("Pair type counts (blank-filtered):\n")
print(table(sm$pair_type))
cat("\n")

# Thinning: cap within-species pairs per species (same rationale as
# seq_matrix_score_distribution.R -- avoid one duplicate-heavy species
# dominating the TPR curve). Cross-species categories left unthinned; no
# single pair dominates those the way within-species duplicates do.
within_sp <- sm |> filter(pair_type == "within-species")
if (is.finite(MAX_WITHIN_SPECIES_PAIRS_PER_SP)) {
  within_sp <- within_sp |>
    group_by(species.x) |>
    slice_sample(n = MAX_WITHIN_SPECIES_PAIRS_PER_SP, replace = FALSE) |>
    ungroup()
}
sm_final <- bind_rows(sm |> filter(pair_type != "within-species"), within_sp)
cat(sprintf("After thinning within-species to <=%d pairs/species: %d total pairs (was %d)\n\n",
            MAX_WITHIN_SPECIES_PAIRS_PER_SP, nrow(sm_final), nrow(sm)))

# ---------------------------------------------------------------------------
# ROC-style sweep
# ---------------------------------------------------------------------------
pt <- split(sm_final$pct_identity, sm_final$pair_type)

roc <- purrr::map_dfr(THRESHOLD_GRID, function(t) {
  data.frame(
    threshold        = t,
    tpr_within_sp     = round(mean(pt[["within-species"]] >= t), 4),
    fpr_congeneric    = round(mean(pt[["congeneric"]]    >= t), 4),
    fpr_confamilial   = round(mean(pt[["confamilial"]]   >= t), 4),
    fpr_crossfamily   = round(mean(pt[["cross-family"]]  >= t), 4)
  )
})
roc$youden_j_congeneric <- round(roc$tpr_within_sp - roc$fpr_congeneric, 4)

cat("=== ROC-style sweep (percent-identity threshold) ===\n")
print(roc, row.names = FALSE)
cat("\n")

# ---------------------------------------------------------------------------
# Current defaults vs. Youden-optimal vs. conventional GITA/JV thresholds
# ---------------------------------------------------------------------------
.lookup <- function(t) roc[which.min(abs(roc$threshold - t)), ]

cat("=== Current defaults ===\n")
cat(sprintf("  score_consensus() min_score = %d:\n", CURRENT_DEFAULTS["score_consensus_min_score"]))
print(.lookup(CURRENT_DEFAULTS["score_consensus_min_score"]))
cat(sprintf("  assign_taxa_llm() score_threshold = %d:\n", CURRENT_DEFAULTS["assign_taxa_llm_score_threshold"]))
print(.lookup(CURRENT_DEFAULTS["assign_taxa_llm_score_threshold"]))
cat("\n")

best_j <- roc[which.max(roc$youden_j_congeneric), ]
cat("=== Youden's J (TPR - FPR_congeneric)-optimal threshold ===\n")
print(best_j)
cat("\n")

cat("=== Conventional GITA/Jonah Ventures thresholds (documented in TaxaAssign/CLAUDE.md) ===\n")
for (nm in names(GITA_JV_THRESHOLDS)) {
  cat(sprintf("  %s (%d): ", nm, GITA_JV_THRESHOLDS[nm]))
  row <- .lookup(GITA_JV_THRESHOLDS[nm])
  cat(sprintf("TPR=%.3f  FPR_congeneric=%.3f  FPR_confamilial=%.3f\n",
              row$tpr_within_sp, row$fpr_congeneric, row$fpr_confamilial))
}
cat("\n")

# ---------------------------------------------------------------------------
# Marker summary
# ---------------------------------------------------------------------------
cat("=== MARKER SUMMARY ===\n")
default_row <- .lookup(CURRENT_DEFAULTS["score_consensus_min_score"])
cat(sprintf("  At current min_score=0: TPR=%.3f (keeps ~%.0f%% of real within-species signal), \n",
            default_row$tpr_within_sp, 100 * default_row$tpr_within_sp))
cat(sprintf("    but FPR_congeneric=%.3f (%.0f%% of congeneric noise ALSO passes this floor --\n",
            default_row$fpr_congeneric, 100 * default_row$fpr_congeneric))
cat("    min_score=0 provides essentially NO discrimination against congeneric confusion by itself.)\n")
thresh_row <- .lookup(CURRENT_DEFAULTS["assign_taxa_llm_score_threshold"])
cat(sprintf("  At current score_threshold=80: TPR=%.3f, FPR_congeneric=%.3f, FPR_confamilial=%.3f\n",
            thresh_row$tpr_within_sp, thresh_row$fpr_congeneric, thresh_row$fpr_confamilial))
cat(sprintf("  Youden-optimal threshold for congeneric discrimination: %d (TPR=%.3f, FPR_congeneric=%.3f, J=%.3f)\n",
            best_j$threshold, best_j$tpr_within_sp, best_j$fpr_congeneric, best_j$youden_j_congeneric))
cat("\n")
cat("CAVEAT: this is real classification ground truth (species identity IS known\n")
cat("for every pair), unlike the posterior/LLM-shape sweeps' resolution-rate proxies.\n")
cat("But it measures the SCORE MATCHING step's discriminative power in isolation --\n")
cat("not the full pipeline's downstream accuracy (priors/LLM context can still\n")
cat("correct or compound a marginal score call).\n")

# ---------------------------------------------------------------------------
# Plots
# ---------------------------------------------------------------------------
roc_long <- roc |>
  select(threshold, tpr_within_sp, fpr_congeneric, fpr_confamilial, fpr_crossfamily) |>
  tidyr::pivot_longer(-threshold, names_to = "metric", values_to = "rate")

p_roc <- ggplot(roc_long, aes(x = threshold, y = rate, colour = metric)) +
  geom_line(linewidth = 1) +
  geom_vline(xintercept = CURRENT_DEFAULTS["assign_taxa_llm_score_threshold"],
             linetype = "dashed", colour = "red") +
  geom_vline(xintercept = GITA_JV_THRESHOLDS["species"],
             linetype = "dotted", colour = "black") +
  labs(
    title = "TPR (within-species) vs FPR (cross-species) by percent-identity threshold",
    subtitle = "Red dashed = assign_taxa_llm() default score_threshold (80) | Dotted black = GITA/JV species threshold (98)",
    x = "Percent-identity threshold", y = "Rate", colour = "Metric"
  ) +
  theme_bw()

p_curve <- ggplot(roc, aes(x = fpr_congeneric, y = tpr_within_sp)) +
  geom_path(colour = "steelblue", linewidth = 1) +
  geom_point(data = .lookup(CURRENT_DEFAULTS["assign_taxa_llm_score_threshold"]),
             aes(x = fpr_congeneric, y = tpr_within_sp), colour = "red", size = 3) +
  geom_abline(slope = 1, intercept = 0, linetype = "dotted", colour = "grey50") +
  labs(
    title = "ROC curve: within-species TPR vs congeneric FPR",
    subtitle = "Red point = current assign_taxa_llm() default (score_threshold=80)",
    x = "FPR (congeneric)", y = "TPR (within-species)"
  ) +
  theme_bw()

p_youden <- ggplot(roc, aes(x = threshold, y = youden_j_congeneric)) +
  geom_line(colour = "darkgreen", linewidth = 1) +
  geom_point(colour = "darkgreen") +
  geom_vline(xintercept = best_j$threshold, linetype = "dashed", colour = "red") +
  labs(
    title = "Youden's J (TPR - FPR_congeneric) by threshold",
    subtitle = sprintf("Red dashed = optimum (threshold=%d)", best_j$threshold),
    x = "Percent-identity threshold", y = "Youden's J"
  ) +
  theme_bw()

print(p_roc)
print(p_curve)
print(p_youden)

cat("\nDone.\n")

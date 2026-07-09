# posterior_threshold_sweep.R
#
# Diagnostic: sensitivity of TaxaAssign::posterior_consensus() to
# min_posterior and cumulative_threshold, against a real posterior_df.
#
# min_posterior and cumulative_threshold are applied sequentially, not
# independently: min_posterior is a hard row filter applied FIRST (drop any
# hypothesis below this fraction of an observation's total named-hypothesis
# posterior mass); cumulative_threshold then selects the smallest surviving
# prefix (sorted descending) reaching this cumulative mass. A high enough
# min_posterior can make cumulative_threshold moot (e.g. only 1 hypothesis
# survives). See posterior_consensus()'s own @details "Threshold interaction"
# section for the mechanism; this script asks the empirical question that
# section explicitly does NOT answer: are the *defaults* (0.05 / 0.90)
# actually good cutoffs on real data, or just plausible-sounding numbers.
#
# posterior_consensus() is pure-R, no re-simulation, given an already-computed
# posterior_df (see TaxaAssign/CLAUDE.md's scaling note) -- so the sweep re-runs
# posterior_consensus() at each (min_posterior, cumulative_threshold) grid
# point against the SAME posterior_df, rather than re-running the expensive
# Monte Carlo step (compute_posterior()) each time.
#
# posterior_df is NOT bundled with this diagnostic (it's derived from a real
# dataset outside the TaxaID repo). See
# scratchpad/reconstruct_posterior_df_12S.R (session-local, not committed) for
# how it was built from PtConception 12S checkpoints (Step 7a.5 through
# compute_posterior(), no live GBIF/DECIPHER calls).
#
# KEY PARAMETERS — edit these for each run
# ---------------------------------------------------------------------------
POSTERIOR_DF_PATH <- file.path(
  "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
  "PtConMifishSchulte_posterior_df_for_sweep.rds"
)

RANK_SYSTEM <- c("order", "family", "genus", "species")

# Grid to sweep. Defaults (0.05 / 0.90) are included so they show up as one
# cell in the heatmaps below, not just asserted as "the" answer.
MIN_POSTERIOR_GRID        <- c(0, 0.01, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20)
CUMULATIVE_THRESHOLD_GRID <- c(0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 0.99)

POSTERIOR_COL <- "posterior_point_est"

# The sweep itself (below) is expensive (pure-R per-observation loop x grid
# size -- the full 13,483-observation x 56-grid-point sweep took >15 min and
# was twice interrupted before finishing). Subsample observations to make the
# sweep fast and robust; a few thousand real observations is plenty to detect
# whether the resolution rate is meaningfully sensitive to these thresholds.
# Set to Inf to use all observations.
SUBSAMPLE_N_OBSERVATIONS <- 3000L
SUBSAMPLE_SEED           <- 42L

# Set this TRUE to reuse a prior run's checkpointed results (e.g. after fixing
# a bug in the post-processing/plots below) instead of re-running the sweep.
REUSE_CHECKPOINTED_RESULTS <- FALSE
# ---------------------------------------------------------------------------

library(ggplot2)
library(dplyr)
library(TaxaAssign)

# ---------------------------------------------------------------------------
# 0. Load (+ optional subsample)
# ---------------------------------------------------------------------------
posterior_df_full <- readRDS(POSTERIOR_DF_PATH)
cat(sprintf("Loaded: %s\n", basename(POSTERIOR_DF_PATH)))
cat(sprintf("Rows: %d | Observations: %d\n",
            nrow(posterior_df_full), n_distinct(posterior_df_full$observation_id)))

if (is.finite(SUBSAMPLE_N_OBSERVATIONS) &&
    SUBSAMPLE_N_OBSERVATIONS < n_distinct(posterior_df_full$observation_id)) {
  set.seed(SUBSAMPLE_SEED)
  keep_ids <- sample(unique(posterior_df_full$observation_id), SUBSAMPLE_N_OBSERVATIONS)
  posterior_df <- posterior_df_full[posterior_df_full$observation_id %in% keep_ids, ]
  cat(sprintf("Subsampled to %d observations (seed %d): %d rows\n",
              SUBSAMPLE_N_OBSERVATIONS, SUBSAMPLE_SEED, nrow(posterior_df)))
} else {
  posterior_df <- posterior_df_full
}
cat("\n")

results_path <- file.path(dirname(POSTERIOR_DF_PATH), "posterior_threshold_sweep_results.rds")

# ---------------------------------------------------------------------------
# 1. Sweep grid
# ---------------------------------------------------------------------------
grid <- expand.grid(
  min_posterior        = MIN_POSTERIOR_GRID,
  cumulative_threshold = CUMULATIVE_THRESHOLD_GRID
)

if (REUSE_CHECKPOINTED_RESULTS && file.exists(results_path)) {
  cat(sprintf("Reusing checkpointed sweep results: %s\n\n", results_path))
  results <- readRDS(results_path)
} else {

cat(sprintf("Sweeping %d grid points x %d observations...\n",
            nrow(grid), n_distinct(posterior_df$observation_id)))

t0 <- proc.time()
results <- purrr::pmap_dfr(grid, function(min_posterior, cumulative_threshold) {
  con <- suppressWarnings(suppressMessages(
    posterior_consensus(
      posterior_df,
      rank_system          = RANK_SYSTEM,
      cumulative_threshold = cumulative_threshold,
      min_posterior        = min_posterior,
      posterior_col        = POSTERIOR_COL
    )
  ))
  n_obs <- nrow(con)
  data.frame(
    min_posterior           = min_posterior,
    cumulative_threshold    = cumulative_threshold,
    n_observations          = n_obs,
    pct_resolved            = round(100 * mean(con$is_resolved, na.rm = TRUE), 2),
    pct_species              = round(100 * mean(con$consensus_rank == "species", na.rm = TRUE), 2),
    pct_unresolved_na        = round(100 * mean(is.na(con$consensus_taxon)), 2),
    mean_n_plausible          = round(mean(con$n_plausible, na.rm = TRUE), 3),
    pct_single                = round(100 * mean(con$consensus_reason == "single", na.rm = TRUE), 2),
    pct_unanimous              = round(100 * mean(con$consensus_reason == "unanimous", na.rm = TRUE), 2),
    pct_lca                    = round(100 * mean(con$consensus_reason == "lca", na.rm = TRUE), 2)
  )
})
cat(sprintf("Sweep done in %.1fs.\n\n", (proc.time() - t0)[["elapsed"]]))

# Checkpoint immediately -- the sweep itself is the expensive part (pure-R
# per-observation loop x grid size); everything below is cheap post-processing
# that shouldn't require re-running the sweep if it has a bug.
saveRDS(results, results_path)
cat(sprintf("Checkpointed sweep results: %s\n\n", results_path))

}

# ---------------------------------------------------------------------------
# 2. Table: the default cell vs. the grid
# ---------------------------------------------------------------------------
default_row <- results |>
  filter(min_posterior == 0.05, cumulative_threshold == 0.90)

cat("=== Default (min_posterior = 0.05, cumulative_threshold = 0.90) ===\n")
print(default_row)
cat("\n")

cat("=== Full grid ===\n")
print(as.data.frame(results |> arrange(min_posterior, cumulative_threshold)))
cat("\n")

# ---------------------------------------------------------------------------
# 3. Sensitivity: how much does the resolution rate move across the grid?
# ---------------------------------------------------------------------------
res_range <- range(results$pct_resolved)
sp_range  <- range(results$pct_species)

cat("=== MARKER SUMMARY ===\n")
cat(sprintf("  pct_resolved range across grid:  %.1f%% - %.1f%%  (spread: %.1f pts)\n",
            res_range[1], res_range[2], diff(res_range)))
cat(sprintf("  pct_species range across grid:   %.1f%% - %.1f%%  (spread: %.1f pts)\n",
            sp_range[1], sp_range[2], diff(sp_range)))
cat(sprintf("  Default cell pct_resolved:       %.1f%%\n", default_row$pct_resolved))
cat(sprintf("  Default cell pct_species:        %.1f%%\n", default_row$pct_species))

# Marginal sensitivity: fix cumulative_threshold at default, vary min_posterior
mp_marginal <- results |> filter(cumulative_threshold == 0.90)
ct_marginal <- results |> filter(min_posterior == 0.05)

cat(sprintf("\n  Holding cumulative_threshold = 0.90, min_posterior 0 -> %.2f moves pct_resolved by %.1f pts\n",
            max(MIN_POSTERIOR_GRID),
            mp_marginal$pct_resolved[which.max(mp_marginal$min_posterior)] -
            mp_marginal$pct_resolved[which.min(mp_marginal$min_posterior)]))
cat(sprintf("  Holding min_posterior = 0.05, cumulative_threshold %.2f -> %.2f moves pct_resolved by %.1f pts\n",
            min(CUMULATIVE_THRESHOLD_GRID), max(CUMULATIVE_THRESHOLD_GRID),
            ct_marginal$pct_resolved[which.max(ct_marginal$cumulative_threshold)] -
            ct_marginal$pct_resolved[which.min(ct_marginal$cumulative_threshold)]))

cat(ifelse(
  diff(res_range) < 3,
  "\n  Interpretation: resolution rate is essentially FLAT across this grid --\n  the defaults are not doing meaningful work; almost any value in this\n  range gives the same answer on this dataset.\n",
  ifelse(
    diff(res_range) < 15,
    "\n  Interpretation: MODERATE sensitivity -- defaults matter but the pipeline\n  is not on a knife-edge; nearby values give similar results.\n",
    "\n  Interpretation: HIGH sensitivity -- the choice of threshold materially\n  changes how many observations resolve to species. Worth pinning down\n  more carefully (e.g. against a hand-labeled validation subset) rather\n  than treating either default as self-evidently correct.\n"
  )
))

# ---------------------------------------------------------------------------
# 4. Plots
# ---------------------------------------------------------------------------

# 4a. Heatmap: pct_resolved across the grid
p_resolved <- results |>
  ggplot(aes(x = factor(cumulative_threshold), y = factor(min_posterior), fill = pct_resolved)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.0f", pct_resolved)), size = 3) +
  scale_fill_viridis_c(name = "% resolved\n(finest rank)") +
  labs(
    title = "posterior_consensus(): % observations resolved to finest rank",
    subtitle = sprintf("Real data, n=%d observations | red box = current default (0.05, 0.90)",
                        n_distinct(posterior_df$observation_id)),
    x = "cumulative_threshold", y = "min_posterior"
  ) +
  theme_bw()

# 4b. Heatmap: pct_species
p_species <- results |>
  ggplot(aes(x = factor(cumulative_threshold), y = factor(min_posterior), fill = pct_species)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.0f", pct_species)), size = 3) +
  scale_fill_viridis_c(name = "% species-\nlevel calls") +
  labs(
    title = "posterior_consensus(): % observations resolved to species",
    subtitle = "Real data | red box = current default (0.05, 0.90)",
    x = "cumulative_threshold", y = "min_posterior"
  ) +
  theme_bw()

# 4c. Marginal line plot: min_posterior sweep at fixed cumulative_threshold = 0.90
p_marginal_mp <- mp_marginal |>
  ggplot(aes(x = min_posterior, y = pct_resolved)) +
  geom_line(colour = "steelblue") +
  geom_point(colour = "steelblue", size = 2) +
  geom_vline(xintercept = 0.05, linetype = "dashed", colour = "red") +
  labs(
    title = "Sensitivity to min_posterior (cumulative_threshold fixed at 0.90)",
    subtitle = "Red dashed = current default (0.05)",
    x = "min_posterior", y = "% resolved to finest rank"
  ) +
  theme_bw()

# 4d. Marginal line plot: cumulative_threshold sweep at fixed min_posterior = 0.05
p_marginal_ct <- ct_marginal |>
  ggplot(aes(x = cumulative_threshold, y = pct_resolved)) +
  geom_line(colour = "coral") +
  geom_point(colour = "coral", size = 2) +
  geom_vline(xintercept = 0.90, linetype = "dashed", colour = "red") +
  labs(
    title = "Sensitivity to cumulative_threshold (min_posterior fixed at 0.05)",
    subtitle = "Red dashed = current default (0.90)",
    x = "cumulative_threshold", y = "% resolved to finest rank"
  ) +
  theme_bw()

print(p_resolved)
print(p_species)
print(p_marginal_mp)
print(p_marginal_ct)

cat("\nDone.\n")

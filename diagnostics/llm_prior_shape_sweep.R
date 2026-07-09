# llm_prior_shape_sweep.R
#
# Diagnostic: sensitivity of TaxaAssign::assign_taxa_llm() to four parameters
# that shape its LLM-derived likelihoods/priors:
#   - score_sharpness       (default 0.1)  -- exponential weight on match scores
#   - unknown_lik_weight    (default 0.05) -- baseline weight for the "unknown" catch-all
#   - prior_phi             (default c(high=50, moderate=10, low=3)) -- Beta concentration
#   - absent_detection_prob (default 0.80) -- suppression strength for known-absent taxa
#
# All four are deterministic post-processing on already-fetched LLM output
# (Session 145 factored the merge step into TaxaAssign:::.merge_llm_priors(),
# and .score_to_likelihood() was already standalone) -- so, given a FIXED,
# real LLM response, this sweep needs ZERO further LLM calls. See
# scratchpad/run_llm_once_for_real.R (session-local, not committed) for how
# the one real LLM run that seeds this sweep was produced: 5 real Anthropic
# API calls against 499 real PtConception 12S observations / 204 unique taxa.
#
# Each of the four parameters is swept INDEPENDENTLY (holding the other three
# at their defaults) rather than a full cross-product grid, since -- unlike
# min_posterior/cumulative_threshold (see posterior_threshold_sweep.R), which
# have a documented, tested interaction -- these four operate on largely
# separate parts of the likelihood/prior construction (score_sharpness +
# unknown_lik_weight shape the likelihood; prior_phi shapes prior
# concentration; absent_detection_prob only touches specific suppressed taxa).
#
# IMPORTANT CAVEAT on absent_detection_prob: the real LLM run behind this
# checkpoint was NOT given any known_absent taxa (none of this ecosystem's
# real workflows currently use that argument), so absent_detection_prob is
# structurally a no-op on the raw checkpoint -- the suppression loop inside
# .merge_llm_priors() never fires when known_absent_df has 0 rows. To test
# its mechanism at all, this script builds a SYNTHETIC known_absent_df
# (marking the top-N highest-prior real taxa as "known absent", disclosed
# here and in the printed output) purely to exercise the suppression math on
# real prior values -- this is NOT a real ecological claim about those
# species' absence.
#
# KEY PARAMETERS — edit these for each run
# ---------------------------------------------------------------------------
CHECKPOINT_PATH <- file.path(
  "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
  "PtConMifishSchulte_llm_prior_checkpoint.rds"
)

SCORE_SHARPNESS_GRID    <- c(0, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0)
UNKNOWN_LIK_WEIGHT_GRID <- c(0.01, 0.02, 0.05, 0.08, 0.10, 0.15, 0.20)
PRIOR_PHI_SCALAR_GRID   <- c(2, 3, 5, 10, 20, 30, 50, 80)   # scalar phi (uniform across quality)
ABSENT_DETECTION_PROB_GRID <- c(0.10, 0.30, 0.50, 0.70, 0.80, 0.90, 0.95, 0.99)
N_SYNTHETIC_KNOWN_ABSENT <- 5L

N_SIMS <- 1000L
# ---------------------------------------------------------------------------

library(dplyr)
library(TaxaAssign)

ckpt <- readRDS(CHECKPOINT_PATH)
observation_ids <- ckpt$observation_ids
group_map       <- ckpt$group_map
lik_list_base   <- ckpt$lik_list
prior_tables    <- ckpt$prior_tables
tax_cols        <- ckpt$tax_cols
candidates      <- ckpt$candidates
known_absent_df_empty <- ckpt$known_absent_df

cat(sprintf("Loaded checkpoint: %s\n", basename(CHECKPOINT_PATH)))
cat(sprintf("Observations: %d | Unique taxa evaluated by LLM: %d\n",
            length(observation_ids), nrow(prior_tables[["all"]])))
cat("\n")

# Defaults, matching assign_taxa_llm()'s own signature defaults
DEFAULT_SCORE_SHARPNESS    <- 0.1
DEFAULT_UNKNOWN_LIK_WEIGHT <- 0.05
DEFAULT_PRIOR_PHI          <- c(high = 50, moderate = 10, low = 3)
DEFAULT_ABSENT_DETECTION_PROB <- 0.80

unref_vec               <- character(0)
unreferenced_family_map <- NULL

.rebuild_lik_list <- function(sharpness, unknown_lik_weight) {
  stats::setNames(
    lapply(observation_ids, function(sid) {
      TaxaAssign:::.score_to_likelihood(
        candidates[candidates$observation_id == sid, ],
        sharpness, unknown_lik_weight, unref_vec,
        unreferenced_family_map, tax_cols
      )
    }),
    observation_ids
  )
}

.run_one <- function(sharpness, unknown_lik_weight, prior_phi, phi_scalar,
                      known_absent_df) {
  lik_list <- .rebuild_lik_list(sharpness, unknown_lik_weight)
  use_beta_prior <- !is.null(prior_phi) || !is.null(phi_scalar)
  merged_list <- TaxaAssign:::.merge_llm_priors(
    observation_ids    = observation_ids,
    group_map           = group_map,
    lik_list             = lik_list,
    prior_tables         = prior_tables,
    known_absent_df      = known_absent_df,
    unknown_lik_weight   = unknown_lik_weight,
    use_beta_prior       = use_beta_prior,
    phi_scalar           = phi_scalar,
    prior_phi            = prior_phi
  )
  post <- compute_posterior(dplyr::bind_rows(merged_list), n_sims = N_SIMS)
  con  <- suppressWarnings(suppressMessages(posterior_consensus(post, rank_system = tax_cols)))
  data.frame(
    n_observations   = nrow(con),
    pct_resolved     = round(100 * mean(con$is_resolved, na.rm = TRUE), 2),
    pct_species      = round(100 * mean(con$consensus_rank == "species", na.rm = TRUE), 2),
    mean_n_plausible = round(mean(con$n_plausible, na.rm = TRUE), 3),
    mean_consensus_posterior = round(mean(con$consensus_posterior, na.rm = TRUE), 4)
  )
}

# ---------------------------------------------------------------------------
# 1. score_sharpness sweep (holding others at default)
# ---------------------------------------------------------------------------
cat("=== Sweeping score_sharpness (others at default) ===\n")
res_sharpness <- purrr::map_dfr(SCORE_SHARPNESS_GRID, function(s) {
  cbind(score_sharpness = s, .run_one(s, DEFAULT_UNKNOWN_LIK_WEIGHT,
                                       DEFAULT_PRIOR_PHI, NULL, known_absent_df_empty))
})
print(res_sharpness)
cat("\n")

# ---------------------------------------------------------------------------
# 2. unknown_lik_weight sweep (holding others at default)
# ---------------------------------------------------------------------------
cat("=== Sweeping unknown_lik_weight (others at default) ===\n")
res_ulw <- purrr::map_dfr(UNKNOWN_LIK_WEIGHT_GRID, function(u) {
  cbind(unknown_lik_weight = u, .run_one(DEFAULT_SCORE_SHARPNESS, u,
                                          DEFAULT_PRIOR_PHI, NULL, known_absent_df_empty))
})
print(res_ulw)
cat("\n")

# ---------------------------------------------------------------------------
# 3. prior_phi sweep -- scalar (uniform) phi vs. the default asymmetric vector
# ---------------------------------------------------------------------------
cat("=== Sweeping prior_phi as a uniform scalar (others at default) ===\n")
res_phi <- purrr::map_dfr(PRIOR_PHI_SCALAR_GRID, function(p) {
  cbind(phi_scalar = p, .run_one(DEFAULT_SCORE_SHARPNESS, DEFAULT_UNKNOWN_LIK_WEIGHT,
                                  NULL, p, known_absent_df_empty))
})
res_phi_default <- cbind(
  phi_scalar = NA_real_,
  .run_one(DEFAULT_SCORE_SHARPNESS, DEFAULT_UNKNOWN_LIK_WEIGHT,
           DEFAULT_PRIOR_PHI, NULL, known_absent_df_empty)
)
cat("Scalar (uniform) phi grid:\n")
print(res_phi)
cat("\nDefault asymmetric vector c(high=50, moderate=10, low=3) for comparison:\n")
print(res_phi_default)
cat("\n")

# ---------------------------------------------------------------------------
# 4. absent_detection_prob sweep -- SYNTHETIC known_absent overlay (disclosed)
# ---------------------------------------------------------------------------
real_taxa <- prior_tables[["all"]]
synthetic_absent_taxa <- real_taxa |>
  arrange(desc(prior_mean)) |>
  slice_head(n = N_SYNTHETIC_KNOWN_ABSENT) |>
  pull(taxon_name)

cat(sprintf(
  "=== Sweeping absent_detection_prob (SYNTHETIC known_absent overlay, NOT a real claim) ===\n"
))
cat(sprintf("  Synthetic 'known absent' taxa (top %d real taxa by prior_mean, for mechanism testing only):\n",
            N_SYNTHETIC_KNOWN_ABSENT))
cat(paste0("    - ", synthetic_absent_taxa, collapse = "\n"), "\n\n")

res_adp <- purrr::map_dfr(ABSENT_DETECTION_PROB_GRID, function(p) {
  kadf <- data.frame(taxon_name = synthetic_absent_taxa, detection_prob = p,
                      stringsAsFactors = FALSE)
  cbind(absent_detection_prob = p, .run_one(DEFAULT_SCORE_SHARPNESS, DEFAULT_UNKNOWN_LIK_WEIGHT,
                                             DEFAULT_PRIOR_PHI, NULL, kadf))
})
print(res_adp)
cat("\n")

# ---------------------------------------------------------------------------
# 5. Marker summary
# ---------------------------------------------------------------------------
cat("=== MARKER SUMMARY ===\n")
cat(sprintf("  score_sharpness:       pct_resolved range %.1f%%-%.1f%% (spread %.1f pts) across %s\n",
            min(res_sharpness$pct_resolved), max(res_sharpness$pct_resolved),
            diff(range(res_sharpness$pct_resolved)),
            paste(range(SCORE_SHARPNESS_GRID), collapse = "-")))
cat(sprintf("  unknown_lik_weight:    pct_resolved range %.1f%%-%.1f%% (spread %.1f pts) across %s\n",
            min(res_ulw$pct_resolved), max(res_ulw$pct_resolved),
            diff(range(res_ulw$pct_resolved)),
            paste(range(UNKNOWN_LIK_WEIGHT_GRID), collapse = "-")))
cat(sprintf("  prior_phi (scalar):    pct_resolved range %.1f%%-%.1f%% (spread %.1f pts) across %s\n",
            min(res_phi$pct_resolved), max(res_phi$pct_resolved),
            diff(range(res_phi$pct_resolved)),
            paste(range(PRIOR_PHI_SCALAR_GRID), collapse = "-")))
cat(sprintf("    Default asymmetric vector pct_resolved: %.1f%% (compare to scalar phi=%.0f (mean-ish): %.1f%%)\n",
            res_phi_default$pct_resolved,
            mean(DEFAULT_PRIOR_PHI),
            res_phi$pct_resolved[which.min(abs(res_phi$phi_scalar - mean(DEFAULT_PRIOR_PHI)))]))
cat(sprintf("  absent_detection_prob: mean_consensus_posterior range %.4f-%.4f (spread %.4f) across %s [SYNTHETIC]\n",
            min(res_adp$mean_consensus_posterior), max(res_adp$mean_consensus_posterior),
            diff(range(res_adp$mean_consensus_posterior)),
            paste(range(ABSENT_DETECTION_PROB_GRID), collapse = "-")))
cat("\n")
cat("CAVEAT: all of the above measure resolution RATE / mean posterior mass, not\n")
cat("ACCURACY -- no ground-truth-validated observations were available. This\n")
cat("checkpoint reflects ONE real LLM response (one seed, one model call) --\n")
cat("LLM output is not perfectly reproducible run-to-run, so treat exact numbers\n")
cat("as illustrative of sensitivity magnitude, not as a precise calibration.\n")

# ---------------------------------------------------------------------------
# 6. Plots
# ---------------------------------------------------------------------------
library(ggplot2)

p1 <- ggplot(res_sharpness, aes(x = score_sharpness, y = pct_resolved)) +
  geom_line(colour = "steelblue") + geom_point(colour = "steelblue", size = 2) +
  geom_vline(xintercept = DEFAULT_SCORE_SHARPNESS, linetype = "dashed", colour = "red") +
  labs(title = "assign_taxa_llm(): sensitivity to score_sharpness",
       subtitle = "Red dashed = current default (0.1)",
       x = "score_sharpness", y = "% resolved to finest rank") +
  theme_bw()

p2 <- ggplot(res_ulw, aes(x = unknown_lik_weight, y = pct_resolved)) +
  geom_line(colour = "coral") + geom_point(colour = "coral", size = 2) +
  geom_vline(xintercept = DEFAULT_UNKNOWN_LIK_WEIGHT, linetype = "dashed", colour = "red") +
  labs(title = "assign_taxa_llm(): sensitivity to unknown_lik_weight",
       subtitle = "Red dashed = current default (0.05)",
       x = "unknown_lik_weight", y = "% resolved to finest rank") +
  theme_bw()

p3 <- ggplot(res_phi, aes(x = phi_scalar, y = pct_resolved)) +
  geom_line(colour = "darkgreen") + geom_point(colour = "darkgreen", size = 2) +
  geom_hline(yintercept = res_phi_default$pct_resolved, linetype = "dashed", colour = "red") +
  labs(title = "assign_taxa_llm(): sensitivity to prior_phi (scalar)",
       subtitle = sprintf("Red dashed = default asymmetric vector's pct_resolved (%.1f%%)",
                           res_phi_default$pct_resolved),
       x = "phi (uniform scalar)", y = "% resolved to finest rank") +
  theme_bw()

p4 <- ggplot(res_adp, aes(x = absent_detection_prob, y = mean_consensus_posterior)) +
  geom_line(colour = "purple") + geom_point(colour = "purple", size = 2) +
  geom_vline(xintercept = DEFAULT_ABSENT_DETECTION_PROB, linetype = "dashed", colour = "red") +
  labs(title = "assign_taxa_llm(): sensitivity to absent_detection_prob [SYNTHETIC known_absent]",
       subtitle = "Red dashed = current default (0.80); NOT a real ecological claim",
       x = "absent_detection_prob", y = "mean consensus_posterior") +
  theme_bw()

print(p1); print(p2); print(p3); print(p4)

cat("\nDone.\n")

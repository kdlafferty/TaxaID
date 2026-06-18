# seq_matrix_score_distribution.R
#
# Diagnostic: examine the within-species p_match distribution near 1.0.
#
# Two cleaning steps mirror what build_sequence_matrix() should do upstream:
#   1. BLANK NAME FILTER: drop sequences with empty/NA species name before
#      forming within-species pairs (blank == blank is not a valid pair).
#   2. THINNING (max_seqs_per_taxon): randomly subsample sequences per species
#      BEFORE pairing, so no single taxon dominates the within-species sample.
#      Note: the diagnostic applies this post-hoc as a pair cap; the production
#      implementation in build_sequence_matrix() should cap sequences pre-alignment
#      to also save alignment time.
#
# KEY PARAMETERS — edit these for each run
# ---------------------------------------------------------------------------
SM_PATH <- file.path(
  "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
  "PtCon18SSchulte_seq_matrix.rds"       # swap for 12S: PtConMifishSchulte_seq_matrix.rds
)

EXCLUDE_FAMILIES  <- character(0)          # e.g. c("Bovidae", "Canidae") for 12S

# Thinning: max within-species pairs retained per species (random subsample).
# Set to Inf to disable.  Rough guide: sqrt(n_seqs) pairs ≈ K seqs each used once.
MAX_PAIRS_PER_SP  <- 20L

SET_SEED          <- 42L
# ---------------------------------------------------------------------------

library(ggplot2)
library(dplyr)

set.seed(SET_SEED)

# ---------------------------------------------------------------------------
# 0. Load + optional family filter
# ---------------------------------------------------------------------------
sm_raw <- readRDS(SM_PATH)
cat(sprintf("Loaded: %s\n", basename(SM_PATH)))
cat(sprintf("Dimensions (raw): %d x %d\n", nrow(sm_raw), ncol(sm_raw)))

if (length(EXCLUDE_FAMILIES) > 0L) {
  sm_raw <- sm_raw |> filter(!(family.x %in% EXCLUDE_FAMILIES))
  cat(sprintf("After excluding %s: %d rows\n",
              paste(EXCLUDE_FAMILIES, collapse = ", "), nrow(sm_raw)))
}
cat("\n")

# ---------------------------------------------------------------------------
# 1. Classify pairs (unfiltered)
# ---------------------------------------------------------------------------
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
    )
  )

cat("Pair type counts (raw, before any cleaning):\n")
print(table(sm$pair_type))
cat("\n")

# ---------------------------------------------------------------------------
# 2. BLANK NAME FILTER
#    Pairs where species == "" or NA are invalid within-species pairs.
#    Show impact before applying.
# ---------------------------------------------------------------------------
within_raw <- sm |> filter(pair_type == "within-species")

n_blank <- sum(within_raw$species.x == "" | is.na(within_raw$species.x))
cat(sprintf("=== Blank name filter ===\n"))
cat(sprintf("Within-species pairs with blank/NA species.x: %d / %d  (%.1f%%)\n",
            n_blank, nrow(within_raw), 100 * n_blank / nrow(within_raw)))

# Top offenders
blank_breakdown <- within_raw |>
  mutate(is_blank = species.x == "" | is.na(species.x)) |>
  filter(is_blank) |>
  count(species.x, name = "n") |>
  arrange(desc(n))
if (nrow(blank_breakdown) > 0L) {
  cat("Blank species values:\n")
  print(head(blank_breakdown, 5))
}
cat("\n")

# Apply filter
within_clean <- within_raw |>
  filter(species.x != "" & !is.na(species.x))

cat(sprintf("Within-species pairs after blank filter: %d (removed %d)\n\n",
            nrow(within_clean), nrow(within_raw) - nrow(within_clean)))

# ---------------------------------------------------------------------------
# 3. THINNING — per-species pair cap
# ---------------------------------------------------------------------------
sp_counts_clean <- within_clean |>
  count(species.x, name = "n_pairs") |>
  arrange(desc(n_pairs))

cat("=== Top 10 species by within-species pair count (after blank filter, before cap) ===\n")
print(head(sp_counts_clean, 10))
cat(sprintf("\nTop species share: %.1f%%\n",
            100 * sp_counts_clean$n_pairs[1] / nrow(within_clean)))
cat(sprintf("Top 3 species share: %.1f%%\n\n",
            100 * sum(sp_counts_clean$n_pairs[1:3]) / nrow(within_clean)))

if (is.finite(MAX_PAIRS_PER_SP)) {
  within_thinned <- within_clean |>
    group_by(species.x) |>
    slice_sample(n = MAX_PAIRS_PER_SP, replace = FALSE) |>
    ungroup()
  cat(sprintf("After capping at %d pairs/species: %d pairs remain (was %d, -%.0f%%)\n\n",
              MAX_PAIRS_PER_SP, nrow(within_thinned), nrow(within_clean),
              100 * (1 - nrow(within_thinned) / nrow(within_clean))))
} else {
  within_thinned <- within_clean
  cat("No per-species cap applied.\n\n")
}

# Rebuild full sm with cleaned + thinned within-species rows
sm_final <- bind_rows(
  sm |> filter(pair_type != "within-species"),
  within_thinned
)

# ---------------------------------------------------------------------------
# 4. Exact-match rates by pair type (final cleaned data)
# ---------------------------------------------------------------------------
exact_summary <- sm_final |>
  group_by(pair_type) |>
  summarise(
    n_pairs      = n(),
    n_exact      = sum(p_match == 1.0),
    pct_exact    = round(100 * mean(p_match == 1.0), 2),
    mean_p_match = round(mean(p_match), 4),
    median_p     = round(median(p_match), 4),
    p95          = round(quantile(p_match, 0.95), 4),
    .groups      = "drop"
  )

cat("=== Exact-match rates [blank-filtered + thinned within-species] ===\n")
print(exact_summary)
cat("\n")

p_self             <- mean(within_thinned$p_match == 1.0)
p_cross_all        <- mean(sm_final$p_match[sm_final$pair_type != "within-species"] == 1.0)
p_cross_congeneric <- mean(sm_final$p_match[sm_final$pair_type == "congeneric"]  == 1.0)
p_cross_confam     <- mean(sm_final$p_match[sm_final$pair_type == "confamilial"] == 1.0)

cat(sprintf("p_self  (P(exact | within-species))       = %.4f\n", p_self))
cat(sprintf("p_cross (P(exact | all cross-species))    = %.4f\n", p_cross_all))
cat(sprintf("p_cross (P(exact | congeneric))           = %.4f\n", p_cross_congeneric))
cat(sprintf("p_cross (P(exact | confamilial))          = %.4f\n", p_cross_confam))
if (p_cross_all > 0)
  cat(sprintf("LR(H1 vs all-cross) at 100%% rule         = %.2f\n", p_self / p_cross_all))
if (p_cross_congeneric > 0)
  cat(sprintf("LR(H1 vs congeneric) at 100%% rule        = %.2f\n", p_self / p_cross_congeneric))
cat("\n")

# ---------------------------------------------------------------------------
# 5. Point-mass test
# ---------------------------------------------------------------------------
cat("=== Within-species p_match quantiles [filtered + thinned] ===\n")
print(quantile(within_thinned$p_match, probs = c(0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1.0)))
cat("\n")

n_exact_within <- sum(within_thinned$p_match == 1.0)
n_near_exact   <- sum(within_thinned$p_match >= 0.995 & within_thinned$p_match < 1.0)
n_near_exact_2 <- sum(within_thinned$p_match >= 0.990 & within_thinned$p_match < 0.995)

cat(sprintf("n with p_match == 1.0:                   %d  (%.1f%%)\n",
            n_exact_within, 100 * n_exact_within / nrow(within_thinned)))
cat(sprintf("n with 0.995 <= p_match < 1.0:           %d  (%.1f%%)\n",
            n_near_exact, 100 * n_near_exact / nrow(within_thinned)))
cat(sprintf("n with 0.990 <= p_match < 0.995:         %d  (%.1f%%)\n\n",
            n_near_exact_2, 100 * n_near_exact_2 / nrow(within_thinned)))

spike_ratio <- n_exact_within / max(n_near_exact, 1L)
cat(sprintf("Spike ratio (exact / [0.995,1.0) bin):   %.2f\n", spike_ratio))
cat("  Interpretation: >5 = point mass plausible; ~1 = smooth; <1 = no spike\n\n")

# Fine bins
breaks_fine        <- seq(0.90, 1.001, by = 0.005)
within_thinned$bin <- cut(within_thinned$p_match, breaks = breaks_fine,
                          right = FALSE, include.lowest = TRUE)
bin_counts <- within_thinned |>
  group_by(bin) |>
  summarise(n = n(), pct = round(100 * n() / nrow(within_thinned), 2), .groups = "drop")
cat("=== Fine bins (0.90–1.0), within-species [filtered + thinned] ===\n")
print(bin_counts, n = 30)
cat("\n")

# ---------------------------------------------------------------------------
# 6. Per-species p_self
# ---------------------------------------------------------------------------
per_species <- within_thinned |>
  group_by(species.x) |>
  summarise(
    n_pairs  = n(),
    p_self_i = mean(p_match == 1.0),
    mean_pm  = round(mean(p_match), 4),
    .groups  = "drop"
  ) |>
  arrange(desc(n_pairs))

cat("=== Per-species p_self [filtered + thinned] ===\n")
print(head(per_species, 20))
cat("\n")
cat(sprintf("Total species represented:           %d\n",  nrow(per_species)))
cat(sprintf("Species with p_self == 0:            %d / %d\n",
            sum(per_species$p_self_i == 0), nrow(per_species)))
cat(sprintf("Species with p_self == 1:            %d / %d\n",
            sum(per_species$p_self_i == 1), nrow(per_species)))
cat(sprintf("Median p_self across species:        %.4f\n", median(per_species$p_self_i)))
cat(sprintf("Mean   p_self across species:        %.4f\n\n", mean(per_species$p_self_i)))

# ---------------------------------------------------------------------------
# 7. Marker summary + model framing verdict
# ---------------------------------------------------------------------------
cat("=== MARKER SUMMARY ===\n")
cat(sprintf("  Spike ratio:              %.2f  (%s)\n",
            spike_ratio,
            ifelse(spike_ratio > 5, "point mass plausible — consider Framing A",
                   "smooth distribution — Framing B (continuous) appropriate")))
cat(sprintf("  p_self:                   %.4f\n", p_self))
cat(sprintf("  p_cross_congeneric:       %.4f\n", p_cross_congeneric))
lr_congeneric <- if (p_cross_congeneric > 0) p_self / p_cross_congeneric else NA_real_
cat(sprintf("  LR(H1 vs congeneric):     %.2f  (%s)\n",
            lr_congeneric,
            ifelse(is.na(lr_congeneric), "NA",
                   ifelse(lr_congeneric > 1,
                          "100%% rule favours H1 over congeneric",
                          "100%% rule FAVOURS CONGENERIC over H1 — rule is unreliable"))))
# NOTE: This diagnostic can also be used to assess the appropriateness of
# different score thresholds (min match floor), gap thresholds, and thinning
# strategies for a given marker.  Run on the full seq_matrix before setting
# these parameters in the pipeline:
#   - p_self / p_cross_congeneric gives the theoretical LR benefit of a 100% floor
#   - varying MAX_PAIRS_PER_SP shows sensitivity to database composition
#   - the fine-bin histogram shows where species-level information concentrates
#   - extending to max-score (not just 100%) requires computing these rates at
#     the marker's empirical maximum retained score (e.g., 97%, 98%) rather
#     than 1.0 — replace the == 1.0 comparisons with >= threshold comparisons

# ---------------------------------------------------------------------------
# 8. Plots
# ---------------------------------------------------------------------------

# 8a. Species domination before cap
p_dom <- sp_counts_clean |>
  mutate(rank = row_number()) |>
  ggplot(aes(x = rank, y = n_pairs)) +
  geom_col(fill = "steelblue") +
  geom_hline(yintercept = MAX_PAIRS_PER_SP, linetype = "dashed",
             colour = "red", linewidth = 0.8) +
  labs(
    title = "Within-species pairs per species (blank-filtered, before cap)",
    subtitle = sprintf("Red dashed = cap (%d pairs/species)", MAX_PAIRS_PER_SP),
    x = "Species rank (by n pairs)", y = "n within-species pairs"
  ) +
  theme_bw()

# 8b. p_match distributions
p_dist <- sm_final |>
  filter(p_match >= 0.75) |>
  ggplot(aes(x = p_match, fill = pair_type, colour = pair_type)) +
  geom_histogram(aes(y = after_stat(density)), binwidth = 0.005,
                 alpha = 0.4, position = "identity") +
  geom_vline(xintercept = 1.0, linetype = "dashed", colour = "black") +
  facet_wrap(~pair_type, scales = "free_y", ncol = 1) +
  labs(
    title = sprintf("p_match by pair type [blank-filtered + cap %d/sp]", MAX_PAIRS_PER_SP),
    x = "p_match", y = "Density"
  ) +
  theme_bw() + theme(legend.position = "none")

# 8c. Spike bar chart (top 5%)
p_spike <- within_thinned |>
  filter(p_match >= 0.95) |>
  mutate(bin2 = cut(p_match, breaks = seq(0.95, 1.001, by = 0.005),
                    right = FALSE, include.lowest = TRUE)) |>
  ggplot(aes(x = bin2)) +
  geom_bar(fill = "steelblue") +
  labs(
    title = "Within-species: top 5% of scores [filtered + thinned]",
    subtitle = sprintf("Spike ratio = %.2f | p_self = %.3f | p_cross_congeneric = %.3f",
                       spike_ratio, p_self, p_cross_congeneric),
    x = "p_match bin", y = "Count"
  ) +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

# 8d. Per-species p_self histogram
p_pself <- per_species |>
  filter(n_pairs >= 2L) |>
  ggplot(aes(x = p_self_i)) +
  geom_histogram(binwidth = 0.05, fill = "coral", colour = "white") +
  labs(
    title = "Per-species p_self [filtered + thinned, ≥2 pairs]",
    x = "p_self = P(p_match == 1.0 | within-species)",
    y = "Number of species"
  ) +
  theme_bw()

print(p_dom)
print(p_dist)
print(p_spike)
print(p_pself)

cat("Done.\n")

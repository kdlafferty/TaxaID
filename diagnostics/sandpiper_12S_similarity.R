# sandpiper_12S_similarity.R
#
# Compare within- and between-species 12S sequence similarity for
# western sandpiper (Calidris mauri) and least sandpiper (Calidris minutilla).
#
# Both are congeneric Calidris (family Scolopacidae), making this a direct test
# of how well 12S resolves two closely related shorebird species.
#
# Output:
#   - Console summary: n sequences, p_match quantiles, exact-match rates,
#     and likelihood ratio at 100% rule (congeneric context)
#   - 4 plots: score distributions, density comparison, congeneric overlap,
#     per-species p_self bar chart
# ==============================================================================

library(TaxaLikely)
library(ggplot2)
library(dplyr)

# ==============================================================================
# PARAMETERS
# ==============================================================================
BARCODE_TERM <- "12S"
TAXA         <- c("Calidris mauri", "Calidris minutilla")
RANK_SYSTEM  <- c("family", "genus", "species")

# Optional: cache fetched sequences so re-runs are fast
CACHE_DIR    <- file.path(
  "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics",
  "cache_sandpiper"
)

# ==============================================================================
# 1. FETCH SEQUENCES FROM NCBI
# ==============================================================================
cat("=== Fetching 12S reference sequences ===\n")
cat(sprintf("Taxa: %s\n", paste(TAXA, collapse = ", ")))
cat(sprintf("Marker: %s\n\n", BARCODE_TERM))

reference_df <- fetch_reference_sequences(
  taxa         = TAXA,
  barcode_term = BARCODE_TERM,
  rank_system  = RANK_SYSTEM,
  cache_dir    = CACHE_DIR
)

cat(sprintf("Sequences fetched:    %d\n", nrow(reference_df)))
cat(sprintf("Unique species:       %d\n", length(unique(reference_df$species))))
cat("Species breakdown:\n")
print(table(reference_df$species))
cat("\n")

cat("Sequence length distribution:\n")
print(summary(nchar(reference_df$sequence)))
cat("\n")

# ==============================================================================
# 2. BUILD SEQUENCE MATRIX
# ==============================================================================
cat("=== Building pairwise sequence matrix ===\n")

seq_matrix <- build_sequence_matrix(
  reference_df,
  rank_system        = RANK_SYSTEM,
  filter_unnamed     = TRUE,
  max_seqs_per_taxon = NULL    # retain all — small dataset, no domination risk
)

cat(sprintf("Pairwise comparisons: %d\n\n", nrow(seq_matrix)))

# ==============================================================================
# 3. CLASSIFY PAIRS
# ==============================================================================
sm <- seq_matrix |>
  mutate(
    same_species = !is.na(species.x) & !is.na(species.y) & species.x == species.y,
    same_genus   = !is.na(genus.x)   & !is.na(genus.y)   & genus.x   == genus.y,
    pair_type = case_when(
      same_species               ~ "within-species",
      !same_species & same_genus ~ "congeneric",
      TRUE                       ~ "other"
    ),
    # Readable species labels for plotting
    sp_x = sub("Calidris ", "C. ", species.x),
    sp_y = sub("Calidris ", "C. ", species.y),
    pair_label = paste0(sp_x, " vs ", sp_y)
  )

cat("Pair type counts:\n")
print(table(sm$pair_type))
cat("\n")

# Split pair types for analysis
within_sm     <- sm |> filter(pair_type == "within-species")
congeneric_sm <- sm |> filter(pair_type == "congeneric")

# ==============================================================================
# 4. SUMMARY STATISTICS
# ==============================================================================
cat("=== Within-species p_match ===\n")
for (sp in unique(within_sm$species.x)) {
  sub_sp <- within_sm |> filter(species.x == sp)
  cat(sprintf("\n  %s  (n pairs = %d)\n", sp, nrow(sub_sp)))
  print(quantile(sub_sp$p_match, probs = c(0.25, 0.5, 0.75, 0.9, 0.95, 1.0)))
  cat(sprintf("  Mean p_match:   %.4f\n", mean(sub_sp$p_match)))
  cat(sprintf("  %% exact match:  %.1f%%\n",
              100 * mean(sub_sp$p_match == 1.0)))
}

cat("\n=== Congeneric (C. mauri vs C. minutilla) ===\n")
cat(sprintf("  n pairs:        %d\n", nrow(congeneric_sm)))
cat("  Quantiles:\n")
print(quantile(congeneric_sm$p_match, probs = c(0.25, 0.5, 0.75, 0.9, 0.95, 1.0)))
cat(sprintf("  Mean p_match:   %.4f\n", mean(congeneric_sm$p_match)))
cat(sprintf("  %% exact match:  %.1f%%\n",
            100 * mean(congeneric_sm$p_match == 1.0)))

# ==============================================================================
# 5. DIAGNOSTIC RATES (p_self / p_cross framing)
# ==============================================================================
p_self_mauri      <- mean(within_sm$p_match[within_sm$species.x == "Calidris mauri"]    == 1.0)
p_self_minutilla  <- mean(within_sm$p_match[within_sm$species.x == "Calidris minutilla"] == 1.0)
p_self_overall    <- mean(within_sm$p_match == 1.0)
p_cross_congeneric <- mean(congeneric_sm$p_match == 1.0)

cat("\n=== Exact-match rates (100% rule framing) ===\n")
cat(sprintf("  p_self [C. mauri]:           %.4f\n", p_self_mauri))
cat(sprintf("  p_self [C. minutilla]:       %.4f\n", p_self_minutilla))
cat(sprintf("  p_self [pooled within-sp]:   %.4f\n", p_self_overall))
cat(sprintf("  p_cross [congeneric]:        %.4f\n", p_cross_congeneric))
if (p_cross_congeneric > 0) {
  cat(sprintf("  LR(H1 vs congeneric) @100%%:  %.2f\n",
              p_self_overall / p_cross_congeneric))
  cat("  Interpretation: LR < 1 means 100%% rule FAVOURS the wrong species\n")
} else {
  cat("  LR(H1 vs congeneric): Inf  (no congeneric exact matches)\n")
}

# ==============================================================================
# 6. FINE BINS (within-species, top 10%)
# ==============================================================================
breaks_fine <- seq(0.90, 1.001, by = 0.005)
within_sm$bin <- cut(within_sm$p_match, breaks = breaks_fine,
                     right = FALSE, include.lowest = TRUE)
bin_tab <- within_sm |>
  group_by(species.x, bin) |>
  summarise(n = n(), .groups = "drop")

cat("\n=== Fine bins (0.90–1.0), within-species ===\n")
print(bin_tab, n = 50)

# ==============================================================================
# 7. PLOTS
# ==============================================================================

# Shared colour palette
sp_colours <- c(
  "within-species" = "#2c7bb6",
  "congeneric"     = "#d7191c"
)

# ---------------------------------------------------------------------------
# Plot 1: Histogram — all pair types combined (p_match >= 0.75)
# ---------------------------------------------------------------------------
p1 <- sm |>
  filter(p_match >= 0.75) |>
  ggplot(aes(x = p_match, fill = pair_type)) +
  geom_histogram(binwidth = 0.005, alpha = 0.7, position = "identity",
                 colour = "white", linewidth = 0.2) +
  scale_fill_manual(values = sp_colours,
                    labels = c("within-species" = "Within species",
                               "congeneric"     = "Cross species\n(C. mauri vs C. minutilla)")) +
  geom_vline(xintercept = 1.0, linetype = "dashed", colour = "black", linewidth = 0.7) +
  labs(
    title    = "12S sequence similarity: western vs least sandpiper",
    subtitle = "Calidris mauri  |  Calidris minutilla",
    x        = "p_match (sequence similarity)",
    y        = "Number of pairs",
    fill     = "Pair type"
  ) +
  theme_bw(base_size = 12) +
  theme(legend.position = "top")

# ---------------------------------------------------------------------------
# Plot 2: Density overlay — within-species vs congeneric
# ---------------------------------------------------------------------------
p2 <- sm |>
  filter(pair_type %in% c("within-species", "congeneric"),
         p_match >= 0.75) |>
  ggplot(aes(x = p_match, colour = pair_type, fill = pair_type)) +
  geom_density(alpha = 0.25, linewidth = 1.0) +
  scale_colour_manual(values = sp_colours,
                      labels = c("within-species" = "Within species",
                                 "congeneric"     = "Cross species")) +
  scale_fill_manual(values = sp_colours,
                    labels = c("within-species" = "Within species",
                               "congeneric"     = "Cross species")) +
  geom_vline(xintercept = 1.0, linetype = "dashed", colour = "black", linewidth = 0.7) +
  labs(
    title    = "12S similarity density: within vs cross species",
    subtitle = "C. mauri and C. minutilla (Scolopacidae)",
    x        = "p_match",
    y        = "Density",
    colour   = NULL, fill = NULL
  ) +
  theme_bw(base_size = 12) +
  theme(legend.position = "top")

# ---------------------------------------------------------------------------
# Plot 3: Congeneric pair distribution (cross-species only)
# ---------------------------------------------------------------------------
p3 <- congeneric_sm |>
  ggplot(aes(x = p_match)) +
  geom_histogram(binwidth = 0.005, fill = "#d7191c", colour = "white",
                 alpha = 0.8, linewidth = 0.2) +
  geom_vline(xintercept = 1.0, linetype = "dashed", colour = "black", linewidth = 0.7) +
  annotate("text",
           x     = max(congeneric_sm$p_match, na.rm = TRUE) - 0.01,
           y     = Inf, vjust = 1.5, hjust = 1,
           label = sprintf("n = %d pairs\nmean = %.4f\n%% exact = %.1f%%",
                           nrow(congeneric_sm),
                           mean(congeneric_sm$p_match),
                           100 * mean(congeneric_sm$p_match == 1.0)),
           size  = 3.5, colour = "#d7191c") +
  labs(
    title    = "Cross-species 12S similarity: C. mauri vs C. minutilla",
    x        = "p_match",
    y        = "Number of pairs"
  ) +
  theme_bw(base_size = 12)

# ---------------------------------------------------------------------------
# Plot 4: Per-species p_match boxplot (raw scores, not just exact)
# ---------------------------------------------------------------------------
# Build a combined data frame with a readable species label and pair context
box_df <- bind_rows(
  within_sm |>
    select(p_match, species.x, pair_type) |>
    mutate(label = sub("Calidris ", "C. ", species.x),
           context = "within-species"),
  congeneric_sm |>
    mutate(label   = "C. mauri\nvs C. minutilla",
           context = "congeneric") |>
    select(p_match, label, context)
)

p4 <- box_df |>
  ggplot(aes(x = label, y = p_match, fill = context)) +
  geom_violin(alpha = 0.5, linewidth = 0.5, colour = "grey40") +
  geom_boxplot(width = 0.15, outlier.size = 1.0, linewidth = 0.5,
               colour = "grey20", fill = "white", alpha = 0.8) +
  scale_fill_manual(values = c("within-species" = "#2c7bb6",
                               "congeneric"     = "#d7191c")) +
  geom_hline(yintercept = 1.0, linetype = "dashed", colour = "black",
             linewidth = 0.7) +
  labs(
    title  = "12S similarity distribution by comparison type",
    x      = NULL,
    y      = "p_match",
    fill   = NULL
  ) +
  ylim(0.75, 1.01) +
  theme_bw(base_size = 12) +
  theme(legend.position = "none",
        axis.text.x = element_text(size = 10))

# ---------------------------------------------------------------------------
# Print all plots
# ---------------------------------------------------------------------------
print(p1)
print(p2)
print(p3)
print(p4)

cat("\nDone.\n")

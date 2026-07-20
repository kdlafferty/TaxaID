# sequence_similarity_matrix.R
#
# Species-by-species sequence similarity matrix for a genus.
# Rows and columns = species; cells = median p_match across all sequence pairs
# for that species combination (diagonal = within-species).
#
# Output:
#   - Console: n sequences, species list, summary stats per pair type
#   - Matrix table (wide format, printed + saved as CSV)
#   - Heatmap plot (ggplot2 tile)
#   - Histogram of all between-species pair distributions
# ==============================================================================

library(TaxaLikely)
library(ggplot2)
library(dplyr)
library(tidyr)

# ==============================================================================
# PARAMETERS
# ==============================================================================
BARCODE_TERM <- "COI"
TAXA         <- "Calidris"          # fetch the whole genus
RANK_SYSTEM  <- c("family","genus","species")
CACHE_DIR    <- file.path(
  "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics",
  "cache_calidris"
)

OUT_DIR      <- file.path(
  "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics"
)

# Aggregation function for within-cell p_match (median is robust to outliers)
AGG_FUN      <- median

# ==============================================================================
# 1. FETCH
# ==============================================================================
cat("=== Fetching sequences ===\n")

reference_df <- fetch_ncbi_reference_sequences(
  taxa         = TAXA,
  barcode_term = BARCODE_TERM,
  rank_system  = RANK_SYSTEM,
  cache_dir    = NULL
)
#will return error if it fails at NCBI.
#
cat(sprintf("Sequences fetched:  %d\n", nrow(reference_df)))
cat(sprintf("Unique species:     %d\n", length(unique(reference_df$species))))
cat("\nSequences per species:\n")
sp_counts <- sort(table(reference_df$species), decreasing = TRUE)
print(sp_counts)
cat("\n")

# ==============================================================================
# 2. BUILD SEQUENCE MATRIX
# ==============================================================================
cat("=== Building pairwise sequence matrix ===\n")

seq_matrix <- build_sequence_matrix(
  reference_df,
  rank_system        = RANK_SYSTEM,
  filter_unnamed     = TRUE,
  max_seqs_per_taxon = NULL    # retain all — seqs typically <50/sp
)

cat(sprintf("Pairwise comparisons: %d\n\n", nrow(seq_matrix)))

# ==============================================================================
# 3. CLASSIFY PAIRS
# ==============================================================================
sm <- seq_matrix |>
  filter(!is.na(species.x), species.x != "",
         !is.na(species.y), species.y != "") |>
  mutate(
    same_species = species.x == species.y,
    pair_type = if_else(same_species, "within-species", "between-species"),
    # Short species labels for matrix display
    sp_x = sub(paste0(TAXA," "), paste0(substr(TAXA, 1, 1),". "), species.x),
    sp_y = sub(paste0(TAXA," "), paste0(substr(TAXA, 1, 1),". "), species.y)
  )




cat("Pair type counts:\n")
print(table(sm$pair_type))
cat("\n")

# ==============================================================================
# 4. AGGREGATE TO SPECIES x SPECIES MATRIX
# ==============================================================================
# Summarise each directed pair (sp_x → sp_y) then symmetrise
agg <- sm |>
  group_by(species.x, species.y, sp_x, sp_y) |>
  summarise(
    n_pairs      = n(),
    median_pmatch = AGG_FUN(p_match),
    mean_pmatch  = mean(p_match),
    min_pmatch   = min(p_match),
    max_pmatch   = max(p_match),
    pct_exact    = round(100 * mean(p_match == 1.0), 1),
    .groups      = "drop"
  )

# Symmetrise: average the two directed medians so the matrix is symmetric
sym <- bind_rows(
  agg |> rename(a = species.x, b = species.y,
                la = sp_x,   lb = sp_y),
  agg |> rename(a = species.y, b = species.x,
                la = sp_y,   lb = sp_x)
) |>
  group_by(a, b, la, lb) |>
  summarise(median_pmatch = mean(median_pmatch),
            n_pairs       = sum(n_pairs),
            .groups = "drop")

# ==============================================================================
# 5. PIVOT TO WIDE MATRIX
# ==============================================================================
# Order species by hierarchical clustering of between-species distances so
# similar species cluster together in the heatmap
between_wide <- sym |>
  filter(a != b) |>
  select(a, b, median_pmatch) |>
  pivot_wider(names_from = b, values_from = median_pmatch, values_fill = NA)

sp_levels <- sort(unique(c(sym$a, sym$b)))  # fallback ordering

# Attempt cluster ordering if there are enough species
if (length(sp_levels) >= 3) {
  tryCatch({
    dist_wide <- sym |>
      filter(a != b) |>
      mutate(dist = 1 - median_pmatch) |>
      select(a, b, dist) |>
      pivot_wider(names_from = b, values_from = dist, values_fill = NA)

    sp_mat <- as.matrix(dist_wide[, -1])
    rownames(sp_mat) <- dist_wide$a
    sp_mat[is.na(sp_mat)] <- 0.5  # impute missings at midpoint
    sp_mat <- (sp_mat + t(sp_mat)) / 2  # symmetrise
    hc <- hclust(as.dist(sp_mat), method = "average")
    sp_levels <- hc$labels[hc$order]
    cat("Species ordered by hierarchical clustering (UPGMA on median distance).\n\n")
  }, error = function(e) {
    message("Cluster ordering failed, using alphabetical: ", e$message)
  })
}

sym <- sym |>
  mutate(a = factor(a, levels = sp_levels),
         b = factor(b, levels = sp_levels),
         la = factor(la, levels = sub(paste0(TAXA," "), paste0(substr(TAXA, 1, 1),". "), sp_levels)),
         lb = factor(lb, levels = sub(paste0(TAXA," "), paste0(substr(TAXA, 1, 1),". "), sp_levels)))



# Wide numeric matrix (species x species, sorted)
matrix_wide <- sym |>
  select(a, b, median_pmatch) |>
  pivot_wider(names_from = b, values_from = median_pmatch) |>
  arrange(a) |>
  select(a, all_of(sp_levels))

cat("=== Species x species median p_match matrix ===\n")
print(matrix_wide, n = 100, width = Inf)
cat("\n")

# Save CSV
csv_path <- file.path(OUT_DIR, paste0(TAXA,"_",BARCODE_TERM,"_similarity_matrix.csv"))
write.csv(matrix_wide, csv_path, row.names = FALSE, na = "")
cat(sprintf("Matrix saved: %s\n\n", csv_path))



# ==============================================================================
# 6. SUMMARY STATS
# ==============================================================================
within_sm   <- sm |> filter(pair_type == "within-species")
between_sm  <- sm |> filter(pair_type == "between-species")

p_self_overall  <- mean(within_sm$p_match == 1.0)
p_cross_overall <- mean(between_sm$p_match == 1.0)

cat("=== Summary ===\n")
cat(sprintf("Within-species:    n = %d pairs | median p_match = %.4f | %%.exact = %.1f%%\n",
            nrow(within_sm), median(within_sm$p_match),
            100 * p_self_overall))
cat(sprintf("Between-species:   n = %d pairs | median p_match = %.4f | %%.exact = %.1f%%\n",
            nrow(between_sm), median(between_sm$p_match),
            100 * p_cross_overall))
if (p_cross_overall > 0) {
  cat(sprintf("LR(H1 vs cross) @100%% rule: %.2f\n", p_self_overall / p_cross_overall))
} else {
  cat("LR(H1 vs cross) @100% rule: Inf  (no between-species exact matches)\n")
}

cat("\nPer-species within-species summary:\n")
per_sp <- within_sm |>
  group_by(species.x) |>
  summarise(
    n_pairs      = n(),
    median_pm    = round(median(p_match), 4),
    pct_exact    = round(100 * mean(p_match == 1.0), 1),
    .groups      = "drop"
  ) |>
  arrange(desc(median_pm))
print(per_sp, n = 50)
cat("\n")

# ==============================================================================
# 7. HEATMAP
# ==============================================================================
# Use short labels and mark within-species diagonal
heatmap_df <- sym |>
  mutate(
    is_self    = as.character(a) == as.character(b),
    label_cell = sprintf("%.3f", median_pmatch)
  )

# Reasonable text size: only print cell values if species count is small
n_sp         <- length(sp_levels)
show_text    <- n_sp <= 20
text_size_px <- if (n_sp <= 15) 2.8 else 2.2

p_heat <- heatmap_df |>
  ggplot(aes(x = lb, y = la, fill = median_pmatch)) +
  geom_tile(colour = "white", linewidth = 0.4) +
  { if (show_text)
      geom_text(aes(label = label_cell),
                size = text_size_px, colour = "black")
  } +
  geom_tile(data = heatmap_df |> filter(is_self),
            colour = "grey20", fill = NA, linewidth = 0.9) +
  scale_fill_gradientn(
    colours  = c("#d73027", "#fc8d59", "#fee090", "#e0f3f8", "#74add1", "#4575b4"),
    values   = scales::rescale(c(0.75, 0.85, 0.92, 0.96, 0.99, 1.0)),
    limits   = c(0.75, 1.0),
    na.value = "grey90",
    name     = "Median\np_match"
  ) +
  labs(

    title    = paste0(TAXA," ",BARCODE_TERM," pairwise sequence similarity"),
    subtitle = sprintf("Median p_match across all sequence pairs  |  n species = %d", n_sp),
    x        = NULL, y = NULL
  ) +
  theme_bw(base_size = 11) +
  theme(
    axis.text.x  = element_text(angle = 45, hjust = 1, size = 9,
                                 face = "italic"),
    axis.text.y  = element_text(size = 9, face = "italic"),
    panel.grid   = element_blank(),
    legend.key.height = unit(1.2, "cm")
  )

print(p_heat)

# ==============================================================================
# 8. BETWEEN-SPECIES PAIR DISTRIBUTION
# ==============================================================================
# Histogram of all between-species p_match values, coloured by pair
p_between <- between_sm |>
  filter(p_match >= 0.75) |>
  mutate(pair_label = paste0(sp_x, " / ", sp_y)) |>
  ggplot(aes(x = p_match)) +
  geom_histogram(binwidth = 0.005, fill = "#d7191c", colour = "white",
                 alpha = 0.8, linewidth = 0.2) +
  geom_vline(xintercept = 1.0, linetype = "dashed", linewidth = 0.7) +
  labs(


    title    = paste0("Between-species ",BARCODE_TERM," similarity — all ",TAXA," pairs"),
    subtitle = sprintf("n = %d cross-species sequence pairs", nrow(between_sm)),
    x        = "p_match",
    y        = "Number of pairs"
  ) +
  theme_bw(base_size = 12)

print(p_between)

# ==============================================================================
# 9. SORTED BETWEEN-SPECIES PAIR SUMMARY TABLE
# ==============================================================================
pair_summary <- agg |>
  filter(species.x != species.y) |>
  arrange(desc(median_pmatch)) |>
  select(sp_x, sp_y, n_pairs, median_pmatch, mean_pmatch, min_pmatch,
         max_pmatch, pct_exact)

cat("=== Between-species pair summary (sorted by median p_match, desc) ===\n")
print(pair_summary, n = 200, width = Inf)

cat("\nDone.\n")
saveRDS(obj, path)


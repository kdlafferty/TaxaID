# ==============================================================================
# score_accuracy_demo.R
# Demonstrates the limits of using match scores alone for taxonomic assignment.
# Produces a figure showing P(correct assignment) vs match score at three
# taxonomic ranks (species, genus, family) — using logistic regression on real
# reference-vs-reference comparisons.
#
# Key insight: Even at high match scores (~95%), species-level accuracy is far
# from certain. This motivates TaxaLikely's generative framework, which uses
# both score AND gap to evaluate likelihoods under competing hypotheses.
#
# Adapted from: accuracy_from_match_Mifish2.R
# Uses: TaxaLikely (build_sequence_matrix), TaxaTools (clean_taxon_names)
# ==============================================================================

library(dplyr)
library(tidyr)
library(lme4)
library(TaxaTools)

# ==============================================================================
# 1. LOAD REFERENCE SEQUENCES
# ==============================================================================
# Option A: From a FASTA file with semicolon-delimited taxonomy in headers
#   Format: accession;kingdom;phylum;class;order;family;genus;species
#
# Option B: Use TaxaLikely::read_reference_fasta() with a separate taxonomy table
#   reference_df <- TaxaLikely::read_reference_fasta(fasta_path, taxonomy, rank_system)

rank_system <- c("family", "genus", "species")

# --- Option A: Parse FASTA with semicolon-delimited headers ------------------
# Update this path to your FASTA file
fasta_path <- file.choose()  # e.g., "MiFishU_taxDB_20240129.fasta"

dna_sequences <- Biostrings::readDNAStringSet(fasta_path)

# Parse semicolon-delimited headers: accession;kingdom;phylum;...;species
header_parts <- strsplit(names(dna_sequences), split = ";")
header_df <- do.call(rbind, header_parts) |> as.data.frame()
colnames(header_df) <- c("accession", "kingdom", "phylum", "class",
                          "order", "family", "genus", "species")

# Build reference_df in TaxaLikely format
reference_df <- header_df |>
  mutate(
    composite_id = accession,
    sequence     = as.character(dna_sequences),
    # Clean species names: drop abbreviations, require binomial
    species = ifelse(grepl("\\s", species), species, NA_character_)
  )

# --- Optional: Filter to families of interest --------------------------------
# keep_families <- c("Cottidae", "Gobiidae", "Fundulidae", "Embiotocidae")
# reference_df <- reference_df |> filter(family %in% keep_families)

# --- Optional: Filter to a taxonomic class -----------------------------------
reference_df <- reference_df |> filter(class == "Actinopteri")

# Clean species names using TaxaTools
reference_df$species <- TaxaTools::clean_taxon_names(reference_df$species)
reference_df<-reference_df|>filter(!is.na(species) & species != "")
reference_df<-reference_df[grepl(" ", reference_df$species), ]# Drop rows with missing species (needed for species-level accuracy)
reference_df <- reference_df %>%
  group_by(genus) %>%
  filter(n_distinct(species) != 1) %>%
  ungroup() #exclude cases where there is just one species per genus.
message(sprintf(
  "Reference: %d sequences, %d species, %d genera, %d families",
  nrow(reference_df),
  length(unique(reference_df$species)),
  length(unique(reference_df$genus)),
  length(unique(reference_df$family))
))

# ==============================================================================
# 2. BUILD PAIRWISE MATCH MATRIX
# ==============================================================================
# TaxaLikely::build_sequence_matrix() handles alignment, distance computation,
# and taxonomy joining in one call.

ref_matrix <- TaxaLikely::build_sequence_matrix(
  reference_df = reference_df,
  rank_system  = rank_system,
  max_dist     = 0.50   # keep pairs up to 50% divergence for the accuracy demo
)

message(sprintf("Pairwise comparisons: %d", nrow(ref_matrix)))

# ==============================================================================
# 3. FLAG OUTLIER SEQUENCES (optional)
# ==============================================================================
# Within-species pairs with unusually low matches suggest mislabeled references.
# TaxaLikely::flag_reference_errors() does this systematically, but here we
# use a quick MAD-based filter for the demo.

outliers <- ref_matrix |>
  filter(species.x == species.y) |>
  mutate(
    median_val = median(p_match),
    mad_val    = mad(p_match),
    is_outlier = (median_val - p_match) > 3 * mad_val
  ) |>
  filter(is_outlier)

if (nrow(outliers) > 0L) {
  message(sprintf("Flagged %d outlier within-species pairs (MAD > 3)", nrow(outliers)))
  # Remove outlier pairs from the matrix
  outlier_ids <- unique(c(outliers$id_x, outliers$id_y))
  ref_matrix <- ref_matrix |>
    filter(!id_x %in% outlier_ids & !id_y %in% outlier_ids)
}

# ==============================================================================
# 4. AGGREGATE TO SPECIES-VS-SPECIES MEDIANS
# ==============================================================================
# Multiple sequences per species create redundant pairs. Collapse to the median
# match between each species pair to avoid over-representing well-sequenced taxa.

match_summary <- ref_matrix |>
  group_by(species.x, species.y, genus.x, genus.y, family.x, family.y) |>
  summarize(p_match = median(p_match), .groups = "drop") |>
  # Flag correctness at each rank
  mutate(
    species_correct = as.integer(species.x == species.y),
    genus_correct   = as.integer(genus.x == genus.y),
    family_correct  = as.integer(family.x == family.y)
  ) |>
  # Per-query metrics (treating species.x as the "query")
  group_by(species.x) |>
  mutate(
    max_match     = max(p_match),
    match_diff    = max_match - p_match,
    # Gap to second-best (the "flatness" metric — precursor to TaxaLikely's gap)
    second_best   = ifelse(n() > 1L, sort(p_match, decreasing = TRUE)[2L], 0),
    gap_to_second = max_match - second_best,
    count_ge      = purrr::map_int(p_match, ~ sum(p_match >= .x)) - 1L
  ) |>
  ungroup() |>
  mutate(log_count_ge = log(count_ge + 1))

message(sprintf("Species-vs-species pairs: %d", nrow(match_summary)))

# ==============================================================================
# 5. FIT LOGISTIC MODELS
# ==============================================================================
# P(correct assignment | match score, gap, rank count)
# This is the "naive" discriminative approach — it asks "given these features,
# is this assignment correct?" TaxaLikely instead asks "how likely are these
# features under each hypothesis?"

#logit_species <- glm(
  #species_correct ~ log_count_ge + match_diff + p_match + p_match:match_diff,
  #data = match_summary, family = binomial()
#)
#logit_genus <- glm(
  #genus_correct ~ log_count_ge + match_diff + p_match + p_match:match_diff,
  #data = match_summary, family = binomial()
#)
#logit_family <- glm(
  #family_correct ~ log_count_ge + match_diff + p_match + p_match:match_diff,
  #data = match_summary, family = binomial()
#)

logit_species <- glm(
  species_correct ~ p_match,
  data = match_summary, family = binomial()
)
logit_genus <- glm(
  genus_correct ~ p_match,
  data = match_summary, family = binomial()
)
logit_family <- glm(
  family_correct ~ p_match,
  data = match_summary, family = binomial()
)

# ==============================================================================
# 6. PREDICT AND PLOT
# ==============================================================================
# Predict accuracy across the score range, holding gap and rank count at their
# "best case" values (match_diff = 0, count = 1). This shows the UPPER BOUND
# of what score alone can tell you — and it's still not great at species level.

new_data <- data.frame(
  p_match    = seq(0.50, 1.00, by = 0.005),
  match_diff = 0,
  log_count_ge = 0
)

plot_data <- new_data |>
  mutate(
    species = predict(logit_species, newdata = new_data, type = "response"),
    genus   = predict(logit_genus,   newdata = new_data, type = "response"),
    family   = predict(logit_family,   newdata = new_data, type = "response")
  )

# --- Base R figure (no ggplot2 dependency) ------------------------------------
par(mar = c(5, 5, 3, 1), family = "sans")

plot(NULL, xlim = c(0.70, 1.00), ylim = c(0, 1),
     xlab = "Match Score (Proportion Identity)",
     ylab = "Predicted P(Correct Assignment)",
     main = "Score alone is a poor predictor of species-level accuracy for Palmyra fishes",
     axes = FALSE)
axis(1, at = seq(0.70, 1.00, by = 0.05),
     labels = paste0(seq(70, 100, by = 5), "%"))
axis(2, at = seq(0, 1, by = 0.25))

polygon(c(plot_data$p_match, rev(plot_data$p_match)),
        c(plot_data$family, rep(0, nrow(plot_data))),
        col = adjustcolor("green", 0.10), border = NA)
polygon(c(plot_data$p_match, rev(plot_data$p_match)),
        c(plot_data$genus, rep(0, nrow(plot_data))),
        col = adjustcolor("#2166AC", 0.10), border = NA)
polygon(c(plot_data$p_match, rev(plot_data$p_match)),
        c(plot_data$species, rep(0, nrow(plot_data))),
        col = adjustcolor("#B2182B", 0.10), border = NA)

# Lines
lines(plot_data$p_match, plot_data$family, lwd = 3, col = "green")
lines(plot_data$p_match, plot_data$genus,   lwd = 3, col = "#2166AC")
lines(plot_data$p_match, plot_data$species, lwd = 3, col = "#B2182B")

# Reference lines
abline(h = 0.95, lty = 3, col = "grey50")
text(.95, 0.98, "95% confidence", adj = 0, cex = 0.75, col = "grey50")
abline(v = 0.97, lty = 2, col = "grey40", lwd = 1.5)
text(0.972, 0.15, "97% match", adj = 0, cex = 0.8, col = "grey40", font = 3)

legend("topleft",
       legend = c("Family","Genus", "Species"),
       col    = c( "green","#2166AC", "#B2182B"),
       lwd    = 3, bty = "n", cex = 0.9)

box()

# ==============================================================================
# INTERPRETATION
# ==============================================================================
# Even at 97% match score, species-level accuracy is well below 95% because:
#   1. Many species pairs have overlapping score distributions
#   2. A high score does not guarantee the BEST match — the gap matters
#   3. The model has no way to say "the true species isn't in the database"
#
# TaxaLikely addresses all three problems:
#   1. It models score distributions per species (hierarchical shrinkage)
#   2. It evaluates score AND gap jointly (bivariate normal)
#   3. It includes H2/H3 hypotheses for unreferenced taxa
#
# This figure is used in the TaxaID presentation to motivate the generative
# framework before introducing the 2D likelihood landscape.
# ==============================================================================

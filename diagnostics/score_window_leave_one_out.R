# ==============================================================================
# Leave-one-out check of TaxaMatch::blast_sequences()'s score_window filter
# (ecosystem soundness-review item 14, TaxaMatch::blast_sequences::score_window)
# ==============================================================================
#
# The review's finding: blast_sequences()'s score window keeps only hits within
# score_range (default 2 percentage points) of each query's TOP hit. If a
# confusable congener happens to score higher than the query's own true species
# (a real possibility for tight congeneric divergence or an incomplete
# reference), and the gap exceeds score_range, the correct species is dropped
# from the candidate set BEFORE TaxaLikely/TaxaAssign ever see it -- not just
# down-weighted, entirely absent, with no way for anything downstream to
# recover it. Field-tested only on 5 easy PtConception queries with clear top
# hits >= 98%, never stress-tested against a taxonomically dense genus.
#
# This script reuses two REAL reference-vs-reference distance matrices already
# built and saved in this directory (sebastes_seq_matrix.rds, 54 Sebastes
# species -- rockfish, a genuinely species-rich, confusable genus;
# chromis_seq_matrix.rds, 26 Chromis species) from the manuscript-support
# session that found the Paralabrax/amplicon-window footgun (see
# sebastes_chromis_confirmation.R) -- both already filtered to the registered
# MiFish amplicon window, so this is a fair, apples-to-apples test of the
# SCORE_WINDOW question specifically, not confounded by the amplicon-window
# issue item 13 just fixed separately.
#
# Method: for each reference sequence (id_x) with at least one real
# within-species neighbor, treat it as a leave-one-out BLAST query against
# every OTHER sequence in the same matrix (id_y != id_x). Compute:
#   best_self  = the best (highest %identity) match to another sequence of
#                its OWN true species
#   best_cross = the best match to any OTHER species (a real congener, since
#                both matrices are single-genus)
# If best_cross > best_self, the true species would NOT be the top BLAST hit
# for this query -- and if best_cross - best_self > score_range, the true
# species sits entirely outside the score window and is silently dropped from
# blast_sequences()'s output.
# ==============================================================================

library(dplyr)

SCORE_RANGE <- 2    # blast_sequences()'s own default
MIN_SCORE   <- 70   # blast_sequences()'s own default min_score floor

analyze_score_window <- function(seq_matrix, score_range = SCORE_RANGE,
                                  min_score = MIN_SCORE, label = "") {
  sm <- seq_matrix
  sm$pident <- sm$p_match * 100
  sm <- sm[sm$pident >= min_score & sm$id_x != sm$id_y, ]

  per_seq <- sm |>
    group_by(id_x, species.x) |>
    summarise(
      best_self  = suppressWarnings(max(pident[species.y == species.x], na.rm = TRUE)),
      best_cross = suppressWarnings(max(pident[species.y != species.x], na.rm = TRUE)),
      .groups = "drop"
    ) |>
    mutate(
      best_self  = ifelse(is.infinite(best_self),  NA_real_, best_self),
      best_cross = ifelse(is.infinite(best_cross), NA_real_, best_cross)
    ) |>
    # Only queries with a real same-species neighbor have a "true species" hit
    # that could be lost -- a true singleton species has nothing to compare.
    filter(!is.na(best_self))

  per_seq <- per_seq |>
    mutate(
      true_species_is_top = is.na(best_cross) | best_self >= best_cross,
      congener_gap         = ifelse(!true_species_is_top, best_cross - best_self, NA_real_),
      true_species_dropped = !true_species_is_top & !is.na(congener_gap) &
                             congener_gap > score_range
    )

  n_total       <- nrow(per_seq)
  n_congener_top <- sum(!per_seq$true_species_is_top)
  n_dropped     <- sum(per_seq$true_species_dropped, na.rm = TRUE)

  cat(sprintf("\n=== %s (n = %d sequences with >=1 within-species neighbor) ===\n",
              label, n_total))
  cat(sprintf("  Congener outscores true species (not top hit):        %d (%.1f%%)\n",
              n_congener_top, 100 * n_congener_top / n_total))
  cat(sprintf("  ...of those, gap > score_range=%d -> TRUE SPECIES DROPPED: %d (%.1f%% of all queries)\n",
              score_range, n_dropped, 100 * n_dropped / n_total))
  if (n_congener_top > 0) {
    gaps <- per_seq$congener_gap[!per_seq$true_species_is_top]
    cat(sprintf("  Congener-gap distribution (pts) when congener wins: min=%.2f median=%.2f max=%.2f\n",
                min(gaps), stats::median(gaps), max(gaps)))
  }

  invisible(per_seq)
}

sebastes_result <- analyze_score_window(
  readRDS(file.path("diagnostics", "sebastes_seq_matrix.rds")),
  label = "Sebastes (54 species, real MiFish-window-filtered 12S data)"
)

chromis_result <- analyze_score_window(
  readRDS(file.path("diagnostics", "chromis_seq_matrix.rds")),
  label = "Chromis (26 species, real MiFish-window-filtered 12S data)"
)

# Third real dataset: the 6-genus PtConception 12S reference set from
# TaxaLikely::sequence_likelihood_workflow.R's own REFERENCE_TAXA
# (Clinocottus, Rhacochilus, Gibbonsia, Oligocottus, Embiotoca, Phanerodon --
# Rhacochilus returns 0 real NCBI hits, a separate known gap, see that
# workflow's own note). Rebuild via (uses TaxaLikely's own NCBI cache, fast):
#   rd <- TaxaLikely::fetch_ncbi_reference_sequences(
#     taxa = c("Clinocottus","Rhacochilus","Gibbonsia","Oligocottus",
#              "Embiotoca","Phanerodon"),
#     barcode_term = "12S", rank_system = c("family","genus","species"),
#     max_per_species = 5L)
#   sm <- TaxaLikely::build_sequence_matrix(rd, rank_system = c("family","genus","species"))
#   saveRDS(sm, "diagnostics/ptconception6genus_seq_matrix.rds")
ptconception_result <- analyze_score_window(
  readRDS(file.path("diagnostics", "ptconception6genus_seq_matrix.rds")),
  label = "PtConception 6-genus (10 species, real 12S data, smaller/sparser reference set)"
)

cat("\n=== Summary ===\n")
cat("See TaxaMatch/CLAUDE.md's Session 151 note and\n",
    "ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 14\n",
    "for the interpretation and any resulting parameter change.\n")

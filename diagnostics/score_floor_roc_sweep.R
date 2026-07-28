# score_floor_roc_sweep.R
#
# Diagnostic: what score floor should TaxaAssign::score_consensus()'s
# min_score/rank_thresholds and TaxaAssign::assign_taxa_llm()'s
# score_threshold actually use, AND (new) is a given Bayesian-pipeline
# observation's raw match score itself strong enough to defend the rank at
# which it was resolved? Every pair in seq_matrix has known species/genus/
# family identity on both sides, so TPR/FPR at any threshold are computable
# facts, not proxies -- unlike the posterior/LLM-shape sweeps elsewhere in
# this directory.
#
# REDESIGNED (2026-07-23) from the original single-tier, row-pooled version,
# after a real design conversation surfaced two problems with that version:
#
# 1. ONE Youden's J (species-tier only, TP=within-species/FP=congeneric) is
#    the wrong objective for a genus- or family-tier threshold -- each rank
#    needs its OWN TP/FP definition (TP = "same taxon at this rank",
#    FP = the NEAREST confusable negative class). Now computed separately
#    per rank: species (TP=within-species, FP=congeneric), genus (TP=same-
#    genus [within-species OR congeneric], FP=confamilial), family
#    (TP=same-family [...OR confamilial], FP=cross-family). Family is the
#    real ceiling for this data -- seq_matrix has no order/class/phylum
#    columns at all (confirmed directly), so cross-family silently pools
#    every rank beyond family; climbing higher would need build_sequence_
#    matrix() itself extended to carry those columns, not attempted here.
#
# 2. Naive row-weighted pooling across ALL genera/families is dominated by
#    whichever taxon has the most reference data. Confirmed as a REAL,
#    measurable bug (not hypothetical) in the sibling problem this exact
#    conversation found in TaxaLikely::train_likelihood_model()'s H2 pooled
#    delta: Sebastes is 30.9% of all raw congeneric PAIRS in this real 12S
#    seq_matrix, and even after collapsing to one best-match-per-reference-
#    SEQUENCE (see below), still 7% of what reaches the pooled congener
#    population -- pulling train_likelihood_model()'s pooled H2 delta ~8-9%
#    toward "congeners are more competitive than typical" for every one of
#    the 92/219 (42%) genera in this data with only one referenced species,
#    which have no data of their own to correct it. Fixed there via an lme4
#    random-intercept hierarchy (genus/family as random effects) reusing the
#    identical mechanism train_likelihood_model() already applies to its own
#    H1 global mean -- see TaxaLikely/CLAUDE.md's matching session note.
#
#    This script cannot reuse that lme4 mechanism directly -- the quantities
#    here are empirical FPR-at-threshold CURVES, not single Gaussian means,
#    and deliberately staying nonparametric/model-free is the whole point:
#    the "*_confusion_risk" columns this script prototypes are meant as an
#    INDEPENDENT check on the likelihood model's own conclusions, not a
#    second application of it. So "similar logic, different mechanism":
#    the SAME principle (population-level average across TAXA, not across
#    raw rows) is applied via genus-/family-EQUAL-WEIGHTED averaging plus
#    Empirical-Bayes shrinkage (w = n/(n+prior_weight), the identical form
#    already used for TaxaLikely's H1/H2 shrinkage) -- computed directly on
#    real pair data, no parametric model fit.
#
#    A second, related correction: like train_likelihood_model()'s own
#    h1_data/congener_pool, this script now collapses to ONE ROW PER
#    REFERENCE SEQUENCE's single best match within each pair-type category,
#    instead of every raw pairwise comparison. Two reasons: (a) without it, a
#    heavily-resequenced species/genus floods a TPR/FPR estimate through
#    sheer O(k^2) combinatorial pair-count, on top of (not instead of) the
#    genus/family-weighting problem above; (b) a sequence's single BEST match
#    against a competing category is also a more faithful stand-in for what a
#    real query actually sees at inference (one best hit per competing
#    candidate), not an average over every possible reference pair.
#
# Real data check before any of this (feeds MIN_OWN_TAXA_FOR_SUPPORT below):
# ~42% of genera and ~67% of families in this real 12S data have only ONE
# referenced species/genus -- a PERMANENT structural zero (more sequencing of
# OTHER taxa won't change it), not a small-sample problem that resolves with
# more data. Empirical-Bayes shrinkage handles this gracefully (weight -> 0,
# full fallback to the pooled curve) with no separate NA-emitting floor logic
# needed -- matching how TaxaLikely::H2_Lookup itself already works (a genus
# with no data simply gets no lookup row and silently uses the pooled
# default).
#
# KEY PARAMETERS -- edit these for each run
# ---------------------------------------------------------------------------
SM_PATH <- file.path(
  "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception",
  "PtConMifishSchulte_seq_matrix.rds"       # swap for 18S: PtCon18SSchulte_seq_matrix.rds
)

EXCLUDE_FAMILIES <- character(0)

THRESHOLD_GRID <- seq(70, 100, by = 1)   # percent-identity scale, matching min_score/score_threshold
PRIOR_WEIGHT    <- 10.0                  # same default TaxaLikely::train_likelihood_model() uses for
                                          # its own Empirical Bayes shrinkage -- reused here for
                                          # consistency, NOT independently validated for this specific
                                          # use (a threshold-rate estimate, not a Gaussian mean). Revisit
                                          # if real *_confusion_risk behavior looks miscalibrated.

CURRENT_DEFAULTS <- c(score_consensus_min_score = 0, assign_taxa_llm_score_threshold = 80)
# ---------------------------------------------------------------------------

library(dplyr)
library(tidyr)
library(purrr)

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
  filter(species.x != "" & !is.na(species.x))

cat("Pair type counts (raw, blank-filtered, pre-collapse):\n")
print(table(sm$pair_type))
cat("\n")

# ---------------------------------------------------------------------------
# STEP 1: per-sequence best-match collapse (mirrors TaxaLikely::train_
# likelihood_model()'s h1_data/max_congener_score convention)
# ---------------------------------------------------------------------------
collapsed <- sm |>
  group_by(id_x, pair_type) |>
  slice_max(pct_identity, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(id_x, genus = genus.x, family = family.x, species = species.x,
            pair_type, pct_identity)

cat(sprintf("After per-sequence best-match collapse: %d rows (was %d raw pairs)\n\n",
            nrow(collapsed), nrow(sm)))

# ---------------------------------------------------------------------------
# STEP 2: rate-at-threshold curves, stratified by taxon group, with
# genus-/family-/species-EQUAL-WEIGHTED pooling and Empirical Bayes shrinkage
# ---------------------------------------------------------------------------
.rate_curve_by_group <- function(df, thresholds) {
  # df must have columns: group, pct_identity
  df |>
    group_by(group) |>
    summarise(
      n    = dplyr::n(),
      rate = list(vapply(thresholds, function(t) mean(pct_identity >= t), numeric(1))),
      .groups = "drop"
    ) |>
    tidyr::unnest_longer(rate, indices_to = "ti", values_to = "rate") |>
    mutate(threshold = thresholds[ti]) |>
    select(group, threshold, n, rate)
}

.equal_weighted_pooled <- function(rate_curve_by_group) {
  # Population-level curve = mean ACROSS GROUPS (one vote per taxon),
  # not across raw rows -- the direct fix for the Sebastes-style dominance
  # problem, at whatever grouping level is passed in (species/genus/family).
  rate_curve_by_group |>
    group_by(threshold) |>
    summarise(pooled_rate = mean(rate), .groups = "drop")
}

.eb_shrink <- function(rate_curve_by_group, pooled, prior_weight = PRIOR_WEIGHT) {
  rate_curve_by_group |>
    left_join(pooled, by = "threshold") |>
    mutate(
      w           = n / (n + prior_weight),
      shrunk_rate = w * rate + (1 - w) * pooled_rate
    )
}

# TP populations (own tier's positive class: "same taxon at this rank"),
# equal-weighted at that SAME rank -- mirrors H1's species-level structure.
within_sp   <- collapsed |> filter(pair_type == "within-species")
same_genus_pop <- collapsed |> filter(pair_type %in% c("within-species", "congeneric"))
same_fam_pop   <- collapsed |> filter(pair_type %in% c("within-species", "congeneric", "confamilial"))

tpr_species_curves <- within_sp     |> rename(group = species) |> .rate_curve_by_group(THRESHOLD_GRID)
tpr_genus_curves   <- same_genus_pop |> rename(group = genus)   |> .rate_curve_by_group(THRESHOLD_GRID)
tpr_family_curves  <- same_fam_pop   |> rename(group = family)  |> .rate_curve_by_group(THRESHOLD_GRID)

pooled_tpr_species <- .equal_weighted_pooled(tpr_species_curves)
pooled_tpr_genus   <- .equal_weighted_pooled(tpr_genus_curves)
pooled_tpr_family  <- .equal_weighted_pooled(tpr_family_curves)

# FP populations (the NEAREST confusable negative class for this tier),
# equal-weighted one rank coarser -- mirrors H2's genus-level structure.
congeneric  <- collapsed |> filter(pair_type == "congeneric")
confamilial <- collapsed |> filter(pair_type == "confamilial")
crossfamily <- collapsed |> filter(pair_type == "cross-family")

fpr_congeneric_by_genus   <- congeneric  |> rename(group = genus)  |> .rate_curve_by_group(THRESHOLD_GRID)
fpr_confamilial_by_family <- confamilial |> rename(group = family) |> .rate_curve_by_group(THRESHOLD_GRID)

pooled_fpr_congeneric  <- .equal_weighted_pooled(fpr_congeneric_by_genus)
pooled_fpr_confamilial <- .equal_weighted_pooled(fpr_confamilial_by_family)
# cross-family has no rank above it in this data (structural ceiling, see
# header) -- a single global rate, no equal-weighting possible or needed.
pooled_fpr_crossfamily <- data.frame(
  threshold   = THRESHOLD_GRID,
  pooled_rate = vapply(THRESHOLD_GRID, function(t) mean(crossfamily$pct_identity >= t), numeric(1))
)

# Empirical-Bayes-shrunk per-genus / per-family curves -- the shrinkage
# TARGET is the equal-weighted pooled curve above, not the naive row-pooled
# one. This is what a real observation's species_confusion_risk/genus_confusion_risk would
# be evaluated against.
congeneric_shrunk  <- .eb_shrink(fpr_congeneric_by_genus,   pooled_fpr_congeneric)
confamilial_shrunk <- .eb_shrink(fpr_confamilial_by_family, pooled_fpr_confamilial)

# ---------------------------------------------------------------------------
# STEP 3: per-rank Youden's J -- properly bias-corrected, properly TP/FP-
# matched threshold for each rank (serves the "critique of a score-only
# approach" and "set the score-only comparison-pathway thresholds" purposes)
# ---------------------------------------------------------------------------
.youden_table <- function(pooled_tpr, pooled_fpr, tp_label, fp_label) {
  pooled_tpr |> rename(tpr = pooled_rate) |>
    inner_join(pooled_fpr |> rename(fpr = pooled_rate), by = "threshold") |>
    mutate(youden_j = tpr - fpr) |>
    arrange(threshold) |>
    rename(!!tp_label := tpr, !!fp_label := fpr)
}

species_roc <- .youden_table(pooled_tpr_species, pooled_fpr_congeneric,
                              "tpr_within_species", "fpr_congeneric")
genus_roc   <- .youden_table(pooled_tpr_genus, pooled_fpr_confamilial,
                              "tpr_same_genus", "fpr_confamilial")
family_roc  <- .youden_table(pooled_tpr_family, pooled_fpr_crossfamily,
                              "tpr_same_family", "fpr_crossfamily")

best_species <- species_roc[which.max(species_roc$youden_j), ]
best_genus   <- genus_roc[which.max(genus_roc$youden_j), ]
best_family  <- family_roc[which.max(family_roc$youden_j), ]

cat("=== Per-rank Youden's J-optimal thresholds (genus-/family-equal-weighted, bias-corrected) ===\n")
cat(sprintf("  SPECIES tier (TP=within-species, FP=congeneric):  threshold=%d  TPR=%.3f  FPR=%.3f  J=%.3f\n",
            best_species$threshold, best_species$tpr_within_species, best_species$fpr_congeneric, best_species$youden_j))
cat(sprintf("  GENUS   tier (TP=same-genus,     FP=confamilial):  threshold=%d  TPR=%.3f  FPR=%.3f  J=%.3f\n",
            best_genus$threshold, best_genus$tpr_same_genus, best_genus$fpr_confamilial, best_genus$youden_j))
cat(sprintf("  FAMILY  tier (TP=same-family,    FP=cross-family): threshold=%d  TPR=%.3f  FPR=%.3f  J=%.3f\n",
            best_family$threshold, best_family$tpr_same_family, best_family$fpr_crossfamily, best_family$youden_j))
cat("\n")

cat("=== Current defaults, evaluated on the bias-corrected species-tier curve ===\n")
.lookup <- function(roc, t) roc[which.min(abs(roc$threshold - t)), ]
print(.lookup(species_roc, CURRENT_DEFAULTS["score_consensus_min_score"]))
print(.lookup(species_roc, CURRENT_DEFAULTS["assign_taxa_llm_score_threshold"]))
cat("\n")

# ---------------------------------------------------------------------------
# STEP 4: *_confusion_risk diagnostic prototype (serves the post-hoc-rollup-
# candidate purpose) -- given an observation's own raw score and its winning
# candidate's genus/family, how much does the RAW SCORE ITSELF (independent
# of any trained likelihood model) support resolution at species / genus /
# family? Continuous, not boolean: literally P(a same-genus-but-different-
# species pair would score this high or higher), evaluated on the genus's
# OWN Empirical-Bayes-shrunk curve -- lower = stronger support. Meant as an
# ADDITIONAL, model-independent diagnostic -- see this conversation's own
# design discussion for why keeping it score-derived (not
# likelihood-derived) matters.
species_confusion_risk <- function(observed_score, genus) {
  row <- congeneric_shrunk |>
    filter(group == genus, threshold == round(observed_score))
  if (nrow(row) == 0L) {
    # genus never seen in training congener data at all -> pure pooled fallback
    pooled_fpr_congeneric$pooled_rate[
      which.min(abs(pooled_fpr_congeneric$threshold - observed_score))]
  } else {
    row$shrunk_rate[1]
  }
}

genus_confusion_risk <- function(observed_score, family) {
  row <- confamilial_shrunk |>
    filter(group == family, threshold == round(observed_score))
  if (nrow(row) == 0L) {
    pooled_fpr_confamilial$pooled_rate[
      which.min(abs(pooled_fpr_confamilial$threshold - observed_score))]
  } else {
    row$shrunk_rate[1]
  }
}

family_confusion_risk <- function(observed_score) {
  pooled_fpr_crossfamily$pooled_rate[
    which.min(abs(pooled_fpr_crossfamily$threshold - observed_score))]
}

cat("=== *_confusion_risk prototype: Sebastes (tight genus) vs. a data-matched contrast ===\n")
# Pick the second-most-data-rich genus as a real, non-cherry-picked contrast
# (not hand-selected for a favorable story).
contrast_genus <- fpr_congeneric_by_genus |>
  filter(group != "Sebastes") |>
  distinct(group, n) |>
  arrange(desc(n)) |>
  slice(1) |>
  pull(group)

for (g in c("Sebastes", contrast_genus)) {
  fam <- collapsed$family[match(g, collapsed$genus)]
  cat(sprintf("\n  Genus: %s (family: %s)\n", g, fam))
  for (s in c(90, 95, 98)) {
    cat(sprintf("    score=%d  species_confusion_risk=%.3f  genus_confusion_risk=%.3f  family_confusion_risk=%.3f\n",
                s, species_confusion_risk(s, g), genus_confusion_risk(s, fam), family_confusion_risk(s)))
  }
}
cat("\n")
cat("Interpretation: species_confusion_risk is P(a real congener of THIS genus would\n")
cat("score this high or higher) -- lower is stronger evidence FOR the species\n")
cat("call. Compare Sebastes vs. the contrast genus at the same raw score: a\n")
cat("tight genus like Sebastes should show much HIGHER species_confusion_risk (weaker\n")
cat("evidence) at the same score than a well-separated genus does.\n\n")

cat("Done.\n")

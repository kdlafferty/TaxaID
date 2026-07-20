# ==============================================================================
# Problem 1 rate estimate: how often is a referenced, locally-plausible species
# structurally absent from an observation's own candidate set?
# ==============================================================================
#
# Context (see ecosystem_docs/REENTRY_PROMPT_degraded_species_likelihood_thresholds.md
# and [[project_edge_case_error_taxa_design]] in the memory system for the full
# design conversation this grew out of):
#
# Candidate generation happens once, upstream of TaxaLikely: the match object
# keeps the best-scoring match per observation plus anything within "X units"
# of it (TaxaMatch::blast_sequences()'s score_range for a live BLAST run; an
# unknown, possibly-undocumented rule for an externally-supplied match table
# like this one -- PtConception's PercMatch/Accession columns never go
# through blast_sequences() at all). Only rows that survive that filter ever
# get a score/likelihood. Three outcomes for a query whose true species is
# NOT the top BLAST hit:
#   (1) true species still within X units -> still a candidate, ordinary
#       H1-vs-H2/H3 competition handles it (measured previously: 26.75%
#       parametric / 31.04% empirical within-genus congener-outscoring rate).
#   (2) true species is NOT referenced at all -> handled by the existing
#       unreferenced-candidate machinery (H2/H3). Working well, not this.
#   (3) true species IS referenced but scores more than X units below the
#       best -> NEVER becomes a candidate row. No likelihood can be built for
#       it after the fact without literally recomputing its score.
#
# This script estimates how often case (3)'s STRUCTURAL PRECONDITION arises
# in real production data: a species that is (a) locally plausible (real
# TaxaExpect occurrence prior at the focal site) and (b) genuinely referenced
# (has real accessions in reference_df) is nonetheless completely absent from
# an observation's own candidate rows, even though that observation DOES have
# at least one other candidate present in the same genus (ruling out "nothing
# in this genus was ever attempted", which is closer to case 2/4 territory).
#
# Deliberately NOT attempted here (would need the query's raw sequence or a
# seq_matrix-triangulation score estimate, neither built yet): confirming
# that the missing species was actually the CORRECT identification for that
# specific observation. This measures the population-level firing rate of
# the diagnostic signature itself (a locally-plausible referenced species is
# structurally missing), not a ground-truth-confirmed error rate. Cheap by
# construction -- no new alignment, no raw sequences, one pass over data
# already sitting on disk.
# ==============================================================================

library(dplyr)

DATA_DIR <- "~/My Drive/Rscripts/eDNA/PtConception"
PREFIX   <- "PtConMifishSchulte"
PLAUSIBILITY_THRESHOLD <- 1e-3   # matches identify_confident_observations()'s default

match_obj <- readRDS(file.path(DATA_DIR, paste0(PREFIX, "_match_obj.rds")))
priors    <- readRDS(file.path(DATA_DIR, paste0(PREFIX, "_taxaexpect_priors.rds")))
reference_df <- readRDS(file.path(DATA_DIR, paste0(PREFIX, "_reference_df.rds")))

# ---- resolve the single focal site (this is a _single_site workflow: every
#      observation is joined against ONE grid_id/main_habitat via
#      join_priors(site = list(...)); derived here as the grid_id with the
#      overwhelming majority of real (non-singleton-mirror) prior rows). ----
site_tab <- sort(table(priors$grid_id), decreasing = TRUE)
FOCAL_GRID <- names(site_tab)[1]
cat(sprintf("Focal grid_id (most-represented in taxaexpect_priors): %s (%d/%d rows)\n",
            FOCAL_GRID, site_tab[1], nrow(priors)))

focal_priors <- priors |>
  filter(grid_id == FOCAL_GRID, taxon_name_rank == "species") |>
  mutate(genus = sub(" .*$", "", taxon_name))

referenced_species <- unique(reference_df$species)

locally_plausible <- focal_priors |>
  filter(theta_mean > PLAUSIBILITY_THRESHOLD) |>
  mutate(is_referenced = taxon_name %in% referenced_species)

cat(sprintf("\nLocally-plausible species at focal site (theta_mean > %.0e): %d\n",
            PLAUSIBILITY_THRESHOLD, nrow(locally_plausible)))
cat(sprintf("  ...of those, referenced (in reference_df):     %d\n",
            sum(locally_plausible$is_referenced)))
cat(sprintf("  ...of those, NOT referenced (case 4, not this): %d\n",
            sum(!locally_plausible$is_referenced)))

plausible_referenced <- locally_plausible |> filter(is_referenced)

# ---- per-observation candidate genus/species sets ----
obs_candidates <- match_obj |>
  group_by(observation_id) |>
  summarise(
    genera_present  = list(unique(genus)),
    species_present = list(unique(taxon_name)),
    .groups = "drop"
  )

n_obs_total <- nrow(obs_candidates)
cat(sprintf("\nTotal observations: %d\n", n_obs_total))

# For each locally-plausible + referenced species, which observations have
# ANY candidate in that species' genus (i.e., the genus was "in play" for
# this observation) but do NOT have that species itself as a candidate?
plausible_referenced$genus <- plausible_referenced$genus  # already set

hit_rows <- list()

for (i in seq_len(nrow(plausible_referenced))) {
  sp    <- plausible_referenced$taxon_name[i]
  gen   <- plausible_referenced$genus[i]
  theta <- plausible_referenced$theta_mean[i]

  has_genus_candidate <- vapply(obs_candidates$genera_present,
                                 function(g) gen %in% g, logical(1))
  has_species_candidate <- vapply(obs_candidates$species_present,
                                   function(s) sp %in% s, logical(1))

  # Case 3 structural precondition: genus WAS attempted (>=1 candidate in
  # that genus survived), but this specific plausible+referenced species
  # did not survive as a candidate itself.
  struct_hit <- has_genus_candidate & !has_species_candidate
  if (any(struct_hit)) {
    hit_rows[[length(hit_rows) + 1]] <- data.frame(
      observation_id = obs_candidates$observation_id[struct_hit],
      missing_species = sp, genus = gen, theta_mean = theta
    )
  }
}

struct_hits <- if (length(hit_rows) > 0) bind_rows(hit_rows) else
  data.frame(observation_id = character(), missing_species = character(),
             genus = character(), theta_mean = numeric())

n_obs_struct_hit <- length(unique(struct_hits$observation_id))

cat("\n=== UNGATED count (genus attempted, species absent -- NOT similarity-checked) ===\n")
cat(sprintf("Observations with >=1 missing plausible+referenced species in an\n"))
cat(sprintf("  already-attempted genus: %d / %d (%.2f%%)\n",
            n_obs_struct_hit, n_obs_total, 100 * n_obs_struct_hit / n_obs_total))
cat("WARNING: this over-counts badly. It only checks 'genus present, species\n")
cat("absent' with no similarity signal at all -- true even for an observation\n")
cat("that is unambiguously a DIFFERENT species in the same genus, where the\n")
cat("'missing' species was never a real near-miss in the first place. Gating\n")
cat("this against real reference-vs-reference similarity (seq_matrix) below.\n")

# ==============================================================================
# Gate: is the missing species' reference actually close enough to this
# observation's own top-scoring candidate (the "anchor") that it plausibly
# WOULD have been a near-miss, not just an unrelated congener? Uses the same
# free seq_matrix lookup restore_suppressed_candidates()'s Tier 1 already
# relies on (reference-vs-reference pairs computed once at training time) --
# no new alignment, no raw query sequence needed. Estimate:
#   estimated_gap = 100 * (1 - p_match(anchor_accession, missing_species))
# i.e. how far below the anchor's OWN reference the missing species' own
# reference sits, applied as a proxy for how far below the query's OBSERVED
# anchor score the missing species would likely have scored (additive
# approximation -- same logic score_window_leave_one_out.R uses for
# congener_gap). Reported as a distribution across several candidate windows
# rather than gated at one arbitrary cutoff.
# ==============================================================================

seq_matrix <- readRDS(file.path(DATA_DIR, paste0(PREFIX, "_seq_matrix.rds")))

# long form: one row per (accession, other_species, p_match), both orientations
sm_long <- bind_rows(
  seq_matrix |> transmute(accession = id_x, other_species = species.y, p_match),
  seq_matrix |> transmute(accession = id_y, other_species = species.x, p_match)
) |>
  group_by(accession, other_species) |>
  summarise(best_p_match = max(p_match, na.rm = TRUE), .groups = "drop")

# this observation's own top-scoring candidate (the anchor)
anchor_df <- match_obj |>
  group_by(observation_id) |>
  slice_max(score_original, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(observation_id, anchor_accession = accession,
         anchor_score = score_original, anchor_species = species)

struct_hits_anchored <- struct_hits |>
  left_join(anchor_df, by = "observation_id") |>
  left_join(sm_long, by = c("anchor_accession" = "accession",
                             "missing_species" = "other_species")) |>
  mutate(
    estimated_gap = 100 * (1 - best_p_match),
    estimated_gap = ifelse(is.na(estimated_gap), Inf, estimated_gap)  # no seq_matrix pair at all -> can't estimate, treat as "not plausibly close"
  )

cat("\n=== GATED result: estimated_gap distribution for structural-precondition hits ===\n")
cat("(estimated_gap = how far below the anchor's own reference the missing\n")
cat(" species' reference sits, in points -- a proxy for how far below the\n")
cat(" query's OBSERVED anchor score it would likely have scored)\n\n")
print(summary(struct_hits_anchored$estimated_gap[is.finite(struct_hits_anchored$estimated_gap)]))
cat(sprintf("\nRows with NO seq_matrix pair at all (can't estimate): %d / %d\n",
            sum(!is.finite(struct_hits_anchored$estimated_gap)), nrow(struct_hits_anchored)))

for (w in c(1, 2, 5, 8, 15)) {
  n_obs_w <- length(unique(struct_hits_anchored$observation_id[
    struct_hits_anchored$estimated_gap <= w]))
  cat(sprintf("  Observations with a plausibly-excluded referenced candidate\n"))
  cat(sprintf("    (estimated_gap <= %2d pts): %5d / %d (%.2f%%)\n",
              w, n_obs_w, n_obs_total, 100 * n_obs_w / n_obs_total))
}

cat("\nTop missing species among GATED hits (estimated_gap <= 8, TaxaMatch's own\n")
cat("score_range default):\n")
gated8 <- struct_hits_anchored |> filter(estimated_gap <= 8)
if (nrow(gated8) > 0) {
  print(head(gated8 |> count(missing_species, genus, sort = TRUE), 15))
} else {
  cat("  (none)\n")
}

cat("\n=== Effective exclusion window in THIS match table (context) ===\n")
cat("detect_suppressed_candidates() on this real match_obj reports rule =\n")
cat("'perfect_only'; among observations with >1 candidate row, the observed\n")
cat("within-observation score spread is ~0.6-1.0 points at every quantile\n")
cat("(median/p75/p90/p95 all 0.6, max 1.0; ~0.6 = one base-pair step on a\n")
cat("~166bp MiFish amplicon) -- this externally-supplied PercMatch table's\n")
cat("effective retention window is far tighter than TaxaMatch::blast_sequences()'s\n")
cat("own score_range=8 default (expected: it never went through blast_sequences()\n")
cat("at all). At the estimated_gap <= 1-2 window that best matches THIS table's\n")
cat("own observed behavior, the gated rate above is the more honest read of\n")
cat("Problem 1's real-world frequency for this dataset specifically.\n")

cat("\n=== Summary ===\n")
cat("The GATED rate (not the ungated one) is the right number to trust: how\n")
cat("often a real, referenced, locally-expected species is absent from an\n")
cat("observation's candidate set despite (a) its genus having been attempted\n")
cat("at all and (b) its own reference being close enough, by real reference-vs-\n")
cat("reference similarity, to plausibly have been a genuine near-miss rather\n")
cat("than an unrelated congener. This still does NOT confirm the missing\n")
cat("species was the correct call for any specific observation -- only that\n")
cat("the structural + similarity preconditions for case 3 both hold.\n")

saveRDS(list(struct_hits_anchored = struct_hits_anchored,
             focal_grid = FOCAL_GRID, n_obs_total = n_obs_total,
             plausible_referenced = plausible_referenced),
        file.path("diagnostics", "referenced_candidate_exclusion_rate_result.rds"))

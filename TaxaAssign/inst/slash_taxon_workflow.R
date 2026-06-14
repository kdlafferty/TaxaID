# slash_taxon_workflow.R
# Test and exploration workflow for add_slash_taxon()
#
# Prereq: consensus_final must already be in your environment
# (output of posterior_consensus() from the Bayesian or LLM pipeline).
#
# Sections:
#   1. Audit plausible_taxa for invalid species names (run this first)
#   2. Run add_slash_taxon()
#   3. Inspect results
#   4. Filter to reportable observations
# ==============================================================================

library(TaxaAssign)
library(TaxaTools)
library(dplyr)

# ------------------------------------------------------------------------------
# 1. Audit plausible_taxa for invalid species names
#    These corrupt slash names. Find them here; fix upstream with
#    filter_gbif_quality(require_species = TRUE) before they reach the pipeline.
# ------------------------------------------------------------------------------

# Flatten all candidates across all observations
all_candidates <- unlist(consensus_final$plausible_taxa)
all_candidates <- unique(all_candidates[!is.na(all_candidates) & nzchar(all_candidates)])

# Flag non-binomial names
invalid_mask  <- !TaxaTools::is_valid_species_name(all_candidates)
invalid_names <- sort(all_candidates[invalid_mask])

cat("Invalid candidate names found:", length(invalid_names), "\n")
if (length(invalid_names)) print(invalid_names)

# Which observation_ids contain invalid names?
obs_with_invalid <- consensus_final |>
  filter(sapply(plausible_taxa, function(x)
    any(!TaxaTools::is_valid_species_name(x[!is.na(x) & nzchar(x)])))) |>
  select(observation_id, plausible_taxa, consensus_taxon, consensus_rank)

cat("\nObservations with invalid candidate names:", nrow(obs_with_invalid), "\n")
print(obs_with_invalid)

# NOTE: ideal fix is upstream — pass require_species = TRUE to
# TaxaFetch::filter_gbif_quality() so these names never enter the pipeline.
# The function will silently drop empty/NA entries; non-binomials that survive
# will appear in slash names using everything-after-first-space as the epithet.

# ------------------------------------------------------------------------------
# 2. Run add_slash_taxon()
# ------------------------------------------------------------------------------

consensus_slash <- add_slash_taxon(consensus_final)

# Spot-check the new columns
cat("\nNew columns added:\n")
cat("  slash_taxon_name     :", sum(!is.na(consensus_slash$slash_taxon_name)), "non-NA rows\n")
cat("  irreducible_consensus:", sum(consensus_slash$irreducible_consensus, na.rm = TRUE),
    "TRUE /", sum(!consensus_slash$irreducible_consensus, na.rm = TRUE), "FALSE\n")

# ------------------------------------------------------------------------------
# 3. Inspect results
# ------------------------------------------------------------------------------

# -- 3a. Sample of multi-candidate slash names
consensus_slash |>
  filter(!is.na(slash_taxon_name)) |>
  select(observation_id, slash_taxon_name, irreducible_consensus,
         n_plausible, consensus_taxon, consensus_rank) |>
  arrange(desc(n_plausible)) |>
  head(30) |>
  print()

# -- 3b. All unique slash names and their irreducibility
unique_slashes <- consensus_slash |>
  filter(!is.na(slash_taxon_name)) |>
  select(slash_taxon_name, irreducible_consensus, n_plausible) |>
  distinct() |>
  arrange(desc(irreducible_consensus), n_plausible)

cat("\nUnique slash taxa:\n")
print(unique_slashes, n = 60)

# -- 3c. Reducible slashes — which are subsumed by a finer set?
#    These are multi-candidate sets where some species appear alone (or in a
#    smaller set) elsewhere in the data. Useful for debugging.
reducible <- consensus_slash |>
  filter(!is.na(slash_taxon_name), !irreducible_consensus) |>
  select(observation_id, slash_taxon_name, n_plausible,
         consensus_taxon, consensus_rank, plausible_taxa) |>
  distinct(slash_taxon_name, .keep_all = TRUE)

cat("\nReducible slash taxa (subsumed by finer sets):", nrow(reducible), "\n")
print(reducible)

# -- 3d. Mixed-genus cases (contain " + ")
mixed_genus <- consensus_slash |>
  filter(grepl(" + ", slash_taxon_name, fixed = TRUE)) |>
  select(observation_id, slash_taxon_name, irreducible_consensus, n_plausible) |>
  distinct(slash_taxon_name, .keep_all = TRUE)

cat("\nMixed-genus slash taxa:\n")
print(mixed_genus)

# ------------------------------------------------------------------------------
# 4. Filter to reportable observations
# ------------------------------------------------------------------------------

# All observations worth reporting:
#   - Singletons resolved to species (irreducible_consensus = TRUE, n_plausible = 1)
#   - Irreducible slash taxa  (irreducible_consensus = TRUE, n_plausible >= 2)
#   - Excludes: unresolved (n_plausible = 0), reducible multi-candidate sets
reportable <- consensus_slash |>
  filter(irreducible_consensus == TRUE)

cat("\nReportable observations:", nrow(reportable), "of", nrow(consensus_slash), "\n")
cat("  Singletons            :", sum(reportable$n_plausible == 1, na.rm = TRUE), "\n")
cat("  Irreducible slash taxa:", sum(reportable$n_plausible > 1,  na.rm = TRUE), "\n")

# Summary table: slash taxon → n observations
reportable |>
  mutate(label = if_else(is.na(slash_taxon_name), consensus_taxon, slash_taxon_name)) |>
  count(label, sort = TRUE) |>
  print(n = 40)

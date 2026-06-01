# test_expand_consensus.R
# Lightweight synthetic tests for expand_consensus_candidates()
# Run interactively: source("inst/test_expand_consensus.R")

library(TaxaLikely)

cat("=== Building synthetic priors_df ===\n")

# Simulate what a TaxaExpect priors data frame looks like:
# species-level rows with taxonomy columns + some prior value columns
priors_df <- data.frame(
  family  = c(rep("Salmonidae", 7), rep("Cyprinidae", 3)),
  genus   = c(rep("Salmo", 3), rep("Salvelinus", 4), rep("Cyprinus", 3)),
  species = c(
    "Salmo salar", "Salmo trutta", "Salmo obtusirostris",       # Salmo
    "Salvelinus alpinus", "Salvelinus fontinalis",               # Salvelinus
    "Salvelinus namaycush", "Salvelinus confluentus",            # Salvelinus
    "Cyprinus carpio", "Cyprinus rubrofuscus", "Cyprinus acutidorsalis" # Cyprinus
  ),
  prior_alpha = c(5, 2, 1,  8, 6, 3, 1,  10, 4, 1),
  prior_beta  = c(2, 5, 9,  2, 3, 7, 9,   1, 6, 9),
  stringsAsFactors = FALSE
)

# Reference database: only some species have barcode sequences
referenced_species <- c(
  "Salmo salar", "Salmo trutta",            # Salmo has 2 refs (salar = consensus)
  "Salvelinus alpinus", "Salvelinus fontinalis", "Salvelinus namaycush",
  "Cyprinus carpio"
)

cat("\npriors_df:\n")
print(priors_df)
cat("\nreferenced_species:", paste(referenced_species, collapse = ", "), "\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Case 1: Species-level consensus ===\n")
cat("Salmo salar is the consensus. Salmo trutta is referenced (should be excluded).\n")
cat("Salmo obtusirostris is unreferenced (should be included).\n\n")

consensus_sp <- data.frame(
  observation_id  = "obs1",
  taxon_name      = "Salmo salar",
  taxon_name_rank = "species",
  stringsAsFactors = FALSE
)

res_sp <- expand_consensus_candidates(
  consensus_df       = consensus_sp,
  priors_df          = priors_df,
  referenced_species = referenced_species
)

cat("\n$likelihoods:\n")
print(res_sp$likelihoods)
cat("Expected: Salmo salar + Salmo obtusirostris (Salmo trutta excluded)\n")
stopifnot(
  nrow(res_sp$likelihoods)       == 2L,
  all(res_sp$likelihoods$likelihood_point_est == 1.0),
  "Salmo salar"        %in% res_sp$likelihoods$taxon_name,
  "Salmo obtusirostris" %in% res_sp$likelihoods$taxon_name,
  !"Salmo trutta"       %in% res_sp$likelihoods$taxon_name,
  nrow(res_sp$unresolved) == 0L
)
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Case 2: Genus-level consensus ===\n")
cat("Salvelinus consensus. All 4 Salvelinus species in priors_df should be candidates.\n\n")

consensus_ge <- data.frame(
  observation_id  = "obs2",
  taxon_name      = "Salvelinus",
  taxon_name_rank = "genus",
  stringsAsFactors = FALSE
)

res_ge <- expand_consensus_candidates(
  consensus_df       = consensus_ge,
  priors_df          = priors_df,
  referenced_species = referenced_species
)

cat("\n$likelihoods:\n")
print(res_ge$likelihoods)
cat("Expected: all 4 Salvelinus species (referenced status irrelevant at genus level)\n")
stopifnot(
  nrow(res_ge$likelihoods)         == 4L,
  all(res_ge$likelihoods$likelihood_mean == 1.0),
  all(res_ge$likelihoods$hypothesis_type == "specific_candidate"),
  nrow(res_ge$unresolved) == 0L
)
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Case 3: Family-level consensus ===\n")
cat("Salmonidae consensus. All 7 Salmonidae species in priors_df should be candidates.\n\n")

consensus_fa <- data.frame(
  observation_id  = "obs3",
  taxon_name      = "Salmonidae",
  taxon_name_rank = "family",
  stringsAsFactors = FALSE
)

res_fa <- expand_consensus_candidates(
  consensus_df   = consensus_fa,
  priors_df      = priors_df,
  max_candidates = 50L
)

cat("\n$likelihoods:\n")
print(res_fa$likelihoods)
cat("Expected: all 7 Salmonidae species\n")
stopifnot(
  nrow(res_fa$likelihoods) == 7L,
  all(res_fa$likelihoods$likelihood_sd == 0.0),
  nrow(res_fa$unresolved) == 0L
)
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Case 4: Family-level overflow → $unresolved ===\n")
cat("max_candidates = 3, but Salmonidae has 7 species. Should go to $unresolved.\n\n")

res_overflow <- expand_consensus_candidates(
  consensus_df   = consensus_fa,
  priors_df      = priors_df,
  max_candidates = 3L
)

stopifnot(
  nrow(res_overflow$likelihoods) == 0L,
  nrow(res_overflow$unresolved)  == 1L,
  res_overflow$unresolved$observation_id == "obs3"
)
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Case 5: Consensus species absent from priors_df ===\n")
cat("'Salmo dentex' not in priors_df; genus inferred from name. Only dentex returned.\n\n")

consensus_absent <- data.frame(
  observation_id  = "obs4",
  taxon_name      = "Salmo dentex",
  taxon_name_rank = "species",
  stringsAsFactors = FALSE
)

res_absent <- expand_consensus_candidates(
  consensus_df       = consensus_absent,
  priors_df          = priors_df,
  referenced_species = referenced_species
)

cat("\n$likelihoods:\n")
print(res_absent$likelihoods)
cat("Expected: Salmo dentex (added) + Salmo obtusirostris (unreferenced congener)\n")
stopifnot(
  "Salmo dentex"        %in% res_absent$likelihoods$taxon_name,
  "Salmo obtusirostris" %in% res_absent$likelihoods$taxon_name,
  !"Salmo trutta"        %in% res_absent$likelihoods$taxon_name
)
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Case 6: Mixed ranks in one call ===\n")
cat("obs1=species, obs2=genus, obs3=family all in one consensus_df.\n\n")

consensus_mixed <- data.frame(
  observation_id  = c("obs1", "obs2", "obs3"),
  taxon_name      = c("Salmo salar", "Salvelinus", "Salmonidae"),
  taxon_name_rank = c("species", "genus", "family"),
  stringsAsFactors = FALSE
)

res_mixed <- expand_consensus_candidates(
  consensus_df       = consensus_mixed,
  priors_df          = priors_df,
  referenced_species = referenced_species
)

cat("\n$likelihoods:\n")
print(res_mixed$likelihoods)
obs_counts <- table(res_mixed$likelihoods$observation_id)
cat("\nCandidate counts per observation:\n")
print(obs_counts)
stopifnot(
  obs_counts["obs1"] == 2L,   # Salmo salar + obtusirostris
  obs_counts["obs2"] == 4L,   # all Salvelinus
  obs_counts["obs3"] == 7L,   # all Salmonidae
  nrow(res_mixed$unresolved) == 0L
)
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Case 7: NULL referenced_species warning ===\n")
cat("Should warn but still run.\n\n")

res_warn <- withCallingHandlers(
  expand_consensus_candidates(
    consensus_df = consensus_sp,
    priors_df    = priors_df
    # referenced_species = NULL (default)
  ),
  warning = function(w) {
    cat("Warning caught:", conditionMessage(w), "\n")
    invokeRestart("muffleWarning")
  }
)

cat("\nAll 3 Salmo species included (no exclusion without referenced_species):\n")
print(res_warn$likelihoods$taxon_name)
stopifnot(nrow(res_warn$likelihoods) == 3L)  # all Salmo
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== All tests passed ===\n")

# test_session99.R
# Quick smoke-tests for the Session 99 unified likelihood pipeline.
# All synthetic data — no external files, internet, or trained model required.
# Source this from the TaxaLikely project directory or run section by section.
#
# Covers:
#   1. unreferenced_candidates() structure
#   2. assign_scores(score_type = "none")          -- no-score pathway
#   3. assign_scores(score_type = "similarity_softmax") -- BirdNET top-1
#   4. assign_scores(score_type = "probability")   -- multi-candidate softmax
#   5. include_unreferenced_family = TRUE           -- LLM / no-priors variant
#   6. Output column set matches TaxaAssign expectations

library(TaxaLikely)
cat("TaxaLikely version:", as.character(packageVersion("TaxaLikely")), "\n\n")

# ---- helpers -----------------------------------------------------------------
.check <- function(desc, expr) {
  tryCatch({
    if (!isTRUE(expr)) stop("assertion failed")
    cat("  PASS:", desc, "\n")
  }, error = function(e) {
    cat("  FAIL:", desc, "->", conditionMessage(e), "\n")
  })
}

# ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
cat("=== 1. unreferenced_candidates() structure ===\n")

consensus_sp <- data.frame(
  observation_id  = "obs1",
  taxon_name      = "Salmo salar",
  taxon_name_rank = "species",
  family          = "Salmonidae",
  genus           = "Salmo",
  species         = "Salmo salar",
  stringsAsFactors = FALSE
)

hyp <- unreferenced_candidates(
  consensus_sp,
  rank_system = c("family", "genus", "species")
)

.check("returns 3 rows (H1 + H2 + H3)",
       nrow(hyp) == 3L)
.check("hypothesis_type values present",
       all(c("specific_candidate", "unreferenced_species", "unreferenced_genus") %in% hyp$hypothesis_type))
.check("observation_id propagated to all rows",
       all(hyp$observation_id == "obs1"))
.check("H1 taxon_name = Salmo salar",
       hyp$taxon_name[hyp$hypothesis_type == "specific_candidate"] == "Salmo salar")
.check("H2 genus = Salmo (same genus as H1)",
       hyp$genus[hyp$hypothesis_type == "unreferenced_species"] == "Salmo")
.check("H3 family = Salmonidae (same family as H1)",
       hyp$family[hyp$hypothesis_type == "unreferenced_genus"] == "Salmonidae")
cat("\n")

# ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
cat("=== 2. assign_scores(score_type = 'none') — morphology / expert IDs ===\n")

lik_none <- assign_scores(hyp, score_type = "none")

.check("all score_likelihood = 1.0",
       all(lik_none$score_likelihood == 1.0))
.check("all score_likelihood_mean = 1.0",
       all(lik_none$score_likelihood_mean == 1.0))
.check("all score_likelihood_sd = 0.0",
       all(lik_none$score_likelihood_sd == 0.0))
.check("score_method = 'none'",
       all(lik_none$score_method == "none"))
.check("required TaxaAssign columns present",
       all(c("observation_id", "taxon_name", "taxon_name_rank",
             "hypothesis_type", "score_likelihood",
             "score_likelihood_mean", "score_likelihood_sd") %in% names(lik_none)))
cat("\n")

# ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
cat("=== 3. assign_scores(score_type = 'similarity_softmax') — BirdNET top-1 ===\n")

birdnet_df <- data.frame(
  observation_id  = c("clip_001", "clip_002"),
  taxon_name      = c("Melospiza melodia", "Turdus migratorius"),
  taxon_name_rank = c("species", "species"),
  family          = c("Passerellidae", "Turdidae"),
  genus           = c("Melospiza", "Turdus"),
  species         = c("Melospiza melodia", "Turdus migratorius"),
  score_original  = c(0.87, 0.43),
  stringsAsFactors = FALSE
)

hyp_bn <- unreferenced_candidates(birdnet_df,
            rank_system = c("family", "genus", "species"))
lik_bn  <- assign_scores(hyp_bn, score_type = "similarity_softmax")

# Each observation has H1 + H2 + H3
.check("6 rows total (2 obs x 3 hypotheses)",
       nrow(lik_bn) == 6L)

h1_clip1 <- lik_bn[lik_bn$observation_id == "clip_001" &
                     lik_bn$hypothesis_type == "specific_candidate", ]
h2_clip1 <- lik_bn[lik_bn$observation_id == "clip_001" &
                     lik_bn$hypothesis_type == "unreferenced_species", ]
h3_clip1 <- lik_bn[lik_bn$observation_id == "clip_001" &
                     lik_bn$hypothesis_type == "unreferenced_genus", ]

.check("H1 score_likelihood = 1.0 (ratio-normalized best candidate)",
       h1_clip1$score_likelihood == 1.0)
# For top-1 input (single H1 per observation), H2/H3 are anchored at
# median(H1 likelihoods) = median(1.0) = 1.0. The confidence score does
# NOT modulate H2/H3 likelihoods when there is only one H1 candidate.
# similarity_softmax only creates discrimination with multi-candidate input.
.check("H2 score_likelihood = 1.0 (top-1 input: single H1 median = 1.0)",
       h2_clip1$score_likelihood == 1.0)
.check("score_method = 'similarity_softmax'",
       all(lik_bn$score_method == "similarity_softmax"))
cat("\n")

# ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
cat("=== 4. assign_scores(score_type = 'probability') — multi-candidate classifier ===\n")
# Simulates iNaturalist CV: multiple ranked species per observation with
# probability scores that sum to ~1.

multi_df <- data.frame(
  observation_id  = c("img_001", "img_001", "img_001"),
  taxon_name      = c("Quercus robur", "Quercus petraea", "Quercus pubescens"),
  taxon_name_rank = c("species", "species", "species"),
  family          = c("Fagaceae", "Fagaceae", "Fagaceae"),
  genus           = c("Quercus", "Quercus", "Quercus"),
  species         = c("Quercus robur", "Quercus petraea", "Quercus pubescens"),
  score_original  = c(0.72, 0.21, 0.07),   # classifier softmax probabilities
  stringsAsFactors = FALSE
)

hyp_mc <- unreferenced_candidates(multi_df,
            rank_system = c("family", "genus", "species"))
lik_mc  <- assign_scores(hyp_mc, score_type = "probability")

h1_rows <- lik_mc[lik_mc$hypothesis_type == "specific_candidate", ]
.check("best H1 candidate score_likelihood = 1.0",
       max(h1_rows$score_likelihood) == 1.0)
.check("H1 likelihoods in (0, 1]",
       all(h1_rows$score_likelihood > 0 & h1_rows$score_likelihood <= 1))
.check("lower-ranked H1s < 1.0",
       sum(h1_rows$score_likelihood < 1.0) >= 2L)
.check("score_method = 'probability'",
       all(lik_mc$score_method == "probability"))
cat("\n")

# ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
cat("=== 5. include_unreferenced_family = TRUE ===\n")

hyp_h4 <- unreferenced_candidates(
  consensus_sp,
  rank_system                 = c("family", "genus", "species"),
  include_unreferenced_family = TRUE
)
lik_h4  <- assign_scores(hyp_h4, score_type = "none")

.check("4 rows when include_unreferenced_family = TRUE",
       nrow(hyp_h4) == 4L)
.check("unreferenced_family hypothesis present",
       "unreferenced_family" %in% hyp_h4$hypothesis_type)
.check("unreferenced_family row has NA taxon_name",
       is.na(hyp_h4$taxon_name[hyp_h4$hypothesis_type == "unreferenced_family"]))
# unreferenced_family gets a fixed small weight, not 1.0, from assign_scores()
h4_lik <- lik_h4$score_likelihood[lik_h4$hypothesis_type == "unreferenced_family"]
# For score_type = "none", ALL rows including H4 receive 1.0 (uniform).
# The 0.05 fixed weight for unreferenced_family only applies when using
# score_type = "probability" or "similarity_softmax".
cat("  INFO: unreferenced_family score_likelihood =", h4_lik,
    "(1.0 for score_type='none'; fixed 0.05 only for probability/similarity_softmax)\n")
.check("unreferenced_family score_likelihood = 1.0 (score_type='none' is uniform)",
       h4_lik == 1.0)
.check("non-family rows also get 1.0",
       all(lik_h4$score_likelihood[lik_h4$hypothesis_type != "unreferenced_family"] == 1.0))

# Verify 0.05 fixed weight for scored types:
consensus_sp_scored <- cbind(consensus_sp, score_original = 0.95)
hyp_h4_scored <- unreferenced_candidates(consensus_sp_scored,
                   rank_system = c("family", "genus", "species"),
                   include_unreferenced_family = TRUE)
lik_h4_ss <- assign_scores(hyp_h4_scored, score_type = "similarity_softmax")
h4_ss_lik <- lik_h4_ss$score_likelihood[lik_h4_ss$hypothesis_type == "unreferenced_family"]
.check("unreferenced_family score_likelihood = 0.05 with similarity_softmax",
       h4_ss_lik == 0.05)
cat("\n")

# ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
cat("=== 6. Mixed ranks (species + genus-level consensus) ===\n")

mixed_df <- data.frame(
  observation_id  = c("obs1", "obs2"),
  taxon_name      = c("Salmo salar", "Salvelinus"),
  taxon_name_rank = c("species",     "genus"),
  family          = c("Salmonidae",  "Salmonidae"),
  genus           = c("Salmo",       "Salvelinus"),
  species         = c("Salmo salar", NA_character_),
  stringsAsFactors = FALSE
)

hyp_mixed <- unreferenced_candidates(mixed_df,
               rank_system = c("family", "genus", "species"))
.check("3 rows per observation (H1 + H2 + H3)",
       all(table(hyp_mixed$observation_id) == 3L))

lik_mixed <- assign_scores(hyp_mixed, score_type = "none")
.check("all score_likelihood = 1.0 for mixed ranks",
       all(lik_mixed$score_likelihood == 1.0))
cat("\n")

# ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ── ──
cat("=== 7. expand_consensus_demo.R (new API) ===\n")
cat("Sourcing inst/workflows/expand_consensus_demo.R...\n")
tryCatch(
  source(system.file("workflows", "expand_consensus_demo.R",
                     package = "TaxaLikely")),
  error = function(e) cat("  ERROR:", conditionMessage(e), "\n")
)

cat("\n=== All session99 tests complete ===\n")
cat("If all lines above say PASS, the unified pipeline is working correctly.\n")
cat("\nNext: see 'Large workflows to check' section below.\n")
cat("\n# ---- Large workflows to check interactively ----------------------------\n")
cat("# These require real data or TaxaAssign installation; run section-by-section:\n")
cat("#\n")
cat("# 1. inst/workflows/6_no_score_pathway_workflow.R  -- no-score pathway\n")
cat("#    (needs a consensus .rds or .csv; Section 2-4 can be tested with\n")
cat("#     any data frame with observation_id + taxon_name + taxon_name_rank)\n")
cat("#\n")
cat("# 2. inst/TaxaLikely_workflow.R  -- Stage A only (synthetic data, no NCBI)\n")
cat("#    Verify: stopifnot at line 119 passes (score_original column check)\n")
cat("#\n")
cat("# 3. TaxaAssign/inst/TaxaAssign_llm_workflow.R\n")
cat("#    Focus: Section 4b 'Inspect unreferenced_family posterior'\n")
cat("#    (formerly 'unknown_species'; now filters on hypothesis_type == 'unreferenced_family')\n")
cat("#\n")
cat("# 4. TaxaAssign/inst/TaxaAssign_bayesian_workflow.R\n")
cat("#    Focus: score_consensus() call -- verify score_col = 'score_original' accepted\n")

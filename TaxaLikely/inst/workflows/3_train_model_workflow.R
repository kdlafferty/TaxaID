# ==============================================================================
# WORKFLOW 3: TRAIN A LIKELIHOOD MODEL
# ==============================================================================
# Purpose: Train a statistical model that converts match scores into
#   likelihoods for taxonomic assignment.
#
# Input: reference_df from Workflow 1 (or a pre-built ref_matrix from Workflow 2)
# Output: A trained model object (class taxa_model_params) for Workflow 4
#
# Requires: DECIPHER and Biostrings (for build_sequence_matrix)
#   Install with: BiocManager::install("DECIPHER")
#
# --- BACKGROUND: WHY THREE HYPOTHESES? ---
#
# When a query sequence arrives, there are three possible explanations:
#
#   H1: Known species ("specific candidate")
#     The query comes from a species that IS in the reference database.
#     This is the standard case -- the best-matching reference is the
#     correct identification. The model learns what within-species match
#     scores look like: typically high scores with a clear gap between
#     the true species and the runner-up.
#
#   H2: Unreferenced species
#     The query comes from a species NOT in the reference database, but
#     from a genus that IS represented. For example, your reference has
#     Fundulus heteroclitus and Fundulus parvipinnis, but the query is
#     actually Fundulus diaphanus -- a species with no reference sequence.
#     In this case, the query will partially match its congeners but with
#     lower scores and a smaller gap than a true H1 match. Ignoring this
#     possibility leads to false confidence: the model would force-assign
#     the query to whichever reference species happens to be closest,
#     even though the true species is absent.
#
#   H3: Unreferenced genus
#     The query comes from a genus entirely absent from the reference.
#     Scores will be even lower, with the "best match" being a distant
#     relative. Without H3, these queries get incorrectly assigned to
#     whatever happens to be in the database.
#
# --- HOW THE MODEL LEARNS H2 AND H3 ---
#
# The model trains on reference-vs-reference comparisons:
#   - Within-species pairs (same species, different sequences) teach H1:
#     what does a correct match look like?
#   - Cross-species, within-genus pairs teach H2: what does a match look
#     like when the true species is missing but a congener is present?
#   - Cross-genus pairs teach H3: what does a distant match look like?
#
# Specifically:
#   - H1 parameters: per-species mean score and gap, with Empirical Bayes
#     shrinkage toward the global mean (so rare species borrow strength
#     from well-sampled ones).
#   - H2 delta: the logit-scale offset between H1 and the foreign-match
#     distribution within the same genus. Computed from observed cross-species
#     matches in the training data (~3 logit units below H1 mean by default).
#   - H3 delta: a further offset below H2 (default H2_delta + 2.0),
#     reflecting the greater divergence expected for a missing genus.
#
# The two key metrics the model uses are:
#   - Score: how well does the query match its best candidate? (logit-transformed)
#   - Gap: how much better is the best match than the runner-up? (logit-scale)
#     A large gap suggests the top candidate is correct (H1). A small gap
#     suggests the true species may not be in the reference (H2 or H3).
#
# --- HOW WRONG REFERENCED CANDIDATES GET LOW LIKELIHOODS ---
#
# Even among referenced species (H1 candidates), the model distinguishes
# correct from incorrect matches. Each candidate's likelihood is evaluated
# against its OWN species-specific distribution. Consider a query that truly
# comes from Species A:
#
#   Species A (correct):
#     - High score (the sequence matches well)
#     - Large gap (Species A clearly beats the runner-up)
#     - These values fall near the center of Species A's expected distribution
#     - Result: HIGH likelihood
#
#   Species B (wrong, but in the reference):
#     - Lower score (the sequence doesn't match as well)
#     - Small gap (Species B doesn't clearly beat its competitors)
#     - These values fall in the TAIL of Species B's expected distribution
#       (because if the query truly came from Species B, we'd expect a much
#       higher score and larger gap)
#     - Result: LOW likelihood
#
# So the model naturally downweights wrong candidates without explicitly
# flagging them. The math handles it: a mediocre score is unlikely under
# a species' H1 distribution because that species expects near-perfect
# matches to its own sequences.
#
# --- WHY UNREFERENCED HYPOTHESES MATTER ---
#
# If we only had H1 (referenced species), the model would be forced to
# divide all probability among candidates in the database. This creates
# a problem when the true species is ABSENT: the model assigns high
# confidence to the closest relative, even though it's the wrong species.
#
# H2 and H3 give the model permission to say "the true source probably
# isn't any species in the reference." When a query produces mediocre
# scores with small gaps against all candidates, the H2/H3 likelihoods
# can exceed any individual H1 likelihood -- correctly signaling that
# the sample likely comes from an unreferenced taxon.
#
# Without H2/H3, every query is guaranteed to be assigned to a referenced
# species. With them, the model can honestly report uncertainty and flag
# samples that may come from taxa absent from the database.
#
# --- COVERAGE: HARD FILTER ONLY (not a model dimension) ---
#
# Reference-vs-reference training pairs are nearly always full-length
# alignments: same-species sequences share the same amplicon and align
# completely. Because within-species pairs rarely show low coverage,
# there is no within-H1 coverage variation from which the model could
# learn a coverage-score relationship. Coverage is therefore NOT a
# dimension of the bivariate normal model.
#
# Coverage is used in two ways:
#   1. Hard filter here in training: pairs below a threshold are excluded
#      before model fitting. Low-coverage cross-species pairs inflate
#      variance estimates and weaken H1/H2 discrimination.
#   2. Soft inflation at inference (Workflow 4): evaluate_likelihoods()
#      produces score_likelihood_cov alongside score_likelihood, widening
#      H1 sigma by 1/sqrt(coverage) for each candidate. This is a
#      principled prior (binomial SE argument), not a fitted parameter.
#      See Workflow 4 for how to compare the two columns.
#
# ==============================================================================

library(TaxaLikely)

# ---- 1. Load inputs ----------------------------------------------------------
# Option A: Start from reference_df (Workflow 1 output)
reference_df <- readRDS(file.choose())

# Option B: Reuse ref_matrix from Workflow 2 (skip alignment step)
# ref_matrix <- readRDS("ref_matrix.rds")

rank_system <- c("family", "genus", "species")

# ---- 2. Build pairwise matrix (skip if reusing from Workflow 2) --------------
# If you already ran Workflow 2 and saved ref_matrix.rds, load it above
# and skip this step -- it's the most time-consuming part.

ref_matrix <- build_sequence_matrix(
  reference_df = reference_df,
  rank_system  = rank_system
)
saveRDS(ref_matrix, "ref_matrix.rds")


# ---- 3. Calibrate and apply a coverage filter before training ---------------
#
# build_sequence_matrix() attaches a 'coverage' column: positions where both
# sequences contribute a non-gap character, divided by the shorter unaligned
# length. Range (0, 1].
#
# Within-species (H1) pairs nearly always have coverage = 1 because
# same-species sequences share the same amplicon. Low-coverage pairs are
# almost entirely cross-species comparisons. Including them in training
# inflates H2 variance estimates and weakens H1/H2 discrimination.
#
# calibrate_coverage_filter() sweeps thresholds and returns Youden's J
# (H1 retention minus H2 retention) to find the Pareto-optimal cutoff.
# coverage_threshold() is a faster quantile-based alternative.

# Confirm coverage distribution
cat("Coverage summary (all pairs):\n")
print(summary(ref_matrix$coverage))

cat("\nCoverage by hypothesis type:\n")
h1 <- ref_matrix[ref_matrix$species.x == ref_matrix$species.y &
                   ref_matrix$id_x != ref_matrix$id_y, ]
h2 <- ref_matrix[ref_matrix$species.x != ref_matrix$species.y, ]
cat(sprintf("  H1 (within-species): mean = %.3f, var = %.5f, n = %d\n",
            mean(h1$coverage), var(h1$coverage), nrow(h1)))
cat(sprintf("  H2 (cross-species):  mean = %.3f, var = %.5f, n = %d\n",
            mean(h2$coverage), var(h2$coverage), nrow(h2)))

cal <- calibrate_coverage_filter(ref_matrix)
best_thresh <- cal$threshold[which.max(cal$youden_j)]
cat(sprintf(
  "\nOptimal coverage threshold: %.3f  (Youden J = %.3f, breadth = %.1f%%)\n",
  best_thresh, max(cal$youden_j), cal$breadth[which.max(cal$youden_j)] * 100
))

# Filter training data to the calibrated threshold.
# Pass the same threshold as min_coverage in evaluate_likelihoods() (Workflow 4)
# to keep inference within the same range as training.
ref_matrix_filtered <- ref_matrix[ref_matrix$coverage >= best_thresh, ]
cat(sprintf("Pairs retained after coverage filter: %d of %d (%.1f%%)\n",
            nrow(ref_matrix_filtered), nrow(ref_matrix),
            100 * nrow(ref_matrix_filtered) / nrow(ref_matrix)))


# ---- 4. Train the model -----------------------------------------------------
# train_likelihood_model() does three things:
#   1. Removes mislabeled sequences (calls flag_reference_errors() internally)
#   2. Computes per-species score and gap distributions
#   3. Estimates H1, H2, H3 parameters with Empirical Bayes shrinkage
#
# The model is ALWAYS bivariate: (score_logit, gap_logit).
# Coverage is handled as a hard filter (above) and a soft inference-time
# inflation (score_likelihood_cov in Workflow 4) -- not a model dimension.
#
# Key parameters:
#   prior_weight:  controls shrinkage strength (default 10). Higher values
#     pull species-specific estimates toward the global mean. Useful when
#     many species have few sequences.
#   use_hierarchy: if TRUE (default), uses lme4 for hierarchical estimation
#     across rank levels. Falls back to global mean if fitting fails.

model <- train_likelihood_model(
  raw_df        = ref_matrix_filtered,
  rank_system   = rank_system,
  prior_weight  = 10.0,
  use_hierarchy = TRUE           # default; explicit here for clarity
  # mislabel_threshold = 0.02   # passed to flag_reference_errors()
)


# ---- 5. Interpret the model --------------------------------------------------
# interpret_model() produces a human-readable summary. The most important
# output is the hypothesis baselines -- these tell you what match scores
# the model expects for each hypothesis type:
#
#   H1 expected match %:  e.g., 98.5% -- a correct species match
#   H2 expected match %:  e.g., 94.2% -- an unreferenced congener
#   H3 expected match %:  e.g., 88.7% -- an unreferenced genus
#
# The separation between these tells you how distinguishable the hypotheses
# are for your marker. If H1 and H2 are close together (e.g., both ~97%),
# the marker has limited power to distinguish known from unreferenced species.
# Markers with large H1-H2 gaps (e.g., COI for animals) provide stronger
# discrimination than markers with small gaps (e.g., 18S).

interp <- interpret_model(model)

# The returned list is useful for programmatic access:
# interp$hypothesis_baselines  -- H1/H2/H3 expected scores
# interp$global_h1             -- global mean score/gap
# interp$species_thresholds    -- per-species expected match %


# ---- 6. Inspect model structure (optional) -----------------------------------
# The model object (class taxa_model_params) contains:
#   H1_Lookup    -- per-species params: lookup_key, rank, mu_score, mu_gap,
#                   sigma_score (shrunk toward global)
#   H1_Global_Mu -- global fallback: named vector (score_logit, gap_logit)
#   H1_Sigma     -- 2x2 global covariance matrix (bivariate)
#   H2           -- list(delta, sigma) for missing-species hypothesis
#   H3           -- list(delta, sigma) for missing-genus hypothesis
#   Stats        -- diagnostics: AIC_Score, n_species, n_singletons, n_anchors

cat("\n--- Model structure ---\n")
str(model, max.level = 1)

cat("\nModel type: BIVARIATE (score_logit + gap_logit)\n")
cat("Species in model:", model$Stats$n_species, "\n")
cat("Singletons:", model$Stats$n_singletons, "\n")
cat("Coverage threshold for Workflow 4 min_coverage:", round(best_thresh, 3), "\n")

# How many species have enough data for reliable per-species estimates?
well_sampled <- sum(model$H1_Lookup$rank == "species")
cat("Species with per-species params:", well_sampled, "\n")


# ---- 7. Preview score_likelihood_cov using training matrix ------------------
# score_likelihood_cov inflates H1 sigma by 1/sqrt(coverage) at inference time.
# Widening sigma flattens the H1 distribution, which changes the likelihood
# point estimate. The direction depends on where the observed score falls
# relative to the H1 mean:
#
#   Score near the H1 mean (good match, within-species pairs):
#     flattening lowers the peak density -> score_likelihood_cov DECREASES.
#     This is the primary intended effect: a strong match at low coverage
#     is penalised relative to the same score at full coverage.
#
#   Score far below the H1 mean (poor cross-species match):
#     the wider tail raises density at that low score -> score_likelihood_cov
#     INCREASES. Secondary effect; these candidates are already ranked low.
#
# The crossover is at exactly +/- 1 sigma from the H1 mean.
#
# To demonstrate the primary (negative delta) effect, use within-species
# pairs that happen to have coverage < 1. These are rare in the training
# matrix (same-species sequences usually have coverage = 1) but do exist.
# This is a diagnostic preview only; in production use your real match
# object from TaxaMatch (Workflow 4).

# Within-species pairs with coverage < 1 (good matches, expected negative delta)
h1_low_cov_ids <- ref_matrix |>
  dplyr::filter(species.x == species.y, id_x != id_y, coverage < 0.99) |>
  dplyr::pull(id_x) |>
  unique() |>
  head(5)

if (length(h1_low_cov_ids) > 0) {
  test_match <- ref_matrix |>
    dplyr::filter(id_x %in% h1_low_cov_ids) |>
    dplyr::rename(
      observation_id = id_x,
      score_original = p_match,
      family         = family.x,
      genus          = genus.x,
      species        = species.x
    ) |>
    TaxaTools::create_taxon_names(rank_system) |>
    dplyr::select(observation_id, score_original, coverage,
                  taxon_name, taxon_name_rank,
                  dplyr::any_of(rank_system))

  preview <- evaluate_likelihoods(
    match_df     = test_match,
    model_params = model,
    rank_system  = rank_system,
    min_coverage = NULL    # no hard filter -- show full coverage range
  )

  cat("\n--- score_likelihood vs score_likelihood_cov (within-species, H1 only) ---\n")
  preview$likelihoods |>
    dplyr::filter(hypothesis_type == "specific_candidate") |>
    dplyr::left_join(
      dplyr::distinct(test_match, observation_id, coverage),
      by = "observation_id"
    ) |>
    dplyr::mutate(delta = round(score_likelihood_cov - score_likelihood, 4)) |>
    dplyr::select(observation_id, taxon_name, coverage,
                  score_likelihood, score_likelihood_cov, delta) |>
    dplyr::arrange(coverage) |>
    print(n = 20)

  cat("\nExpected: negative delta (good match near H1 mean -> wider sigma\n")
  cat("reduces peak density -> lower likelihood for low-coverage candidates).\n")
  cat("Zero delta = coverage was 1 for that candidate; no inflation applied.\n")
} else {
  cat("No within-species pairs with coverage < 0.99 found.\n")
  cat("All training pairs have full-length alignments for this database.\n")
  cat("The coverage adjustment will only activate for real query data\n")
  cat("(e.g. BLAST hits from truncated reads) where qcovs < 100%%.\n")
}


# ---- 8. Save model and threshold for Workflow 4 -----------------------------
saveRDS(model, "trained_model.rds")
saveRDS(best_thresh, "coverage_threshold.rds")   # min_coverage filter for Workflow 4
message("Saved trained_model.rds and coverage_threshold.rds")

message("\nWorkflow 3 complete.")
message("Next: Workflow 4 (convert match scores to likelihoods)")
message("  Pass coverage_threshold.rds as min_coverage to evaluate_likelihoods()")
message("  Compare score_likelihood vs score_likelihood_cov in Workflow 4 output")

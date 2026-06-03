# TaxaAssign: LLM-Shortcut Workflow
# ============================================================================
# LLM-shortcut pipeline: match scores + LLM priors -> Bayesian posteriors
#
# Shortcut for: TaxaLikely -> TaxaExpect -> TaxaAssign
#   - Replaces the trained likelihood model with exponentially-weighted scores
#   - Replaces occurrence-based priors with LLM biogeographic knowledge
#   - Posteriors computed via compute_posterior() as normal
#
# Dataset example: MiFish eDNA, tidewater goby sites, Southern California
# Input:   TaxaMatch/inst/match_obj.rds
# Output:  posteriors data frame (one row per sample x taxon hypothesis)
#
# Appropriate for: exploratory analysis, well-known taxa, known ecoregion
# Full pipeline needed for: publication, rare/novel taxa, poorly-known regions
#
# Parallel structure to the Bayesian workflow:
#   LLM workflow     -- assign_taxa_llm() generates both likelihoods and priors
#   Bayesian workflow -- TaxaLikely and TaxaExpect supply them independently
# ============================================================================


# =============================================================================
# SECTION 1: LOAD INPUTS
# =============================================================================
library(TaxaHabitat)
library(TaxaAssign)   # assign_taxa_llm(), compute_posterior(), posterior_consensus()
library(TaxaLikely)   # audit_reference_coverage()
library(TaxaTools)    # call_anthropic_api() and other llm_fn providers
library(dplyr)

# ---- 1a. Load match object --------------------------------------------------
#match_df <- readRDS(file.choose())  # select your match data file (.rds)
# Assumes match_df has been cleaned and is not redundant (see TaxaMatch workflow)


#from TaxaMatch
#estuarine fishes 12S: JVB1846-MiFishU-esv-data.csv (173 seconds)
#California intertidal fishes 12S: JVB2844-MiFishU-esv-data (381.12 seconds)
#Palmyra fishes (big) 12S: JVB1950-MiFishU-esv-data
#Palmyra COI: Palmyra2019-UniCOI-esv-data
library(TaxaMatch)
match_df <- standardize_match_data(
  data            = NULL,        # opens file.choose()
  observation_id_col   = "ESVId",
  score_col       = "PercMatch",
  # taxonomy_ranks = NULL        # auto-detected from Kingdom...Species columns
  lowercase_names = TRUE         # default: all col names → lowercase
)|>
  dplyr::mutate(taxon_name = TaxaTools::clean_taxon_names(taxon_name))|>#get rid of subspecies, authors, etc.
filter_redundant_hypotheses()

cat("Match object:", nrow(match_df), "rows x", ncol(match_df), "cols\n")
cat("Samples:", n_distinct(match_df$observation_id), "\n")
cat("Taxon names:", n_distinct(match_df$taxon_name), "\n")
cat("Score range:", paste(range(match_df$score_original), collapse = " - "), "\n")
cat("Marker(s):", paste(unique(match_df$testid), collapse = ", "), "\n\n")

# =============================================================================
# SECTION 2: CHOOSE LLM PROVIDER + DEFINE CONTEXT
# =============================================================================

# ---- 2a. Choose LLM provider ------------------------------------------------
# Default: call_anthropic_api (requires ANTHROPIC_API_KEY in .Renviron).
# Alternatives — uncomment to use:
t0 <- Sys.time()
llm_fn <- TaxaTools::call_anthropic_api

# Gemini (free tier; requires GEMINI_API_KEY):
# llm_fn <- function(p) TaxaTools::call_gemini_api(p, model = "gemini-2.0-flash")

# OpenAI (requires OPENAI_API_KEY):
# llm_fn <- function(p) TaxaTools::call_openai_api(p, model = "gpt-4o-mini")

# Local Ollama (no key needed):
# llm_fn <- function(p) TaxaTools::call_ollama_api(p, model = "llama3.2")

# ---- 2b. Define context + known presence/absence ----------------------------
# Shared across all samples in this dataset.
# Supply per-sample context by adding a observation_id column and one row per sample.
#
# Results are sensitive to these inputs. A user should run the model and assess
# if there are any obvious false positives or false negatives. These are key
# assumptions that can increase accuracy and precision.

# Option A: Auto-populate context from taxon names (requires TaxaHabitat)
ctx <- build_context(
  taxon_names     = unique(match_df$taxon_name[match_df$score_original == 100]),# short list of the best matches
  geographic_hint = "Southern California NOT Gulf of California Estuary and Coastal Lagoon",
  date            = "2025",
  habitat_scheme  = "IUCN_L1",# better to enter a custom list.
  llm_fn          = llm_fn
)
# Inspect per-species habitat weights: attr(ctx, "habitats_df")

# Option B: Manual context (if you know the site details)
# ctx <- data.frame(
#   ecoregion    = "Southern California Bight",
#   main_habitat = "rocky intertidal / kelp forest",
#   date         = "2025"
# )

# Known present: species confirmed at the site (LLM context only — boosts prior)
known_present <- c()

# Known absent: species confirmed NOT at the site
# Math suppression: prior × (1 - absent_detection_prob), then renormalize
known_absent <- c()



# =============================================================================
# SECTION 3: UNREFERENCED SPECIES
# =============================================================================
# Unreferenced species: described taxa that share a genus with a scored
# candidate but have NO barcode reference sequence. Because TaxaMatch can
# only return taxa with references, an unreferenced species can never appear
# as a named match — even if it is the true source of the sequence.
#
# Inserting unreferenced species as explicit hypotheses lets the LLM evaluate
# geographic plausibility for species that are taxonomically plausible but
# unrepresented in any reference library.
#
# Example: Fundulus parvipinnis (native SCB, no 12S reference) is unreferenced;
# the LLM ranks it above Fundulus lima (Mexican, has reference).
#
# suggest_unreferenced_species() strategy (LLM-first, preferred):
#   1. LLM generates biogeographically plausible species per genus (one call
#      per batch of genera). Species outside this region are never queried.
#   2. Removes species already in match_df (skip-list: have references).
#   3. Queries NCBI nucleotide (retmax=0, count only) ONLY for plausible
#      remainder; count=0 -> unreferenced, count>0 -> has sequences.
#   4. Date filter embedded in query term as [PDAT] range.
#
# expand_to_family = TRUE: for genera where the LLM finds NO plausible species,
#   a second LLM call asks for plausible species in OTHER genera of the same
#   family. Use when you suspect the true taxon belongs to a represented family
#   but an unsampled genus.
#
# To skip unreferenced species insertion entirely, set unreferenced_species <- NULL.

unreferenced_species <- suggest_unreferenced_species(
  match_df,
  context          = ctx,
  barcode_term     = "12S",            # adjust to your marker: "COI", "ITS2", etc.
  # barcode_term   = c("12S", "MiFish"),  # OR-ed; catches variant annotations
  llm_fn           = llm_fn,
  max_date         = "2024/12/31",     # set to your reference library build date
  expand_to_family = TRUE,
  # ncbi_api_key   = Sys.getenv("ENTREZ_KEY")  # faster with key (10 req/s vs 3)
)
cat("Unreferenced taxa found:", length(unreferenced_species), "\n")
cat("Census:\n"); print(attr(unreferenced_species, "census"))
if (!is.null(attr(unreferenced_species, "family_census"))) {
  cat("Family census:\n"); print(attr(unreferenced_species, "family_census"))
}

# -- ALTERNATIVE: exhaustive approach (slower but does not require an LLM) ----
# audit_barcode_coverage() queries NCBI for EVERY non-reference species per
# genus via the NCBI taxonomy subtree. More complete for species-rich genera,
# but much slower.
#
# coverage <- TaxaLikely::audit_barcode_coverage(
#   match_df,
#   barcode_term = "12S",
#   max_date     = "2024/12/31",
#   target_rank  = "genus"
# )
# unreferenced_species <- coverage$unreferenced


# =============================================================================
# SECTION 4: COMPUTE POSTERIORS
# =============================================================================
# assign_taxa_llm() generates likelihoods (from exponentially-weighted scores)
# and priors (from LLM biogeographic assessment) in one step, then calls
# compute_posterior() internally.
#
# One LLM call per group (here: one call for all samples, since context is
# shared). The LLM receives the unique taxon list for the group and returns
# a flat JSON array of prior weights. All sample-level bookkeeping is in R.
#
# To split by region or habitat, supply context with a observation_id column and
# set context_group = "ecoregion" (or c("ecoregion", "habitat")).
# Each unique combination then gets its own LLM call.

result <- assign_taxa_llm(
  match_df,
  context              = ctx,
  known_present        = known_present,
  known_absent         = known_absent,
  absent_detection_prob = 0.9,
  context_group        = NULL,    # all samples share one context -> one LLM call
  llm_fn               = llm_fn,
  score_threshold      = 80,      # drop candidates below this score
  top_n                = 10,      # max candidates per sample in the taxon list
  score_sharpness      = 0.1,     # exponential weight sharpness (0 = uniform lik)
  unknown_lik_weight   = 0.05,    # likelihood and prior weight for the unreferenced_family catch-all row
  unreferenced_taxa    = unreferenced_species,
  taxa_per_call        = 30,      # taxa per LLM call (batches large taxon lists)
  pause_seconds        = 1,       # delay between calls (rate limit buffer)
  prior_phi            = c(high = 50, moderate = 10, low = 3),
                                   # Beta concentration by information_quality:
                                   # phi = effective sample size of LLM judgment
                                   # high=50 (well-studied), moderate=10, low=3 (data-deficient)
                                   # scalar = uniform phi; NULL = fixed priors (no MC on priors)
  n_sims               = 1000,    # MC simulations; propagates Beta prior + likelihood uncertainty
  verbose              = FALSE
)

cat("Posteriors computed for", n_distinct(result$observation_id), "samples\n")
cat("Total rows (sample x hypothesis):", nrow(result), "\n")

# ---- 4b. Inspect unreferenced_family posterior -------------------------------
# Flag samples where the catch-all unreferenced_family row beats every named candidate
ambiguous <- result |>
  group_by(observation_id) |>
  filter(posterior_point_est == max(posterior_point_est)) |>
  filter(hypothesis_type == "unreferenced_family") |>
  ungroup()

cat("Samples where unreferenced_family has the highest posterior:",
    nrow(ambiguous), "\n")

# saveRDS(result, file.choose(new = TRUE))  # choose where to save llm_posteriors.rds


# =============================================================================
# SECTION 5: CONSENSUS TAXONOMY + EMPIRICAL BAYES REFINEMENT
# =============================================================================
# Collapse posteriors to one row per observation_id via LCA (Lowest Common Ancestor).
# The LCA is the finest taxonomic rank at which all "plausible" hypotheses agree.
#
# Plausible set: hypotheses that together account for >= cumulative_threshold of
# the named-taxon posterior mass, after excluding any below min_posterior.
# (unreferenced_family rows, which have NA taxon_name, are always excluded from LCA.)

consensus <- posterior_consensus(
  result,
  cumulative_threshold    = 0.90,
  min_posterior            = 0.05,
  posterior_col            = "posterior_point_est",
  lookup_missing_taxonomy  = TRUE,
  backbone_id              = 4,
  rank_system              = c("family", "genus", "species"),
  species_reference        = unreferenced_species
)

result_updated <- update_prior_from_consensus(
  result, consensus,
  presence_multiplier = 5,
  n_sims              = 1000
)

consensus_final <- posterior_consensus(
  result_updated,
  cumulative_threshold    = 0.90,
  min_posterior            = 0.05,
  posterior_col            = "posterior_point_est",
  lookup_missing_taxonomy  = TRUE,
  backbone_id              = 4,
  rank_system              = c("order","family", "genus", "species"),
  species_reference        = unreferenced_species
)

cat("\nConsensus taxonomy summary:\n")
print(table(consensus_final$consensus_rank, useNA = "always"))
cat("\nResolved to species-level:",
    sum(consensus_final$is_resolved, na.rm = TRUE), "/",
    nrow(consensus_final), "samples\n")

# Inspect unresolved samples
unresolved <- consensus_final |>
  filter(is.na(consensus_taxon) | !is_resolved)
if (nrow(unresolved) > 0L) {
  cat("\nUnresolved samples:\n")
  print(unresolved[, c("observation_id", "consensus_taxon", "consensus_rank",
                        "n_plausible")])
}

splist<-consensus_final$consensus_taxon%>%unique()
splist[order(splist)]
cat("Elapsed:", round(difftime(Sys.time(), t0, units = "secs"), 2), "sec\n")

# =============================================================================
# SECTION 6: SCORE-BASED CONSENSUS (CONVENTIONAL APPROACH)
# =============================================================================
# Conventional metabarcoding consensus for comparison with the Bayesian
# posterior_consensus() above.  Works directly from raw match scores — no
# trained model, no priors, no LLM.
#
# Thresholds below follow the common eDNA convention (e.g., GITA functions,
# Jonah Ventures pipeline):
#   species >= 98%, genus >= 95%, family >= 90%, order >= 85%
#
# max_gap = 1: all hits within 1% of the top score contribute to the LCA.
#   This is the "top-hit tie-breaking" logic used by most BLAST-LCA pipelines.
#
# whitelist: optional plausible taxa list.  When supplied, the consensus is
#   upranked to the nearest rank where a whitelist member agrees.  This
#   approximates the "likely list" filtering in the GITA pipeline.

score_con_wilder <- score_consensus(
  match_df,
  min_score       = 100,       # drop hits below 80% (same as score_threshold above)
  max_gap         = 0,        # include all hits within 1% of best score for LCA
  rank_thresholds = NULL,
  whitelist       = NULL,     # set to a plausible taxon list if available
  score_col       = "score_original",
  rank_system     = c("family", "genus", "species")
)

score_con_thresholds <- score_consensus(
  match_df,
  min_score       = 100,       # drop hits below 80% (same as score_threshold above)
  max_gap         = 0,        # include all hits within 1% of best score for LCA
  rank_thresholds = c(species = 98, genus = 95, family = 90, order = 85),
  whitelist       = NULL,     # set to a plausible taxon list if available
  score_col       = "score_original",
  rank_system     = c("family", "genus", "species")
)

score_con_JV <- score_consensus(
  match_df,
  min_score       = 90,       # drop hits below 80% (same as score_threshold above)
  max_gap         = 1,        # include all hits within 1% of best score for LCA
  rank_thresholds = NULL,
  whitelist       = NULL,     # set to a plausible taxon list if available
  score_col       = "score_original",
  rank_system     = c("order","family", "genus", "species")
)

cat("\nScore-based consensus summary:\n")
print(table(score_con_JV$consensus_rank, useNA = "always"))
cat("Resolved to species-level:",
    sum(score_con_JV$is_resolved, na.rm = TRUE), "/",
    nrow(score_con_JV), "samples\n")


# =============================================================================
# SECTION 7: COMPARE POSTERIOR vs SCORE-BASED CONSENSUS
# =============================================================================
# Side-by-side comparison to evaluate where the two approaches agree and
# disagree.  Disagreements highlight samples where priors or likelihood
# modelling change the outcome — the value added (or risk) of the Bayesian
# approach.

comparison <- merge(
  consensus_final[, c("observation_id", "consensus_taxon", "consensus_rank",
                       "is_resolved", "consensus_posterior", "n_plausible","plausible_taxa")],
  score_con_JV[, c("observation_id", "consensus_taxon", "consensus_rank",
                 "is_resolved", "top_score", "n_taxa")],
  by = "observation_id", suffixes = c("_posterior", "_score")
)


comparison <- merge(
  consensus_final[, c("observation_id", "consensus_taxon", "consensus_rank",
                      "is_resolved", "consensus_posterior", "n_plausible","plausible_taxa")],
  score_con_wilder[, c("observation_id", "consensus_taxon", "consensus_rank",
                   "is_resolved", "top_score", "n_taxa")],
  by = "observation_id", suffixes = c("_posterior", "_score")
)


# Flag agreement/disagreement
comparison$taxon_agree <- comparison$consensus_taxon_posterior ==
                          comparison$consensus_taxon_score
comparison$rank_agree  <- comparison$consensus_rank_posterior ==
                          comparison$consensus_rank_score
# Handle NAs in comparison
comparison$taxon_agree[is.na(comparison$consensus_taxon_posterior) |
                       is.na(comparison$consensus_taxon_score)] <- FALSE
comparison$rank_agree[is.na(comparison$consensus_rank_posterior) |
                      is.na(comparison$consensus_rank_score)] <- FALSE

cat("\n--- Posterior vs Score Consensus Comparison ---\n")
cat("Total samples:", nrow(comparison), "\n")
cat("Taxon agreement:", sum(comparison$taxon_agree), "/", nrow(comparison),
    sprintf("(%.0f%%)\n", 100 * mean(comparison$taxon_agree)))
cat("Rank agreement: ", sum(comparison$rank_agree), "/", nrow(comparison),
    sprintf("(%.0f%%)\n", 100 * mean(comparison$rank_agree)))

# Summary table: resolution level by method
cat("\nResolution comparison:\n")
res_table <- table(
  posterior = ifelse(is.na(comparison$consensus_rank_posterior), "unresolvable",
                     comparison$consensus_rank_posterior),
  score    = ifelse(is.na(comparison$consensus_rank_score), "unresolvable",
                     comparison$consensus_rank_score)
)
print(res_table)

# Interesting disagreements: where the methods assign different taxa
disagree <- comparison[!comparison$taxon_agree, ]
if (nrow(disagree) > 0L) {
  cat("\nDisagreements (", nrow(disagree), " samples):\n")
  print(disagree[, c("observation_id",
                      "consensus_taxon_posterior", "consensus_rank_posterior",
                      "consensus_taxon_score", "consensus_rank_score",
                      "consensus_posterior", "top_score","plausible_taxa")])
}

compare_workflows<-disagree%>%dplyr::select(plausible_taxa,consensus_taxon_posterior,consensus_taxon_score)%>%unique()

write.csv(compare_workflows$plausible_taxa, "Wilder_TAXAID_plausible.csv", row.names = FALSE)
write.csv(compare_workflows[,2:3], "Wilder_TAXAID.csv", row.names = FALSE)

# Cases where posterior resolves further than score (value of priors)
posterior_finer <- comparison[
  !is.na(comparison$consensus_rank_posterior) &
  !is.na(comparison$consensus_rank_score) &
  match(comparison$consensus_rank_posterior,
        c("family", "genus", "species")) >
  match(comparison$consensus_rank_score,
        c("family", "genus", "species")), ]
cat("\nPosterior resolved finer than score:", nrow(posterior_finer), "samples\n")

# Cases where score resolves further (prior may be pulling toward caution)
score_finer <- comparison[
  !is.na(comparison$consensus_rank_posterior) &
  !is.na(comparison$consensus_rank_score) &
  match(comparison$consensus_rank_score,
        c("family", "genus", "species")) >
  match(comparison$consensus_rank_posterior,
        c("family", "genus", "species")), ]
cat("Score resolved finer than posterior:", nrow(score_finer), "samples\n")


# =============================================================================
# SECTION 8: REPORT
# =============================================================================
# Option A: Report for posterior consensus (requires result + posterior_consensus output)
report_posterior <- generate_report(
  result    = result_updated,
  consensus = consensus_final,
  unreferenced_result = unreferenced_species,
  data_type = "eDNA", marker = "12S MiFish",
  study_description = "eDNA survey of a southern California estuary",
  llm_fn = TaxaTools::call_anthropic_api
)

# Option B: Report for score-based consensus (result = NULL, no posteriors)
report_score <- generate_report(
  result    = NULL,
  consensus = score_con_JV,
  data_type = "eDNA", marker = "12S MiFish",
  study_description = "eDNA survey of a southern California estuary",
  llm_fn = TaxaTools::call_anthropic_api
)


# =============================================================================
# SECTION 9: ASSEMBLED REPORT (Distributed Report Architecture)
# =============================================================================
# Each package's report_*() function captures what it did at that pipeline step.
# assemble_report() combines them into a unified Methods + Results document.
# This is complementary to generate_report() above -- use one or both.

# Build per-package sections from the objects already in memory:
library(TaxaFetch)    # report_fetch()
library(TaxaMatch)    # report_match()
library(TaxaHabitat)  # report_habitat()

# match_obj should have report_params from blast_sequences()
match_sec <- TaxaMatch::report_match(match_df, data_type = "eDNA")

# If you have occurrence data (from TaxaFetch), include it:
# fetch_sec <- TaxaFetch::report_fetch(occurrences, study_area = "Santa Barbara Channel")

# If you have habitat weights:
# habitat_sec <- TaxaHabitat::report_habitat(habitat_weights)

# Assignment section from this workflow's outputs:
assign_sec <- TaxaAssign::report_assign(result_updated, consensus_final, data_type = "eDNA")

# Assemble whichever sections you have:
assembled <- TaxaTools::assemble_report(
  match_sec, assign_sec,
  title = "eDNA Taxonomic Assignment — LLM Workflow"
)
cat(assembled)


# =============================================================================
# WRAPPER ALTERNATIVE: run_llm_pipeline()
# =============================================================================
# Replaces Sections 2-5 above (context → unreferenced → posteriors → consensus)
# with a single call. Optionally auto-generates context from taxon names and
# detects unreferenced species.
#
# The step-by-step workflow above gives full control over each stage;
# the wrapper is for the common case where defaults suffice.
#
#from TaxaMatch
# estuarine fishes 12S: JVB1846-MiFishU-esv-data.csv (173 seconds)
#California intertidal fishes 12S: JVB2844-MiFishU-esv-data (381.12 seconds)
#Palmyra fishes (big) 12S: JVB1950-MiFishU-esv-data
#Palmyra COI: Palmyra2019-UniCOI-esv-data
# library(TaxaMatch)
# library(TaxaAssign)
# match_df <- standardize_match_data(
#   data            = NULL,        # opens file.choose()
#   observation_id_col   = "ESVId",
#   score_col       = "PercMatch",
#   # taxonomy_ranks = NULL        # auto-detected from Kingdom...Species columns
#   lowercase_names = TRUE         # default: all col names → lowercase
# )|>
#   dplyr::mutate(taxon_name = TaxaTools::clean_taxon_names(taxon_name))|>#get rid of subspecies, authors, etc.
#   filter_redundant_hypotheses()
#
# llm_result <- run_llm_pipeline(
#   match_df             = match_df,
#   context              = NULL,                   # NULL = auto-generate via build_context()
#   auto_context         = TRUE,
#   geographic_hint      = "Southern California estuary",
#   date                 = "2025",
#   habitat_scheme       = "IUCN_L1",
#   llm_fn               = TaxaTools::call_anthropic_api,
#   detect_unreferenced  = TRUE,
#   barcode_term         = "12S",
#   expand_to_family     = TRUE,
#   max_date             = "2024/12/31",
#   score_threshold      = 80,
#   score_sharpness      = 0.1,
#   known_present        = c(),
#   known_absent         = c(),
#   prior_phi            = c(high = 50, moderate = 10, low = 3),
#   n_sims               = 1000L,
#   cumulative_threshold = 0.90,
#   presence_multiplier  = 5,
#   rank_system          = c("family", "genus", "species"),
#   generate_report      = TRUE,
#   report_params        = list(data_type = "eDNA", marker = "12S MiFish",
#                               study_description = "eDNA survey of a southern California estuary"),
#   verbose              = TRUE
# )
#
# # Equivalent outputs:
# consensus_final       <- llm_result$consensus
# result_updated        <- llm_result$result
# ctx                   <- llm_result$context
# unreferenced_species  <- llm_result$unreferenced
# report                <- llm_result$report
llm_workflow_consensus<-consensus_final

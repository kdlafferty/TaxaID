# ==============================================================================
# WORKFLOW: COMPUTE POSTERIORS (TaxaAssign)
# ==============================================================================
# Purpose: Combine likelihoods (from TaxaMatch/TaxaLikely) with occurrence-based
#   priors (from TaxaExpect) to compute Bayesian posterior probabilities per
#   taxonomic hypothesis, then reduce to one consensus call per observation.
#
# Audience: someone learning TaxaAssign step by step, continuing directly from
#   TaxaExpect's generate_priors_workflow.R.
#
# WHY THIS SCRIPT USES A SYNTHETIC LIKELIHOOD OBJECT: TaxaMatch and TaxaLikely
# (the packages that would normally produce a real likelihood object from BLAST/
# classifier scores) do not yet have Layer-1 workflow scripts of their own --
# they need multiple data-type variants (sequence/acoustic/image) per the
# ecosystem's workflow redesign plan, which is deferred, separate scope. Rather
# than build all of TaxaMatch+TaxaLikely inline here, DEBUG_MODE = TRUE builds a
# small, CLEARLY-LABELED SYNTHETIC likelihood object standing in for real
# TaxaMatch/TaxaLikely output. It is built using the REAL species names already
# present in taxaexpect_priors (loaded from TaxaExpect's checkpoint), so the
# join in Step 1 is genuine and meaningful, not just structurally-typed fake
# data -- the same "tutorial-only shortcut, real downstream data" pattern used
# in TaxaHabitat's inline main_habitat tag and TaxaExpect's live-fallback fetch.
#
# TWO VARIANTS -- BOTH run live in DEBUG_MODE, on the same tutorial taxa:
#   VARIANT A (Steps 1-4) -- THE BAYESIAN PATHWAY
#     join_priors() -> compute_posterior() -> posterior_consensus() ->
#     add_slash_taxon(). Consumes the real taxaexpect_priors checkpoint plus
#     the synthetic likelihood object described above.
#   VARIANT B (Step 5) -- THE LLM/NO-SCORE PATHWAY
#     assign_taxa_llm() -> posterior_consensus() -> add_slash_taxon() (or the
#     run_llm_pipeline() wrapper). IMPORTANT: this pathway has NO
#     taxaexpect_priors parameter at all -- it asks the LLM directly for
#     range_status/habitat_fit/information_quality per taxon and builds its
#     OWN priors from that ecological reasoning, completely bypassing
#     TaxaExpect's occurrence-based priors. It is a genuinely parallel,
#     independent pathway, not a variant of the Bayesian one -- useful when no
#     occurrence-based prior model exists (e.g. morphological/expert-ID data
#     with no reference database, or when TaxaExpect's GLMM can't converge on
#     sparse tutorial-scale data -- see generate_priors_workflow.R's own
#     fallback-level messages). Runs its own real LLM call, on a separate
#     synthetic match_df (a different object shape from Variant A's
#     likelihoods -- see Step 5).
#
# Output: two consensus tibbles, taxaassign_consensus (Variant A) and
#   taxaassign_consensus_llm (Variant B); see "Output" block at the end of
#   this file for the full column contract consumed by TaxaFlag.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaAssign::, TaxaTools::, dplyr::, tibble::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps
# to a future function argument.

# DEBUG_MODE = TRUE  -> load TaxaExpect's real tutorial checkpoint and build a
#                       small synthetic likelihood object from its real taxa
#                       (see the header note above for why).
# DEBUG_MODE = FALSE -> plug in your own likelihoods object from TaxaMatch/
#                       TaxaLikely (see the "SWAP IN YOUR OWN DATA" block below
#                       Section 1)
DEBUG_MODE <- TRUE

# Number of taxa (from the real taxaexpect_priors species pool) to use when
# building the synthetic likelihood object, and the number of synthetic
# observations to construct. Kept small -- this is a join-mechanics demo, not
# a benchmark. See Section 1 for the graceful-degradation guard when fewer
# than N_SYNTH_TAXA species are actually available.
N_SYNTH_TAXA <- 4L
N_SYNTH_OBS  <- 3L

# rank_system for join_priors()/posterior_consensus(): matches the taxonomy
# columns present on the synthetic likelihood object (family/genus/species).
RANK_SYSTEM <- c("family", "genus", "species")

if (DEBUG_MODE) {

  # ---- Tutorial example: continue from TaxaExpect's Gadus checkpoint --------
  # This is the exact readRDS() line documented in generate_priors_workflow.R's
  # Output block (its Step 9 saves taxaexpect_priors to
  # "<OUT_PREFIX>_taxaexpect_priors.rds" with OUT_PREFIX = "tutorial_gadus").
  # Unlike TaxaExpect's own DEBUG_MODE fallback, there is no sensible "fetch
  # fresh data" fallback here -- the entire point of this script is to consume
  # the prior pipeline's output, so a missing checkpoint is a hard stop.
  .priors_checkpoint <- file.path(tempdir(), "tutorial_gadus_taxaexpect_priors.rds")

  if (!file.exists(.priors_checkpoint)) {
    stop("DEBUG_MODE = TRUE but TaxaExpect's checkpoint was not found at ",
         .priors_checkpoint, ". Run TaxaExpect's generate_priors_workflow.R ",
         "first -- this script has nothing meaningful to demonstrate without ",
         "real taxaexpect_priors output.")
  }

  taxaexpect_priors <- readRDS(.priors_checkpoint)
  message("DEBUG_MODE = TRUE -- loaded TaxaExpect's checkpoint: ", .priors_checkpoint,
          " (", nrow(taxaexpect_priors), " prior row(s)).")

  # CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: TaxaExpect::generate_full_priors()'s
  # own roxygen docs (R/generate_full_priors.R, @note) state its output has
  # taxon_name but NOT taxon_name_rank, and that join_priors() requires the
  # latter -- join_priors() errors outright ("missing required column(s):
  # taxon_name_rank") without it. generate_full_priors()'s every modelled row
  # is species-level by construction (TaxaExpect predicts at the species rank
  # only); the one exception is the global-floor undetected row, whose
  # taxon_name is NA and so has no meaningful rank either. Add the column
  # directly rather than routing through TaxaTools::create_taxon_names()
  # (which derives taxon_name/taxon_name_rank FROM separate rank columns --
  # taxaexpect_priors has only the single flat taxon_name string, not that).
  taxaexpect_priors$taxon_name_rank <- ifelse(
    is.na(taxaexpect_priors$taxon_name), NA_character_, "species"
  )

  # ---- Derive SITE_GRID_ID / SITE_HABITAT FROM taxaexpect_priors ------------
  # taxaexpect_priors is already filtered to one focal grid_id by TaxaExpect's
  # Step 9 -- do not hardcode these values. Guard against the (should-not-
  # happen) case of a multi-site object slipping through, rather than silently
  # taking the first value.
  SITE_GRID_ID <- unique(stats::na.omit(taxaexpect_priors$grid_id))
  SITE_HABITAT <- unique(stats::na.omit(taxaexpect_priors$main_habitat))

  if (length(SITE_GRID_ID) != 1L) {
    stop("Expected exactly one grid_id in taxaexpect_priors (single-site by ",
         "construction from generate_priors_workflow.R), but found ",
         length(SITE_GRID_ID), ": ", paste(SITE_GRID_ID, collapse = ", "),
         ". Check the upstream TaxaExpect checkpoint.")
  }
  if (length(SITE_HABITAT) != 1L) {
    stop("Expected exactly one main_habitat in taxaexpect_priors (single-site ",
         "by construction from generate_priors_workflow.R), but found ",
         length(SITE_HABITAT), ": ", paste(SITE_HABITAT, collapse = ", "),
         ". Check the upstream TaxaExpect checkpoint.")
  }
  message(sprintf("  SITE_GRID_ID = \"%s\", SITE_HABITAT = \"%s\" (derived from taxaexpect_priors).",
                  SITE_GRID_ID, SITE_HABITAT))

  # ---- Build the synthetic likelihood object -- TUTORIAL-ONLY SHORTCUT ------
  # THIS IS NOT REAL TaxaMatch/TaxaLikely OUTPUT. A real likelihood object
  # would come from BLAST/classifier scores run through TaxaLikely's
  # score-to-likelihood pipeline. Here we pick real species names already
  # modelled in taxaexpect_priors (the live Gadidae species GBIF actually
  # returned upstream -- never hardcoded, since the exact species vary run to
  # run) and construct plausible-looking competing-hypothesis rows for a
  # handful of synthetic "ASV" observations, loosely mimicking a real
  # BLAST-derived likelihood shape (one clear top candidate, one or two lower-
  # likelihood congeners). There is no need for statistical rigor here -- this
  # exists solely to exercise join_priors()'s join mechanics against a real
  # prior table.
  .real_species <- unique(stats::na.omit(taxaexpect_priors$taxon_name))
  .real_species <- .real_species[grepl("^[A-Z][a-z]+ [a-z]+$", .real_species)]

  message(sprintf("  %d species-level taxon name(s) available in taxaexpect_priors.",
                  length(.real_species)))

  .n_synth_taxa <- min(N_SYNTH_TAXA, length(.real_species))
  if (.n_synth_taxa < 2L) {
    stop("Fewer than 2 species-level taxon names are available in ",
         "taxaexpect_priors -- cannot build even a minimal synthetic ",
         "likelihood object with competing hypotheses. Re-run TaxaExpect's ",
         "generate_priors_workflow.R with a wider fetch (more species breadth) ",
         "before continuing.")
  }
  if (.n_synth_taxa < N_SYNTH_TAXA) {
    message(sprintf(
      "  Only %d species-level taxa available (< N_SYNTH_TAXA = %d) -- using ",
      .n_synth_taxa, N_SYNTH_TAXA
    ), "all of them. Competing-hypothesis rows below will draw from this ",
    "smaller pool; some synthetic observations may repeat the same congener ",
    "pairing as a result.")
  }

  .synth_taxa <- head(.real_species, .n_synth_taxa)
  .synth_genus <- sub(" .*", "", .synth_taxa)

  # family = "Gadidae" is hardcoded deliberately here: it is the real query
  # family used upstream in TaxaExpect's live-fallback fetch (see
  # generate_priors_workflow.R's Section "Fallback: live GBIF fetch"), not a
  # guess. If you swap in a different upstream taxon, update this to match.
  .synth_family <- "Gadidae"

  message(sprintf("  Synthetic likelihood object will draw from %d real taxon name(s): %s",
                  length(.synth_taxa), paste(.synth_taxa, collapse = ", ")))

  # One "observation" = one synthetic ASV with 2-3 competing candidate-taxon
  # rows. Top candidate gets a score_likelihood near 0.9-1.0; congener(s) get
  # progressively lower plausible-looking values. score_likelihood_mean/_sd
  # loosely mimic a BLAST-derived likelihood shape (tight SD on a clear winner,
  # wider SD on a weaker candidate) -- illustrative only, not fit to real data.
  .build_obs <- function(obs_id, taxa_idx) {
    n_cand <- length(taxa_idx)
    top_score <- stats::runif(1, 0.90, 0.99)
    if (n_cand == 1L) {
      scores <- top_score
    } else {
      remaining <- sort(stats::runif(n_cand - 1L, 0.10, 0.60), decreasing = TRUE)
      scores <- c(top_score, remaining)
    }
    tibble::tibble(
      observation_id         = obs_id,
      taxon_name             = .synth_taxa[taxa_idx],
      taxon_name_rank        = "species",
      # CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: posterior_consensus()
      # requires hypothesis_type -- normally added by TaxaLikely::
      # evaluate_likelihoods() / TaxaAssign::expand_unreferenced_hypotheses(),
      # neither of which runs in this synthetic-data tutorial. Every synthetic
      # candidate here is a real, named species (not a placeholder for a
      # missing reference), so "specific_candidate" is the correct value for
      # all rows -- see posterior_consensus()'s documented LCA logic, which
      # treats specific_candidate/unreferenced_species/unreferenced_genus as
      # equally "named" hypotheses.
      hypothesis_type        = "specific_candidate",
      genus                  = .synth_genus[taxa_idx],
      family                 = .synth_family,
      score_likelihood       = scores,
      score_likelihood_mean  = scores,
      score_likelihood_sd    = ifelse(scores == max(scores), 0.02, 0.08)
    )
  }

  set.seed(42)  # reproducible tutorial output -- remove for real stochastic use
  .obs_ids <- paste0("ASV_", seq_len(N_SYNTH_OBS))
  .likelihoods_list <- lapply(seq_along(.obs_ids), function(i) {
    # Each observation gets 2-3 competing candidates (or fewer if the taxa
    # pool is very small), cycling through the available synthetic taxa so
    # every observation's top candidate differs where possible.
    n_cand   <- min(sample(2:3, 1L), .n_synth_taxa)
    top_idx  <- ((i - 1L) %% .n_synth_taxa) + 1L
    other_idx <- setdiff(seq_len(.n_synth_taxa), top_idx)
    cand_idx <- c(top_idx, head(other_idx, n_cand - 1L))
    .build_obs(.obs_ids[i], cand_idx)
  })

  likelihoods <- dplyr::bind_rows(.likelihoods_list)

  message(sprintf("  Synthetic likelihoods: %d observation(s), %d hypothesis row(s) total.",
                  length(.obs_ids), nrow(likelihoods)))
  message("  *** SYNTHETIC DATA NOTICE *** -- score_likelihood* columns above are ",
          "illustrative placeholders, NOT real BLAST/classifier output. Replace ",
          "with a real TaxaMatch/TaxaLikely likelihoods object for any real analysis.")

  # taxonomy_lookup for join_priors(): deduplicated taxon_name + rank columns
  # from this same synthetic object (per the CONFIG spec -- built from the
  # synthetic likelihood object itself, not a separate query).
  taxonomy_lookup <- likelihoods |>
    dplyr::distinct(taxon_name, taxon_name_rank, genus, family)

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your real likelihoods object + real
  # taxaexpect_priors checkpoint:
  #
  #   taxaexpect_priors <- readRDS("path/to/your_taxaexpect_priors.rds")
  #     (the object produced by TaxaExpect's generate_priors_workflow.R)
  #   taxaexpect_priors$taxon_name_rank <- ifelse(
  #     is.na(taxaexpect_priors$taxon_name), NA_character_, "species"
  #   )
  #     (REQUIRED: generate_full_priors() does not add taxon_name_rank, but
  #     join_priors() requires it -- see the comment above this block's
  #     DEBUG_MODE counterpart for why this one-liner is correct.)
  #
  #   likelihoods <- readRDS("path/to/your_likelihoods.rds")
  #     (the object produced by TaxaMatch + TaxaLikely -- a data frame with at
  #     minimum observation_id, taxon_name, taxon_name_rank, hypothesis_type
  #     (REQUIRED by posterior_consensus() -- "specific_candidate" for named
  #     reference matches, "unreferenced_species"/"unreferenced_genus" for
  #     TaxaLikely's placeholder rows), score_likelihood, score_likelihood_mean,
  #     score_likelihood_sd; plus taxonomy columns e.g. genus/family for
  #     rank_system detection. TaxaLikely::evaluate_likelihoods() /
  #     TaxaAssign::expand_unreferenced_hypotheses() normally add
  #     hypothesis_type for you -- add it manually only if building a
  #     likelihoods object by hand, as this tutorial does.)
  #
  #   taxonomy_lookup <- likelihoods |>
  #     dplyr::distinct(taxon_name, taxon_name_rank, genus, family)
  #     (or a richer external taxonomy source, e.g. match_df's reference
  #     taxonomy -- see ?TaxaAssign::join_priors)
  #
  #   SITE_GRID_ID <- unique(na.omit(taxaexpect_priors$grid_id))
  #   SITE_HABITAT <- unique(na.omit(taxaexpect_priors$main_habitat))
  #     (or your own site resolution -- see ?TaxaAssign::join_priors's `site`
  #     argument for the lat/lon auto-resolve path)
  #
  #   RANK_SYSTEM <- c("family", "genus", "species")   # match your data's columns
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real likelihoods/taxaexpect_priors objects ",
       "have been supplied. Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_gadus"

# ==============================================================================
# VARIANT A: THE BAYESIAN PATHWAY (join_priors -> compute_posterior ->
#            posterior_consensus -> add_slash_taxon)
# ==============================================================================
# This is the pathway that consumes TaxaExpect's occurrence-based priors.
# VARIANT B (the LLM/no-score pathway) is documented, NOT run, in Section 5.
# ==============================================================================

# ==============================================================================
# 1.  JOIN LIKELIHOODS TO PRIORS
# ==============================================================================
# Bridges the synthetic likelihood object to taxaexpect_priors: joins on
# taxon_name x taxon_name_rank x grid_id x main_habitat, applies the dark
# diversity fallback for any candidate without a modelled prior, fills
# taxonomy, and drops redundant coarser-rank hypotheses.
#
# singleton_taxonomy / expansion_taxonomy are omitted here: this tutorial's
# synthetic likelihood object is species-rank-only (no coarse-rank rows to
# expand) and taxaexpect_priors' own singleton-mirror rows already carry
# taxonomy from TaxaExpect's Step 7 (taxonomy = occurrences_clean), which is
# sufficient for the default flat dark-diversity floor used here. A real
# workflow with genus/family-rank likelihood rows or a need for hierarchical
# group priors should supply both -- see ?TaxaAssign::join_priors.

message("\n--- Step 1: Joining likelihoods to TaxaExpect priors ---")

likelihoods_w_prior <- TaxaAssign::join_priors(
  likelihoods       = likelihoods,
  taxaexpect_priors = taxaexpect_priors,
  site              = list(grid_id = SITE_GRID_ID, main_habitat = SITE_HABITAT),
  taxonomy_lookup   = taxonomy_lookup,
  rank_system       = RANK_SYSTEM
)

message(sprintf("  %d row(s) ready for compute_posterior().", nrow(likelihoods_w_prior)))

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so a future session can skip Step 1 by pasting the readRDS() line
# below -- no file.exists()-gated auto-reload; you decide when to reuse this.
likelihoods_w_prior_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_likelihoods_w_prior.rds"))
saveRDS(likelihoods_w_prior, likelihoods_w_prior_path)
message(sprintf("  Saved: %s", likelihoods_w_prior_path))
message(sprintf("  To reuse without re-joining, paste:\n    likelihoods_w_prior <- readRDS(\"%s\")",
                likelihoods_w_prior_path))

# ==============================================================================
# 2.  COMPUTE POSTERIOR
# ==============================================================================
# Core Bayes update: normalizes likelihoods within each observation_id, then
# combines with the joined prior (point-estimate path always runs; Monte Carlo
# path runs when n_sims > 0 and at least one source of uncertainty exists).

message("\n--- Step 2: Computing posteriors ---")

posterior_df <- TaxaAssign::compute_posterior(
  likelihood_w_prior = likelihoods_w_prior,
  n_sims             = 1000
)

message(sprintf("  %d posterior row(s) computed across %d observation(s).",
                nrow(posterior_df), dplyr::n_distinct(posterior_df$observation_id)))

# ---- Explicit checkpoint ----------------------------------------------------
posterior_df_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_posterior_df.rds"))
saveRDS(posterior_df, posterior_df_path)
message(sprintf("  Saved: %s", posterior_df_path))
message(sprintf("  To reuse without re-computing, paste:\n    posterior_df <- readRDS(\"%s\")",
                posterior_df_path))

# ==============================================================================
# 3.  POSTERIOR CONSENSUS (LCA-based, one row per observation_id)
# ==============================================================================

message("\n--- Step 3: Computing posterior consensus ---")

consensus_df <- TaxaAssign::posterior_consensus(
  posterior_df = posterior_df,
  rank_system  = RANK_SYSTEM
)

message(sprintf("  %d consensus row(s) (one per observation_id); %d resolved.",
                nrow(consensus_df), sum(consensus_df$is_resolved, na.rm = TRUE)))

# ---- Explicit checkpoint ----------------------------------------------------
consensus_df_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_consensus_df.rds"))
saveRDS(consensus_df, consensus_df_path)
message(sprintf("  Saved: %s", consensus_df_path))
message(sprintf("  To reuse without re-computing, paste:\n    consensus_df <- readRDS(\"%s\")",
                consensus_df_path))

# ==============================================================================
# 4.  ADD SLASH TAXON (compact reporting label + irreducibility flag)
# ==============================================================================
# Session 123's addition: appends slash_taxon_name + irreducible_consensus,
# and (since consensus_taxon is present here) consensus_OTU + primary_taxon --
# the single-reporting-label columns TaxaFlag expects downstream.

message("\n--- Step 4: Adding slash taxon notation ---")

taxaassign_consensus <- TaxaAssign::add_slash_taxon(consensus_df)

message(sprintf("  %d row(s); %d irreducible consensus call(s).",
                nrow(taxaassign_consensus),
                sum(taxaassign_consensus$irreducible_consensus, na.rm = TRUE)))

# ---- Explicit checkpoint ----------------------------------------------------
taxaassign_consensus_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaassign_consensus.rds"))
saveRDS(taxaassign_consensus, taxaassign_consensus_path)
message(sprintf("  Saved: %s", taxaassign_consensus_path))
message(sprintf("  To reuse without re-running this workflow, paste:\n    taxaassign_consensus <- readRDS(\"%s\")",
                taxaassign_consensus_path))

# ==============================================================================
# 5.  VARIANT B (DOCUMENTED, NOT RUN) -- THE LLM/NO-SCORE PATHWAY
# ==============================================================================
# assign_taxa_llm() is a GENUINELY PARALLEL, INDEPENDENT pathway, not a variant
# of the Bayesian one above. IMPORTANT DESIGN FACT: it has NO taxaexpect_priors
# parameter at all. Instead of joining occurrence-based priors from TaxaExpect,
# it asks the LLM directly for range_status / habitat_fit / information_quality
# per taxon (ecological reasoning) and derives Beta(alpha, beta) priors from
# that via prior_phi -- completely bypassing everything Steps 1-2 do above.
#
# Use this pathway when no occurrence-based prior model exists at all -- e.g.
# morphological/expert-ID data, or a classifier's candidate list with no
# reference database to build a TaxaExpect model from. It still ends in the
# same compute_posterior() Bayes update internally, so its output posterior
# columns are directly compatible with posterior_consensus() + add_slash_taxon()
# below -- only the PRIOR SOURCE differs, not the downstream mechanics.
#
# Run live here (below), on its own synthetic match_df -- a genuinely
# different object shape from Variant A's `likelihoods` (0-100 score_original,
# no score_likelihood/prior columns at all; assign_taxa_llm() derives both
# likelihood AND prior internally). Reuses the same real taxa pool and
# observation ids as Variant A (.synth_taxa/.synth_genus/.synth_family/
# .obs_ids/.n_synth_taxa, all still in scope from the DEBUG_MODE block above)
# for a clean side-by-side comparison against the Bayesian pathway's result.

message("\n--- Step 5: VARIANT B -- THE LLM/NO-SCORE PATHWAY (assign_taxa_llm) ---")

# match_df here is TaxaMatch's candidate-list shape: observation_id,
# score_original (0-100 scale -- e.g. BLAST percent identity; NOT the same
# scale or column as Variant A's score_likelihood), taxon_name,
# taxon_name_rank, plus genus/family for rank_system. Required columns per
# assign_taxa_llm()'s own validation: observation_id, score_original,
# taxon_name, taxon_name_rank.
.build_match_row <- function(obs_id, taxa_idx) {
  n_cand <- length(taxa_idx)
  top_score <- stats::runif(1, 92, 99)
  if (n_cand == 1L) {
    scores <- top_score
  } else {
    # Kept above score_threshold's default (80) so all competing congeners
    # survive into the candidate set -- otherwise assign_taxa_llm() silently
    # drops any row below score_threshold before the LLM ever sees it.
    remaining <- sort(stats::runif(n_cand - 1L, 82, 90), decreasing = TRUE)
    scores <- c(top_score, remaining)
  }
  tibble::tibble(
    observation_id  = obs_id,
    taxon_name      = .synth_taxa[taxa_idx],
    taxon_name_rank = "species",
    genus           = .synth_genus[taxa_idx],
    family          = .synth_family,
    score_original  = scores
  )
}

.match_list <- lapply(seq_along(.obs_ids), function(i) {
  n_cand    <- min(sample(2:3, 1L), .n_synth_taxa)
  top_idx   <- ((i - 1L) %% .n_synth_taxa) + 1L
  other_idx <- setdiff(seq_len(.n_synth_taxa), top_idx)
  cand_idx  <- c(top_idx, head(other_idx, n_cand - 1L))
  .build_match_row(.obs_ids[i], cand_idx)
})
match_df <- dplyr::bind_rows(.match_list)

message(sprintf("  Synthetic match_df: %d observation(s), %d candidate row(s), score_original in [80,100].",
                length(.obs_ids), nrow(match_df)))
message("  *** SYNTHETIC DATA NOTICE *** -- score_original values are illustrative ",
        "placeholders, NOT real BLAST/classifier output.")

# context: one row with main_habitat, applied uniformly to every observation
# (context_group is left NULL, so .build_group_map()/.get_group_context()
# apply this single row's fields to all observations regardless of an
# observation_id column being present). Built directly from SITE_HABITAT
# (already derived from taxaexpect_priors earlier in this script) rather than
# via TaxaAssign::build_context() -- that function would re-run TaxaHabitat's
# LLM-based habitat classification on this same taxon set, for which we
# already have a real answer from the upstream chain. A real workflow with
# per-observation context (e.g. different sites) would supply context_group
# and an observation_id column on context.
context <- tibble::tibble(main_habitat = SITE_HABITAT)

# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: leaving llm_fn at its default
# (NULL) does NOT error -- it silently degrades to uniform priors. Root cause:
# assign_taxa_llm()'s internal .resolve_llm_fn() falls back to
# TaxaTools::call_api() (the generic multi-provider dispatcher, per Session 86
# of TaxaAssign/CLAUDE.md), and call_api()'s own provider auto-detection
# requires TaxaTools to have been library()-attached (its .onAttach() hook is
# what sets getOption("TaxaID.llm_fn") from detected API keys) -- see
# TaxaTools/R/call_api.R's own comment: "this means .onAttach() hasn't run
# (package loaded via :: not library())". This house style's fully-namespaced,
# never-attached calling convention (TaxaTools::..., never library(TaxaTools))
# is therefore incompatible with EVERY function's NULL-default llm_fn across
# the ecosystem (assign_taxa_llm(), run_llm_pipeline(), build_context(),
# suggest_unreferenced_species() all share .resolve_llm_fn()). Explicit
# llm_fn -- exactly the pattern already used in TaxaHabitat's
# assign_habitat_workflow.R -- avoids the auto-detection path entirely.
message("  Requires ANTHROPIC_API_KEY to actually run.")
posterior_llm <- TaxaAssign::assign_taxa_llm(
  match_df    = match_df,
  context     = context,
  rank_system = RANK_SYSTEM,
  llm_fn      = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api),
  n_sims      = 1000L
)

message(sprintf("  %d posterior row(s) computed across %d observation(s) (LLM-derived priors).",
                nrow(posterior_llm), dplyr::n_distinct(posterior_llm$observation_id)))

# ---- Explicit checkpoint ----------------------------------------------------
posterior_llm_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_posterior_llm.rds"))
saveRDS(posterior_llm, posterior_llm_path)
message(sprintf("  Saved: %s", posterior_llm_path))
message(sprintf("  To reuse without re-querying the LLM, paste:\n    posterior_llm <- readRDS(\"%s\")",
                posterior_llm_path))

taxaassign_consensus_llm <- TaxaAssign::posterior_consensus(
  posterior_df = posterior_llm,
  rank_system  = RANK_SYSTEM
) |>
  TaxaAssign::add_slash_taxon()

message(sprintf("  %d consensus row(s) (LLM pathway); %d resolved.",
                nrow(taxaassign_consensus_llm),
                sum(taxaassign_consensus_llm$is_resolved, na.rm = TRUE)))

# ---- Explicit checkpoint ----------------------------------------------------
taxaassign_consensus_llm_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaassign_consensus_llm.rds"))
saveRDS(taxaassign_consensus_llm, taxaassign_consensus_llm_path)
message(sprintf("  Saved: %s", taxaassign_consensus_llm_path))
message(sprintf("  To reuse without re-running this variant, paste:\n    taxaassign_consensus_llm <- readRDS(\"%s\")",
                taxaassign_consensus_llm_path))

# Equivalently, the high-level wrapper collapses Step 5's assign_taxa_llm() +
# posterior_consensus() + add_slash_taxon() into one call (~7 calls -> 1):
#
#   taxaassign_consensus_llm <- TaxaAssign::run_llm_pipeline(
#     match_df    = match_df,
#     context     = context,
#     rank_system = RANK_SYSTEM
#   )

message("\nWorkflow complete.")
message("Next: pass taxaassign_consensus (Bayesian pathway) or taxaassign_consensus_llm ",
        "(LLM pathway) to TaxaFlag for anomalous-detection flagging.")

# ==============================================================================
# Output
# ==============================================================================
# This workflow produces TWO consensus objects -- one per pathway, both with
# the identical column shape (posterior_consensus() + add_slash_taxon()
# output), since only the prior SOURCE differs between them, not the
# downstream mechanics:
#
#   taxaassign_consensus      -- VARIANT A (Bayesian pathway). Priors from
#                                 TaxaExpect's real occurrence model
#                                 (taxaexpect_priors). Use this as the primary/
#                                 default output when an occurrence-based
#                                 prior model exists.
#   taxaassign_consensus_llm  -- VARIANT B (LLM/no-score pathway). Priors from
#                                 the LLM's direct ecological reasoning
#                                 (assign_taxa_llm()), bypassing TaxaExpect
#                                 entirely. Use this when no occurrence-based
#                                 prior model exists (e.g. morphological/
#                                 expert-ID data, or insufficient occurrence
#                                 data to fit TaxaExpect's GLMM -- see
#                                 generate_priors_workflow.R's own fallback-
#                                 level messages for how easily that threshold
#                                 is missed on tutorial-scale real data).
#
# Both are independent, complete pipelines over the same tutorial taxa --
# compare them directly to see how prior source alone changes the consensus.
#
# Columns:
#   observation_id          -- character/any; groups competing hypotheses
#   consensus_taxon         -- character; the LCA (or single/unanimous) taxon
#   consensus_rank          -- character; rank at which consensus was reached
#   consensus_reason        -- character; "unanimous", "single", "lca", or NA
#   is_resolved             -- logical; TRUE if a consensus call was reached
#   consensus_posterior     -- numeric; summed posterior mass at consensus_taxon
#   consensus_confidence_score -- numeric; from posterior_consensus()
#   n_plausible             -- integer; size of the plausible candidate set
#   winner_prior            -- numeric; prior_mean of highest-posterior hypothesis
#   winner_likelihood       -- numeric; score_likelihood of same
#   winner_likelihood_cov   -- numeric; coverage-adjusted likelihood, when present
#   plausible_taxa          -- list column; character vector of candidate taxa
#   plausible_posteriors    -- list column; numeric vector, positionally aligned
#                               with plausible_taxa
#   slash_taxon_name        -- character; compact slash-species label (NA for
#                               singletons/unresolved); from add_slash_taxon()
#   irreducible_consensus   -- logical; TRUE when the candidate set cannot be
#                               further decomposed elsewhere in the dataset;
#                               from add_slash_taxon()
#   consensus_OTU           -- character; single reporting label -- slash_taxon_name
#                               when non-NA, else consensus_taxon; from
#                               add_slash_taxon() (Session 123)
#   primary_taxon           -- character; consensus_OTU reduced to one taxon by
#                               dropping everything after the first "/" or " + ";
#                               from add_slash_taxon() (Session 123)
#
# Consumer: TaxaFlag, which flags anomalous detections (contamination,
#   allochthonous transport, taxonomic scope, handler artifacts) using
#   consensus_OTU / primary_taxon / irreducible_consensus / winner_prior /
#   winner_likelihood as inputs.
# ==============================================================================

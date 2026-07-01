# ==============================================================================
# WORKFLOW: FLAG DETECTIONS (TaxaFlag)
# ==============================================================================
# Purpose: Flag anomalous detections in the consensus taxonomic assignment
#   output -- habitat/geographic/scope implausibility, contamination risk, and
#   a post-hoc sanity check comparing sequence-match evidence against the
#   occurrence-based prior tier -- so a human reviewer can filter or triage
#   the final call list before reporting results.
#
# Audience: someone learning TaxaFlag step by step, continuing directly from
#   TaxaAssign's compute_posteriors_workflow.R.
#
# THIS IS THE LAST PACKAGE IN THE TUTORIAL CHAIN:
#   TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign -> TaxaFlag
# There is no further downstream package -- this script's output is the
# terminal object of the whole tutorial series. See the "Output" block at the
# end of this file.
#
# UNLIKE THE PRIOR THREE SCRIPTS, NO SYNTHETIC DATA IS BUILT HERE. Both
# functions run live below (review_assignments(), add_posthoc_assessment())
# operate entirely on REAL objects already produced by the upstream chain --
# taxaassign_consensus (TaxaAssign's Bayesian-pathway output) and
# taxaexpect_priors (TaxaExpect's prior model, needed here only for its
# taxon_name + model_tier columns). Nothing needs to be fabricated: the
# consensus object already carries real plausible_taxa/winner_likelihood
# values, and taxaexpect_priors already carries the real model_tier per
# taxon. This is the first script in the series where 100% of the primary
# demonstration is real continuity data end to end.
#
# TWO FUNCTIONS RUN LIVE, ONE DOCUMENTED-ONLY:
#   STEP 1 (live) -- review_assignments(): one real LLM call reviewing the
#     irreducible candidate set (plausible_taxa / slash notation) for
#     habitat/geographic/contamination plausibility and alternatives.
#   STEP 2 (live) -- add_posthoc_assessment(): fully offline categorical
#     cross-tab of sequence-match evidence (winner_likelihood) against
#     occurrence-based prior tier (model_tier), no LLM call.
#   STEP 3 (documented, NOT run) -- flag_contaminant(): needs lab read-count
#     data (one row per sample x taxon, n_reads) that this GBIF-occurrence-
#     based tutorial chain has never produced. See Section 3 below for why.
#
# Output: taxaassign_consensus_flagged -- see "Output" block at the end of
#   this file for the full column contract. Terminal object -- nothing
#   downstream consumes it within this ecosystem.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaFlag::, TaxaTools::, dplyr::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps
# to a future function argument.

# DEBUG_MODE = TRUE  -> load TaxaAssign's real tutorial checkpoints
#                       (taxaassign_consensus + taxaexpect_priors).
# DEBUG_MODE = FALSE -> plug in your own consensus + tiers objects (see the
#                       "SWAP IN YOUR OWN DATA" block below)
DEBUG_MODE <- TRUE

# taxa_per_call for review_assignments(): kept at the package default (15) --
# this tutorial's consensus object is small, so a single LLM call almost
# certainly covers every row regardless.
TAXA_PER_CALL <- 15L

# likelihood_threshold for add_posthoc_assessment(): package default (0.5) --
# see ?TaxaFlag::add_posthoc_assessment for the sequence-supported cutoff.
LIKELIHOOD_THRESHOLD <- 0.5

if (DEBUG_MODE) {

  # ---- Tutorial example: continue from TaxaAssign's Gadus checkpoint --------
  # These are the exact readRDS() lines documented in
  # compute_posteriors_workflow.R's Output block (taxaassign_consensus) and
  # generate_priors_workflow.R's Output block (taxaexpect_priors, still
  # available upstream -- TaxaAssign's script only read it in, it never
  # overwrote it). Unlike TaxaExpect's own DEBUG_MODE fallback, there is no
  # sensible "build something synthetic" fallback here -- the entire point of
  # this script is to flag REAL consensus calls; a synthetic consensus object
  # would have nothing genuine to say about habitat/geography/contamination
  # plausibility.
  .consensus_checkpoint <- file.path(tempdir(), "tutorial_gadus_taxaassign_consensus.rds")
  .priors_checkpoint    <- file.path(tempdir(), "tutorial_gadus_taxaexpect_priors.rds")

  if (!file.exists(.consensus_checkpoint)) {
    stop("DEBUG_MODE = TRUE but TaxaAssign's checkpoint was not found at ",
         .consensus_checkpoint, ". Run TaxaAssign's compute_posteriors_workflow.R ",
         "first -- this script has nothing meaningful to flag without real ",
         "taxaassign_consensus output.")
  }
  if (!file.exists(.priors_checkpoint)) {
    stop("DEBUG_MODE = TRUE but TaxaExpect's checkpoint was not found at ",
         .priors_checkpoint, ". Run TaxaExpect's generate_priors_workflow.R ",
         "first -- add_posthoc_assessment() requires the real taxaexpect_priors ",
         "tiers object (taxon_name + model_tier).")
  }

  taxaassign_consensus <- readRDS(.consensus_checkpoint)
  message("DEBUG_MODE = TRUE -- loaded TaxaAssign's checkpoint: ", .consensus_checkpoint,
          " (", nrow(taxaassign_consensus), " consensus row(s)).")

  taxaexpect_priors <- readRDS(.priors_checkpoint)
  message("DEBUG_MODE = TRUE -- loaded TaxaExpect's checkpoint: ", .priors_checkpoint,
          " (", nrow(taxaexpect_priors), " prior row(s)).")

  # ---- Derive SITE_HABITAT FROM taxaexpect_priors ----------------------------
  # taxaexpect_priors is already filtered to one focal grid_id/habitat by
  # TaxaExpect's Step 9 -- do not hardcode this value. Same derivation
  # TaxaAssign's own script used; re-derived here rather than assumed, since a
  # live run's actual habitat could differ from any previous tutorial run.
  SITE_HABITAT <- unique(stats::na.omit(taxaexpect_priors$main_habitat))

  if (length(SITE_HABITAT) != 1L) {
    stop("Expected exactly one main_habitat in taxaexpect_priors (single-site ",
         "by construction from generate_priors_workflow.R), but found ",
         length(SITE_HABITAT), ": ", paste(SITE_HABITAT, collapse = ", "),
         ". Check the upstream TaxaExpect checkpoint.")
  }
  message(sprintf("  SITE_HABITAT = \"%s\" (derived from taxaexpect_priors).",
                  SITE_HABITAT))

  # ---- Build `context` for review_assignments() -- simple named list --------
  # habitat: the real SITE_HABITAT value derived above, never hardcoded.
  # geography: HONESTY CAVEAT -- this tutorial chain never geocoded its GBIF
  # search box (a lat/lon bounding box or WKT polygon; see TaxaFetch's
  # make_bbox_wkt()/define_search_polygon()) to a named place. Inventing a
  # specific place name here (e.g. "North Atlantic" or "Gulf of Maine") would
  # misrepresent it as an authoritative geocoded result when it is not. State
  # plainly that it is an approximate, non-geocoded placeholder so a reader
  # knows to replace it with a real place name (or the search bbox/polygon
  # itself) in their own workflow.
  context <- list(
    geography = "approximate -- not re-derived from real geocoding in this tutorial chain; replace with the actual sampling region name or search bbox/polygon",
    habitat   = SITE_HABITAT
  )
  message("  context$habitat = real SITE_HABITAT; context$geography is an ",
          "HONEST PLACEHOLDER (see comment above) -- this tutorial never ",
          "geocoded its GBIF search box to a named place.")

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your real consensus + tiers objects:
  #
  #   taxaassign_consensus <- readRDS("path/to/your_taxaassign_consensus.rds")
  #     (the object produced by TaxaAssign's compute_posteriors_workflow.R --
  #     either taxaassign_consensus (Bayesian pathway) or
  #     taxaassign_consensus_llm (LLM pathway); both share the identical
  #     column shape, so either works unchanged below)
  #
  #   taxaexpect_priors <- readRDS("path/to/your_taxaexpect_priors.rds")
  #     (the object produced by TaxaExpect's generate_priors_workflow.R;
  #     only taxon_name + model_tier are required by add_posthoc_assessment())
  #
  #   SITE_HABITAT <- unique(na.omit(taxaexpect_priors$main_habitat))
  #     (or your own site resolution)
  #
  #   context <- list(
  #     geography = "your real sampling region name or search bbox/polygon",
  #     habitat   = SITE_HABITAT
  #   )
  #     (or a build_context() data frame with ecoregion + main_habitat columns
  #     -- review_assignments() accepts either shape; see .normalise_context())
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real taxaassign_consensus/taxaexpect_priors ",
       "objects have been supplied. Edit the 'SWAP IN YOUR OWN DATA' block in ",
       "this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_gadus"

# ==============================================================================
# 1.  REVIEW ASSIGNMENTS -- LLM EXPERT REVIEW (LIVE)
# ==============================================================================
# One real LLM call per taxa_per_call-sized chunk of observations. Reviews the
# IRREDUCIBLE CANDIDATE SET (plausible_taxa / slash notation) rather than just
# consensus_taxon -- irreducible_only = TRUE (the default) tells
# review_assignments() to present the LLM with the full plausible-taxa list
# for observations whose candidate set cannot be decomposed further elsewhere
# in the dataset, so the LLM's alternatives/lower-hypotheses reasoning has the
# real competing-hypothesis context TaxaAssign already computed, not just a
# single winner.
#
# target_group = NULL (omitted): this tutorial isn't scoped to one target
# taxonomic group in any meaningful way (it's a generic Gadidae/marine-fish
# demo, not e.g. "birds only" or "fish only" eDNA survey), so scope_plausibility
# would have nothing informative to compare against and is skipped.
#
# marker = NULL (omitted): no marker metadata (e.g. "12S"/"18S") has been
# threaded through this tutorial chain to pass along here.
#
# llm_fn: SAME FOOTGUN AS TaxaAssign's script -- review_assignments()'s own
# default resolves to TaxaTools::call_api(), the generic multi-provider
# dispatcher, whose provider auto-detection depends on TaxaTools having been
# library()-attached (.onAttach() sets getOption("TaxaID.llm_fn") from
# detected API keys). This house style's fully-namespaced, never-attached
# calling convention (TaxaTools::..., never library(TaxaTools)) means that
# auto-detection path never fires, and call_api() SILENTLY degrades rather
# than erroring. Pass llm_fn explicitly, exactly as TaxaHabitat's and
# TaxaAssign's scripts already do.
# ==============================================================================

message("\n--- Step 1: Reviewing assignments (LLM expert review) ---")
message("  Requires ANTHROPIC_API_KEY (or getOption(\"TaxaID.llm_fn\")) to actually run.")
message(sprintf("  Reviewing %d consensus row(s) from taxaassign_consensus (Bayesian pathway).",
                nrow(taxaassign_consensus)))
message("  NOTE: the same call applies equally to taxaassign_consensus_llm (the LLM ",
        "pathway's consensus object) -- only one pathway is demonstrated here since one ",
        "live run is enough for a tutorial; both share the identical column shape.")

# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: irreducible_only = TRUE hard-
# filters to rows where irreducible_consensus is TRUE and errors outright
# ("No candidate sets to review") if none exist (R/review_assignments.R).
# TaxaAssign's synthetic tutorial data draws from only ~4 species across 3
# tiny observations, so candidate sets very often overlap across observations
# -- making non-irreducible the EXPECTED outcome for this small a pool, not
# bad luck. A real dataset with many more species/observations would not hit
# this as readily. Check before committing to irreducible_only = TRUE; fall
# back to reviewing every row (irreducible_only = FALSE) when none qualify,
# rather than letting the tutorial hard-stop on a data-volume artifact.
.n_irreducible <- sum(taxaassign_consensus$irreducible_consensus, na.rm = TRUE)
.use_irreducible_only <- .n_irreducible > 0L

if (!.use_irreducible_only) {
  message(sprintf(
    "  0 of %d rows have irreducible_consensus == TRUE -- with this tutorial's ",
    nrow(taxaassign_consensus)
  ), "small synthetic species pool (~4 species across 3 observations), ",
  "candidate sets routinely overlap across observations, so this is expected, ",
  "not a bug. Falling back to irreducible_only = FALSE (review every row's ",
  "consensus_taxon/plausible_taxa regardless of irreducibility).")
}

taxaassign_consensus_reviewed <- TaxaFlag::review_assignments(
  df                 = taxaassign_consensus,
  taxon_col          = "consensus_taxon",
  plausible_taxa_col = "plausible_taxa",
  irreducible_only   = .use_irreducible_only,
  context            = context,
  target_group       = NULL,
  data_type          = "eDNA",
  llm_fn             = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api),
  taxa_per_call      = TAXA_PER_CALL
)

message(sprintf("  %d row(s) reviewed; %d flagged with contamination_risk == \"high\".",
                nrow(taxaassign_consensus_reviewed),
                sum(taxaassign_consensus_reviewed$contamination_risk == "high", na.rm = TRUE)))

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so a future session can skip Step 1 by pasting the readRDS() line
# below -- no file.exists()-gated auto-reload; you decide when to reuse this.
taxaassign_consensus_reviewed_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaassign_consensus_reviewed.rds"))
saveRDS(taxaassign_consensus_reviewed, taxaassign_consensus_reviewed_path)
message(sprintf("  Saved: %s", taxaassign_consensus_reviewed_path))
message(sprintf("  To reuse without re-querying the LLM, paste:\n    taxaassign_consensus_reviewed <- readRDS(\"%s\")",
                taxaassign_consensus_reviewed_path))

# ==============================================================================
# 2.  ADD POST-HOC ASSESSMENT -- SEQUENCE EVIDENCE x PRIOR TIER (LIVE, OFFLINE)
# ==============================================================================
# Fully offline categorical cross-tab: combines winner_likelihood (sequence-
# match support for the winning hypothesis, already on taxaassign_consensus
# from TaxaAssign's posterior_consensus()) against model_tier (the occurrence-
# based prior tier for that taxon, already on taxaexpect_priors) into one of
# seven categories (sensible / limited_evidence / unexpected / unprecedented /
# suspect / vague_rank / modeled).
#
# tiers = taxaexpect_priors DIRECTLY -- no synthetic data needed. Per
# add_posthoc_assessment()'s own source, `tiers` only requires taxon_name +
# model_tier, and taxaexpect_priors already has both real columns from
# TaxaExpect's checkpoint. Runs on taxaassign_consensus_reviewed (Step 1's
# output) so the final object carries both LLM review columns and the
# post-hoc assessment column together.
# ==============================================================================

message("\n--- Step 2: Adding post-hoc assessment (sequence evidence x prior tier) ---")

taxaassign_consensus_flagged <- TaxaFlag::add_posthoc_assessment(
  consensus_df          = taxaassign_consensus_reviewed,
  tiers                 = taxaexpect_priors,
  winner_likelihood_col = "winner_likelihood",
  consensus_taxon_col   = "consensus_taxon",
  consensus_rank_col    = "consensus_rank",
  taxon_col             = "taxon_name",
  tier_col              = "model_tier",
  likelihood_threshold  = LIKELIHOOD_THRESHOLD,
  finest_rank           = "species"
)

message("  posthoc_assessment distribution:")
print(table(taxaassign_consensus_flagged$posthoc_assessment, useNA = "ifany"))

# ---- Explicit checkpoint ----------------------------------------------------
taxaassign_consensus_flagged_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaassign_consensus_flagged.rds"))
saveRDS(taxaassign_consensus_flagged, taxaassign_consensus_flagged_path)
message(sprintf("  Saved: %s", taxaassign_consensus_flagged_path))
message(sprintf("  To reuse without re-running this workflow, paste:\n    taxaassign_consensus_flagged <- readRDS(\"%s\")",
                taxaassign_consensus_flagged_path))

# ==============================================================================
# 3.  FLAG CONTAMINANT (DOCUMENTED, NOT RUN)
# ==============================================================================
# flag_contaminant() compares read-count PROPORTIONS between field samples and
# control samples (extraction blanks, PCR blanks, positive controls) to score
# each taxon's likelihood of being a lab/field contaminant rather than a
# genuine detection.
#
# WHY THIS IS NOT RUN HERE: flag_contaminant() operates on LONG-FORMAT
# read-count data -- one row per sample x taxon, with a numeric n_reads
# column -- which nothing in this eDNA-OCCURRENCE tutorial chain has ever
# produced. TaxaFetch/TaxaHabitat/TaxaExpect/TaxaAssign's scripts all operate
# on GBIF OCCURRENCE records (presence data with lat/lon, not lab sequencing
# output), so there are no samples, no blanks, and no read counts anywhere
# upstream to draw from. Unlike the synthetic likelihood/match objects built
# in TaxaAssign's own script (which reused REAL species names already present
# in taxaexpect_priors for genuine continuity), a synthetic contamination
# scenario here would have zero connection to anything real in this chain --
# fabricated sample IDs, fabricated blanks, fabricated read counts -- and
# would just be noise, not a meaningful demonstration. This mirrors the
# sampling_group TODO documented but not built in TaxaFetch's own workflow.
#
# Signature (verified from R/flag_contaminant.R):
#
#   flag_contaminant(df,
#                     event_col        = "event_id",
#                     taxon_col        = "taxon_name",
#                     reads_col        = "n_reads",
#                     control_samples  = NULL,
#                     sample_type_col  = NULL,
#                     control_types    = NULL,
#                     exclude_samples  = NULL,
#                     contaminant_type = "lab_contaminant",
#                     score_thresholds = c(0.5, 0.9),
#                     verbose          = TRUE)
#
# `df` must be LONG-FORMAT: one row per sample (L1 collection event) x taxon,
# with a numeric `reads_col` (default "n_reads"). `event_col` identifies the
# L1 collection event; `control_samples` (or `sample_type_col` +
# `control_types`) identifies which events are blanks/controls versus field
# samples. `contaminant_type` controls the output column PREFIX (e.g.
# "lab_contaminant", "field_contaminant", "positive_control") -- see the Flag
# Column Convention below.
#
# Algorithm (.compute_contaminant_scores(), one row per taxon in the output):
#   1. Within-sample proportions: prop = n_reads / sum(n_reads) per sample
#   2. Per taxon: mean_prop_field, mean_prop_control, n_controls_present
#   3. Score: mean_prop_field / (mean_prop_field + mean_prop_control) in [0, 1]
#   4. Taxa absent from controls entirely -> score = 1.0 (no evidence of
#      contamination)
#
# FLAG COLUMN CONVENTION (the counterintuitive score/risk asymmetry -- see
# TaxaFlag/CLAUDE.md's "Flag Column Convention" section): flag_contaminant()
# adds a triplet of columns named from `contaminant_type`:
#   {contaminant_type}_risk   -- character: "high" (probable artifact) /
#                                 "moderate" (uncertain) / "low" (likely
#                                 genuine), gated by score_thresholds
#   {contaminant_type}_score  -- numeric in [0, 1]; HIGHER = MORE LIKELY
#                                 GENUINE (i.e. score is the inverse sense of
#                                 risk -- score 1.0 means low risk/real
#                                 detection, score 0.0 means high risk/
#                                 contaminant). This is intentional: score is
#                                 an intermediate, threshold-tunable output;
#                                 risk is the user-facing categorical result,
#                                 and the two are NOT the same direction.
#   {contaminant_type}_reason -- character; plain-English explanation (e.g.
#                                 mean_prop_field/mean_prop_control values,
#                                 or "absent from controls")
#
# Would-be example call, if this chain produced real read-count data:
#
#   read_counts_long <- readRDS("path/to/your_long_format_read_counts.rds")
#   # columns: event_id, taxon_name, n_reads, sample_type ("field"/"blank"/...)
#
#   taxaassign_consensus_flagged <- TaxaFlag::flag_contaminant(
#     df               = read_counts_long,
#     event_col        = "event_id",
#     taxon_col        = "taxon_name",
#     reads_col        = "n_reads",
#     sample_type_col  = "sample_type",
#     control_types    = c("extraction_blank", "pcr_blank"),
#     contaminant_type = "lab_contaminant",
#     score_thresholds = c(0.5, 0.9)
#   )
#   # then dplyr::left_join() the per-taxon lab_contaminant_risk/_score/_reason
#   # columns back onto taxaassign_consensus_flagged by taxon_name.
#
# Not run in this script -- see explanation above.

message("\n--- Step 3: flag_contaminant() -- DOCUMENTED ONLY, NOT RUN (see comment block above) ---")
message("  Requires lab read-count data (long-format: event_id x taxon_name x n_reads, ",
        "with control/blank samples identified) that this GBIF-occurrence-based tutorial ",
        "chain does not produce. See Section 3's comment block for the full signature, ",
        "algorithm, and Flag Column Convention.")

message("\nWorkflow complete.")
message("taxaassign_consensus_flagged is the TERMINAL object of the TaxaID tutorial chain ",
        "(TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign -> TaxaFlag). ",
        "Filter on contamination_risk / habitat_plausibility / geographic_plausibility / ",
        "posthoc_assessment for a human-reviewed final call list.")

# ==============================================================================
# Output
# ==============================================================================
# TaxaFlag is the FINAL package in the TaxaID ecosystem's dependency chain:
#   TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign -> TaxaFlag
# taxaassign_consensus_flagged is therefore the TERMINAL OBJECT of this
# tutorial series -- there is no further downstream package within this
# ecosystem to hand it to. It is meant to be read, filtered, and acted upon
# by a human reviewer (or exported for reporting), not consumed by more code.
#
# taxaassign_consensus_flagged is taxaassign_consensus (see
# compute_posteriors_workflow.R's Output block for the full base column set)
# plus the following appended columns:
#
# From review_assignments() (Step 1):
#   habitat_plausibility     -- character; "likely"/"possible"/"unlikely" --
#                               does this taxon live in this habitat?
#   geographic_plausibility  -- character; "likely"/"possible"/"unlikely" --
#                               is this taxon found in this region? (NOTE:
#                               reviewed against the honest-placeholder
#                               `context$geography` string in this tutorial --
#                               re-run with a real geocoded place name for a
#                               meaningful answer)
#   contamination_risk       -- character; "low"/"moderate"/"high" -- common
#                               lab/field contaminant? (higher = more risk)
#   review_alternatives       -- character; comma-separated plausible
#                               alternatives at the same rank, when the
#                               reviewed taxon/candidate set is implausible
#   review_lower_hypotheses  -- character; comma-separated finer-rank taxa
#                               expected here, when consensus is coarse-ranked
#                               (suppressed for irreducible-candidate-set rows
#                               per irreducible_only = TRUE)
#   review_confidence        -- character; "high"/"moderate"/"low" -- LLM's
#                               overall confidence in this review
#   review_comment           -- character; free text; anything the structured
#                               fields above don't capture
#   (scope_plausibility is ABSENT here -- target_group was NULL, since this
#   tutorial isn't scoped to one target taxonomic group)
#
# From add_posthoc_assessment() (Step 2):
#   posthoc_assessment -- character; one of "sensible", "limited_evidence",
#                         "unexpected", "unprecedented", "suspect",
#                         "vague_rank", "modeled" -- cross-tabulates
#                         winner_likelihood (sequence-match support) against
#                         model_tier (occurrence-based prior tier) from
#                         taxaexpect_priors
#
# NOT added in this run (flag_contaminant() documented but not executed --
# see Section 3): {contaminant_type}_risk / {contaminant_type}_score /
# {contaminant_type}_reason. Add these via a separate left_join() once real
# lab read-count data is available.
#
# Consumer: none within the TaxaID ecosystem -- this is the terminal object
#   of the tutorial series. Intended for human review/filtering (e.g.
#   dplyr::filter(contamination_risk != "high", posthoc_assessment != "suspect"))
#   or export for reporting/manuscript figures.
# ==============================================================================

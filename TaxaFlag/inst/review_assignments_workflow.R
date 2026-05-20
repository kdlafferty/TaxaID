# =============================================================================
# TaxaFlag — LLM Review of Taxonomic Assignments Workflow
# =============================================================================
# Reviews a consensus table (or any taxon list) using an LLM to assess
# habitat fit, geographic plausibility, contaminant risk, and alternatives.
#
# Works with any data frame containing a taxon column — not restricted to
# TaxaAssign output.

library(TaxaFlag)

# --- 1. Create or load a consensus table -------------------------------------
# This can come from TaxaAssign (posterior_consensus or score_consensus),
# or be any data frame with a taxon column.

# Example: Palmyra Atoll eDNA study
consensus_df <- data.frame(
  observation_id       = c("S1", "S1", "S1", "S2", "S2", "S2", "S3", "S3"),
  consensus_taxon = c(
    "Carcharhinus melanopterus",  # blacktip reef shark — expected
    "Homo sapiens",               # human — contaminant
    "Gobiidae",                   # goby family — expected but coarse
    "Salmo salar",                # Atlantic salmon — wrong ocean
    "Lutjanus bohar",             # red snapper — expected
    "Bos taurus",                 # cattle — food contaminant
    "Acanthurus triostegus",      # convict tang — expected
    "Eucyclogobius newberryi"     # tidewater goby — California endemic
  ),
  consensus_rank = c("species", "species", "family", "species",
                     "species", "species", "species", "species"),
  stringsAsFactors = FALSE
)

# --- 2. Define study context -------------------------------------------------
# Simple named list with geography and habitat. This tells the LLM where
# and what kind of environment the samples came from.

context <- list(
  geography = "Palmyra Atoll, central Pacific Ocean",
  habitat   = "coral reef lagoon"
)

# Alternative: use build_context() from TaxaAssign if available
# context <- TaxaAssign::build_context(taxa = unique(consensus_df$consensus_taxon),
#                                       llm_fn = TaxaTools::call_anthropic_api)

# --- 3. Run LLM review ------------------------------------------------------
# The function extracts unique taxa, batches them, and sends to the LLM.
# It returns the input data frame with 8 review columns appended.

reviewed <- review_assignments(
  df             = consensus_df,
  taxon_col      = "consensus_taxon",
  taxon_rank_col = "consensus_rank",   # enables review_lower_hypotheses
  context        = context,
  target_group   = "fish",             # enables review_scope
  marker         = "12S MiFish"        # contaminant context
)

# --- 4. Inspect results ------------------------------------------------------

# Overview
reviewed[, c("consensus_taxon", "review_habitat", "review_geography",
             "review_contaminant", "review_confidence")]

# Likely contaminants
reviewed[reviewed$review_contaminant %in% c("likely", "possible"),
         c("consensus_taxon", "review_contaminant", "review_comment")]

# Out-of-scope taxa
reviewed[reviewed$review_scope == "out_of_scope",
         c("consensus_taxon", "review_scope", "review_comment")]

# Geographically implausible + suggested alternatives
reviewed[reviewed$review_geography == "unlikely",
         c("consensus_taxon", "review_geography", "review_alternatives")]

# Lower-rank hypotheses for coarse assignments
reviewed[!is.na(reviewed$review_lower_hypotheses),
         c("consensus_taxon", "consensus_rank", "review_lower_hypotheses")]

# --- 5. Combine with data-driven flags (optional) ----------------------------
# If you also ran flag_contaminant(), you can compare the two approaches

# lab_flags <- flag_contaminant(reads_long, control_samples = ..., ...)
# comparison <- merge(
#   lab_flags[, c("taxon_name", "flag_lab_contaminant", "flag_lab_contaminant_score")],
#   unique(reviewed[, c("consensus_taxon", "review_contaminant")]),
#   by.x = "taxon_name", by.y = "consensus_taxon",
#   all = TRUE
# )
# comparison  # Compare data-driven vs LLM contaminant assessments

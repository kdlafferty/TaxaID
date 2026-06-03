# ==============================================================================
# WORKFLOW 5: AUDIT REFERENCE DATABASE COVERAGE
# ==============================================================================
# Purpose: Determine which species are missing from your reference database
#   ("unreferenced" species) and use this information to constrain likelihoods.
#
# Why it matters:
#   When a query sequence comes from a species NOT in your reference, the model
#   assigns it to the H2 (unreferenced species) or H3 (unreferenced genus)
#   hypothesis. But for genera where ALL species are already in the reference,
#   the H2 hypothesis is implausible and should be suppressed.
#
# Two audit tools:
#   A. audit_barcode_coverage() -- for DNA barcoding / eDNA (most common)
#      Checks whether each species has a barcode sequence at NCBI for your marker.
#      A species with no barcode sequence can NEVER appear as a reference match,
#      regardless of what database you use.
#
#   B. audit_reference_coverage() -- for non-barcode libraries (images, sounds)
#      Checks NCBI taxonomy to see how many described species exist per genus.
#      Simpler but less precise (doesn't check whether sequences exist).
#
# Input: reference_df (from Workflow 1) or match_df (from TaxaMatch)
#        + likelihoods (from Workflow 4, for applying constraints)
# Output: Census of reference completeness + constrained likelihoods
#
# Requires: internet access (NCBI API)
# ==============================================================================

library(TaxaLikely)

# ---- 1. Load inputs ----------------------------------------------------------
# We need genus + species columns from the reference.
# Can use reference_df, or extract from the match object.
reference_df <- readRDS("reference_df.rds")

# Deduplicate to one row per species
ref_species <- reference_df[!duplicated(reference_df$species),
                            c("genus", "species")]
cat("Reference species:", nrow(ref_species), "across",
    length(unique(ref_species$genus)), "genera\n")

# ==============================================================================
# PATH A: BARCODE COVERAGE (eDNA / DNA barcoding)
# ==============================================================================
# For each genus in the reference, audit_barcode_coverage():
#   1. Gets all described species from NCBI taxonomy
#   2. Skips species already in the reference (they have sequences by definition)
#   3. Queries NCBI nucleotide for each remaining species:
#      count = 0 -> unreferenced (no barcode sequence exists)
#      count > 0 -> has sequences but absent from your reference
#
# This can be slow for species-rich genera. Consider using cache_dir in
# Workflow 1 and running this on a subset first.

coverage <- audit_barcode_coverage(
  match_df     = ref_species,
  barcode_term = "12S",          # your marker: "COI", "ITS2", etc.
  target_rank  = "genus"
  # max_date    = "2024/12/31",  # match GenBank state when reference was built
  # min_len     = NULL,          # auto-resolved from barcode_term
  # max_len     = NULL,
  # species_list = my_external_species_list,  # optional: FishBase, WoRMS, etc.
  # ncbi_api_key = Sys.getenv("ENTREZ_KEY")
)

# ---- 2. Inspect census results -----------------------------------------------
cat("\nCoverage census:\n")
print(coverage$census)

# Census columns:
#   group             - genus name
#   total             - described species in this genus (NCBI + species_list)
#   in_reference      - species in your reference (skip-list)
#   has_seqs_not_in_ref - have barcode sequences but absent from your reference
#   unreferenced      - no barcode sequence found (true unreferenced species)
#   is_complete       - TRUE when both gaps are zero

# Which genera are fully sampled?
complete <- coverage$census[coverage$census$is_complete, ]
cat("\nFully sampled genera:", nrow(complete), "\n")
if (nrow(complete) > 0) print(complete$group)

# Which genera have the most unreferenced species?
if ("unreferenced" %in% names(coverage$census)) {
  cat("\nGenera with most unreferenced species:\n")
  print(coverage$census[order(-coverage$census$unreferenced), ][1:10, ])
}

# ---- 3. View unreferenced species list ---------------------------------------
cat("\nUnreferenced species (no barcode sequence):\n")
print(coverage$unreferenced)
cat("Total unreferenced:", length(coverage$unreferenced), "\n")

# ---- 4. Apply coverage constraints to likelihoods ----------------------------
# For fully sampled genera, H2 (unreferenced_species) hypotheses are
# implausible and should be suppressed. apply_coverage_constraints() sets
# their likelihoods to zero.

likelihoods <- readRDS("likelihoods.rds")

# Reshape census for apply_coverage_constraints()
census_result <- data.frame(
  taxon_name = coverage$census$group,
  rank       = "genus",
  status     = ifelse(coverage$census$is_complete, "complete", "incomplete"),
  stringsAsFactors = FALSE
)

constrained <- apply_coverage_constraints(likelihoods, census_result)

# How many H2 rows were suppressed?
n_suppressed <- sum(
  constrained$hypothesis_type == "unreferenced_species" &
  constrained$score_likelihood == 0,
  na.rm = TRUE
)
cat("\nH2 rows suppressed (complete genera):", n_suppressed, "\n")

saveRDS(constrained, "likelihoods_constrained.rds")


# ==============================================================================
# PATH B: REFERENCE COVERAGE (non-barcode: images, sounds)
# ==============================================================================
# Simpler audit: counts described species per genus from NCBI taxonomy.
# Does not check whether sequences or reference material exists --
# just whether the species is described.
#
# Use this for image-based or acoustic identification where barcode
# availability is irrelevant.

# coverage_b <- audit_reference_coverage(
#   reference_df = ref_species,
#   target_rank  = "genus"
#   # ncbi_api_key = Sys.getenv("ENTREZ_KEY")
# )
#
# print(coverage_b$census)
# print(coverage_b$unreferenced)

message("\nWorkflow 5 complete.")
message("Constrained likelihoods saved. Next: TaxaAssign for posterior assignment.")


# ==============================================================================
# PATH C: ACOUSTIC / IMAGE COVERAGE (classifier-based data)
# ==============================================================================
# Use when your detections come from a fixed-species classifier (BirdNET,
# camera-trap model) rather than DNA barcoding.
#
# audit_acoustic_coverage() answers: which plausible species at your site
# are ABSENT from the classifier's known species list? These cannot appear
# as candidates regardless of how common they are — they are unreferenced
# in the acoustic/image sense.
#
# No internet access required (pure set-membership check).
#
# Inputs:
#   plausible_species  -- species expected at your site (LLM / GBIF / expert list)
#   reference_species  -- classifier's known species list (BirdNET, custom model)
#   match_df           -- (optional) classifier output; annotates census with
#                         in_match_data = TRUE for species that actually appeared

# ---- C1. Supply your plausible species and classifier species list -----------
# plausible_species: species expected at this site, from TaxaExpect or expert list
plausible_species <- c(
  "Turdus migratorius",
  "Setophaga petechia",
  "Limosa fedoa",
  "Selasphorus calliope"
  # ... add your site-specific species list
)

# reference_species: the classifier's built-in known species list
# For BirdNET: read from the BirdNET_GLOBAL_6K_V2.4_Labels.txt file
# reference_species <- readLines("BirdNET_GLOBAL_6K_V2.4_Labels.txt")
reference_species <- c(
  "Turdus migratorius",
  "Setophaga petechia",
  "Turdus merula",
  "Corvus brachyrhynchos"
  # ... your classifier's full species list
)

# ---- C2. Run acoustic coverage audit ----------------------------------------
coverage_c <- audit_acoustic_coverage(
  plausible_species = plausible_species,
  reference_species = reference_species
  # match_df = birdnet_match_df   # optional: annotate with in_match_data
)

cat("\nAcoustic coverage census:\n")
print(coverage_c$census)

cat("\nUnreferenced species (absent from classifier):\n")
print(coverage_c$unreferenced)
cat("Total unreferenced:", length(coverage_c$unreferenced), "\n")

# ---- C3. (Optional) Load match data and annotate census with detections ------
# If you have classifier output loaded, pass it to annotate the census with
# which unreferenced species actually appeared as detections:
#
# birdnet_match_df <- TaxaMatch::read_birdnet_output("BirdNET_results/")
# coverage_c_annotated <- audit_acoustic_coverage(
#   plausible_species = plausible_species,
#   reference_species = reference_species,
#   match_df          = birdnet_match_df
# )
# print(coverage_c_annotated$census)

# ---- C4. Pass unreferenced species to TaxaAssign ----------------------------
# Acoustic data uses unreferenced_candidates() + assign_scores() for
# likelihoods (see Workflow 6). The unreferenced species list from this audit
# informs suggest_unreferenced_species() in TaxaAssign, which builds additional
# H2 hypotheses for species that cannot appear as classifier candidates.
#
# unreferenced_result <- TaxaAssign::suggest_unreferenced_species(
#   match_df          = birdnet_match_df,
#   unreferenced_taxa = coverage_c$unreferenced
# )

message("\nWorkflow 5C complete.")
message("Next: Workflow 6 (no-score pathway) for acoustic likelihoods, then TaxaAssign.")

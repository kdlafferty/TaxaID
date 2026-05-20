# ==============================================================================
# TaxaMatch — workflow_standardize.R
# Test workflow for standardize_match_data()
# ==============================================================================
# Run this from the TaxaMatch project after devtools::load_all() or
# devtools::install() + library(TaxaMatch).
# ==============================================================================

library(TaxaMatch)
#estuarine fishes 12S: JVB1846-MiFishU-esv-data.csv
#California intertidal fishes 12S:JVB2844-MiFishU-esv-data
#Palmyra fishes (big) 12S: JVB1950-MiFishU-esv-data
#Palmyra COI: Palmyra2019-UniCOI-esv-data
# ------------------------------------------------------------------------------
# Option A: Load from file interactively (opens file chooser)
# Use the MiFish eDNA file:
#   (your local data directory)
#     e.g., JVB1846-MiFishU-esv-data.csv
# ------------------------------------------------------------------------------

match_obj <- standardize_match_data(
  data            = NULL,        # opens file.choose()
  observation_id_col   = "ESVId",
  score_col       = "PercMatch",
  # rank_system = NULL        # auto-detected from Kingdom...Species columns
  lowercase_names = TRUE         # default: all col names → lowercase
)|>
  dplyr::mutate(taxon_name = TaxaTools::clean_taxon_names(taxon_name))#get rid of subspecies, authors, etc.

#smaller dataset for testing workflows.
#match_obj<-match_obj|>dplyr::filter(family=="Cottidae")

# ------------------------------------------------------------------------------
# Option B: Supply the file path directly (non-interactive)
# ------------------------------------------------------------------------------

# match_obj <- standardize_match_data(
#   data = file.choose(),  # select your match data CSV
#   observation_id_col = "ESVId",
#   score_col     = "PercMatch"
# )

# ------------------------------------------------------------------------------
# Inspect the result
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# What if your file uses non-standard column names?
# Example: score column is called "identity" instead of "PercMatch"
# ------------------------------------------------------------------------------

# match_obj2 <- standardize_match_data(
#   data          = my_df,
#   observation_id_col = "query_id",
#   score_col     = "identity"
# )

# ------------------------------------------------------------------------------
# What if taxonomy columns have non-standard names?
# Supply rank_system explicitly:
# ------------------------------------------------------------------------------

# match_obj3 <- standardize_match_data(
#   data           = my_df,
#   observation_id_col  = "ESVId",
#   score_col      = "PercMatch",
#   rank_system = c("phylum", "class_name", "family_name", "genus_name", "species_name")
# )

# ------------------------------------------------------------------------------
# Filter redundant higher-rank hypotheses
# ------------------------------------------------------------------------------
# When the match pipeline returns both a species-level row (Gobius paganellus)
# and a genus-level row (Gobius) for the same sample, the genus row is
# redundant. filter_redundant_hypotheses() removes coarser-rank rows that are
# superseded by finer-rank rows within the same lineage and observation_id.
# Genus rows for lineages that have NO species-level match are retained.
#
# Call AFTER standardize_match_data() so taxon_name_rank is already populated.

cat("Rows before filtering redundant hypotheses:", nrow(match_obj), "\n")

match_obj <- filter_redundant_hypotheses(match_obj)

cat("Rows after filtering redundant hypotheses: ", nrow(match_obj), "\n")

# Rank breakdown after filtering
print(table(match_obj$taxon_name_rank, useNA = "ifany"))

# ------------------------------------------------------------------------------
# Save match object for use in TaxaLikely
# ------------------------------------------------------------------------------
# Saved to inst/ so it stays with the package source and is easy to find.
# Path is relative to the TaxaMatch project root.

saveRDS(match_obj, file = "inst/match_obj.rds")
cat("Saved: inst/match_obj.rds\n")

# To load in TaxaLikely workflow_example.R:
#   match_obj <- readRDS("path/to/TaxaMatch/inst/match_obj.rds")

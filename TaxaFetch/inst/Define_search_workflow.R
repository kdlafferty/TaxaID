# =============================================================================
# use this TaxaFetch search workflow to define the taxonomic groups and backbone
# for which to search GBIF.
#
# =============================================================================
#
# INPUT:  TaxaMatch output -- a dataframe of taxa identified from a sample,
#         with NCBI backbone ranks and likelihood estimates.
#
# OUTPUT: A list of taxa in the GBIF backbone to search for
#
# BACKBONE FLOW:
#   TaxaMatch (NCBI, id=4) --> change_backbone --> GBIF (id=11) for GBIF query

#
# DEPENDENCIES:
#   TaxaTools,dplyr
#
# =============================================================================

library(TaxaTools)
library(dplyr)

# =============================================================================
# 0.  USER INPUTS  -- edit this section only
# =============================================================================
# --- TaxaMatch output ---------------------------------------------------------
# Replace with your real TaxaMatch output dataframe.
# Required: taxon_name + any rank columns (kingdom ... species)
# Optional: likelihood_alpha, likelihood_beta, and sample metadata
taxamatch_output <- data.frame(
  kingdom          = c("Animalia"),
  phylum           = c("Chordata"),
  class            = c("Actinopterygii"),
  order            = c("Gobiiformes"),
  family           = c("Oxudercidae"),
  genus            = c("Eucyclogobius"),
  species          = c("Eucyclogobius newberryi"),
  likelihood_alpha = c(NA),
  likelihood_beta  = c(NA),
  stringsAsFactors = FALSE
)
# --- GBIF search expansion ----------------------------------------------------
# Expand the GBIF query to all species within this rank that are represented
# in the TaxaMatch output. E.g., "family" fetches all family members, not
# just the exact species in the sample. This captures co-occurring species
# that inform the occupancy model even if they were not in the sample.
taxonomy_ranks    <- c("kingdom", "phylum", "class", "order",
                       "family", "genus", "species")
search_rank     <- "family"
taxa_to_exclude <- c("Hominidae","Anatidae")   # groups to exclude from download

# =============================================================================
# 1.  OPTIONAL: TRANSLATE NAMES from NCBI --> GBIF backbone (generally a good idea if GBIF data are used)
# =============================================================================

message("\n--- Step 1: Translating NCBI names to GBIF backbone ---")
taxa_unique <- taxamatch_output%>%create_taxon_names(taxonomy_ranks = taxonomy_ranks)%>%unique()
taxa_in_gbif_backbone <- verify_taxon_names(taxa_unique$taxon_name, backbone_id = 11)
GBIF_ranks<-strsplit(taxa_in_gbif_backbone$classification_ranks, "\\|")[[1]] #get the taxonomy ranks for GBIF
taxa_gbif<-taxa_in_gbif_backbone|>
  change_backbone(
    input_col          = "user_supplied_name",
    old_backbone_label = "taxon_name",
    new_backbone_label = "gbif_name"
  ) |>
  create_taxon_names(taxonomy_ranks = GBIF_ranks)
n_translated <- sum(!is.na(taxa_gbif$taxon_name))
message(sprintf("  %d of %d taxa translated to GBIF backbone.",
                n_translated, nrow(taxa_gbif)))
if (n_translated == 0) stop("No taxa translated. Check backbone ID and name format.")

# Expand to higher-rank groups for GBIF search:
# e.g. search_rank = "family" fetches all families present in the sample,
# so the GBIF download captures all co-occurring species within those families.
higher_taxa_to_search <- taxa_gbif |>
  dplyr::filter(
    !is.na(.data[[search_rank]]),
    !(.data[[search_rank]] %in% taxa_to_exclude)
  ) |>
  dplyr::select(kingdom:dplyr::any_of(search_rank)) |>
  distinct()

message(sprintf("  %d unique %s group(s) identified for GBIF query.",
                nrow(higher_taxa_to_search), search_rank))

higher_taxa_to_search

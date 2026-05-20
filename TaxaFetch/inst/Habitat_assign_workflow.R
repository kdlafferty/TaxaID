# =============================================================================
# TaxaFetch workflow for uploading GBIF data
# =============================================================================
#
# INPUT:  Occurrences dataframe of taxa identified from a sample,
# OUTPUT: A habitat column.
#
# DEPENDENCIES:
#   TaxaTools, dplyr
# =============================================================================

library(TaxaTools)
library(dplyr)
library(rnaturalearth)
library(ggplot2)
library(marmap)


# =============================================================================
# 0.  USER INPUTS  -- a habitat_scheme (see Habitat scheme workflow)
# =============================================================================
# a dataframe with a taxon_name column
# =============================================================================
# 5.  ASSIGN HABITAT VIA LLM
# =============================================================================
# Habitat is assigned BEFORE grid optimisation because optimize_grid_size()
# needs main_habitat to evaluate habitat coverage per candidate resolution.

taxa_in_data <- unique(occurrence_data$taxon_name)

prompt <-build_habitat_prompt(taxa_in_data, habitat_scheme = NULL)

#EITHER#
#submit prompt automatically through an api
.llm_fn_ <- function(p, ...) call_anthropic_api(p, model = "claude-sonnet-4-6")
LLM_output <- prompt_api(prompt, llm_fn = .llm_fn_)
#OR#
#submit prompt manually (in chunks) through an interface
#info <- prompt_manual(prompt, out_dir = "habitat_assignment")
#LLM_output <- read_llm_response(info$response_files)
habitat_lookup <- parse_hierarchical_habitat_response(
  LLM_output,
  taxon_list     = prompt$taxa,
  habitat_scheme = prompt
) #translate LLM output into a taxon by habitat table
#add species-habitat associations to occurrence level data
occurrences_with_habitat <- assign_habitat_biological(
  data        = occurrence_data,
  habitats_df = habitat_lookup,
  threshold   = 0.5,
  weight_by_abundance = TRUE
)
occurrences_with_habitat%>%dplyr::select(taxon_name,main_habitat)%>%unique()

n_habitats_assigned <- occurrences_with_habitat |>
  dplyr::filter(!is.na(main_habitat)) |>
  dplyr::distinct(decimalLatitude, decimalLongitude) |>
  nrow()

message(sprintf("  %d location(s) assigned a habitat.", n_habitats_assigned))

if (n_habitats_assigned == 0) {
  stop("No sites received a habitat assignment. Check LLM output and habitat classes.")
}
# =============================================================================
# plotting habitat points over a map can help a user to find mislabeled locations.

# =============================================================================


occurrences_flagged <- flag_habitat_inconsistencies(occurrences_with_habitat)
reviewed            <- review_spatial_flags(occurrences_flagged)
occurrences_clean   <- dplyr::filter(reviewed, spatial_flag == "likely")

# Save the QC-filtered occurrences for TaxaExpect
saveRDS(occurrences_clean,
        file.path(system.file("", package = "TaxaFetch"), "occurrences_with_habitat.rds"))
message("Saved occurrences_with_habitat (post-QAQC).")


# Stage 0 — generate scheme (one API call, ~50 tokens)
sp     <- build_scheme_prompt(taxa_in_data, realm = "marine",
                              min_habitats = 3L, max_habitats = 8L)
raw_s  <- prompt_api(sp)
scheme <- parse_scheme_response(raw_s, sp)
print(scheme)   # inspect — edit if needed before proceeding

# Stage 1 — weighted assignment (unchanged)
prompt   <- build_habitat_prompt(taxa_in_data, habitat_scheme = scheme)
raw_text <- prompt_api(prompt)
hab_tbl  <- parse_hierarchical_habitat_response(raw_text, taxa_in_data,
                                                habitat_scheme = prompt)


occurrences_with_habitat <- assign_habitat_biological(
  data        = occurrence_data,
  habitats_df = hab_tbl,
  threshold   = 0.5,
  weight_by_abundance = TRUE
)
occurrences_with_habitat%>%dplyr::select(taxon_name,main_habitat)%>%unique()








# Stage 1 — quick, 18 columns
l1_prompt    <- build_l1_screening_prompt(taxa_in_data)
l1_raw       <- prompt_api(l1_prompt)
l1_screening <- parse_l1_screening_response(l1_raw, taxa_in_data,
                                            l1_prompt = l1_prompt)

# Inspect: which L1 groups got selected?
colSums(l1_screening[, -1])  # show totals per group

# Stage 2 — filtered L2 columns only
prompt <- build_habitat_prompt_two_stage(taxa_in_data, l1_screening)
# This will tell you how many L2 columns made it through

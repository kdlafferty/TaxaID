library(TaxaHabitat)
library(TaxaTools)
# =============================================================================
# ASSIGN HABITAT VIA LLM WORKFLOW
# =============================================================================
# Habitat is assigned BEFORE grid optimisation because optimize_grid_size()
# needs main_habitat to evaluate habitat coverage per candidate resolution.

message("\n--- Step 5: Assigning habitat via LLM ---")
all_occurrences<-readRDS(file.choose())  # select all_occurrences.rds from TaxaFetch/inst/


taxa_in_data <- unique(all_occurrences$taxon_name)
message(sprintf("  Requesting habitat for %d taxa...", length(taxa_in_data)))
#NULL returns the IUCN scheme.
#Otherwise, A category scheme tailored the particular taxa with
# Required column: l1_name, Optional columns: l2_name, l2_code (NA = single-level), realm
# e.g., habitat_scheme<-data.frame( l1_name = c("Kelp Forest","Kelp Forest","Rocky Reef","Rocky Reef"),
#l2_name = c("Shallow Kelp Forest (<10m)", "Deep Kelp Forest (>10m)","Rocky Subtidal","Rocky Intertidal"),
#l2_code = c("KF1", "KF2"), realm = rep("marine", 4), stringsAsFactors = FALSE)
custom_scheme<-data.frame( l1_name = c("Kelp Forest","Pelagic"))

simple_scheme <- data.frame(
  l1_name = c("Rocky Subtidal", "Sandy Subtidal","Rocky Intertidal", "Pelagic", "Estuarine Bay","Freshwater"),
  stringsAsFactors = FALSE
)


prompt <- build_habitat_prompt(taxa_in_data, habitat_scheme = simple_scheme)
#prompt <- build_habitat_prompt(taxa_in_data, habitat_scheme = NULL) #create an LLM prompt to match taxa to their IUCN habitats

#EITHER#
#submit prompt automatically through an api
.llm_fn_ <- function(p, ...) call_anthropic_api(p, model = "claude-sonnet-4-6")
LLM_output <- prompt_api(prompt, llm_fn = .llm_fn_) #process through an Anthropic api.
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
  data        = all_occurrences,
  habitats_df = habitat_lookup,
  threshold   = 0.5
)


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

#library(TaxaExpect)
library(rnaturalearth)
library(ggplot2)
library(marmap)

occurrences_flagged <- flag_habitat_inconsistencies(occurrences_with_habitat)
reviewed            <- review_spatial_flags(occurrences_flagged)
occurrences_clean   <- dplyr::filter(reviewed, spatial_flag == "likely")
saveRDS(occurrences_clean, file.choose(new = TRUE))  # choose where to save occurrences_clean.rds
message("Saved all_occurrences.")

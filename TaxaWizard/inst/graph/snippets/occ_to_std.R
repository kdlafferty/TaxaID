# Edge: occurrences -> std_occurrences
# Source: TaxaHabitat/inst/Habitat_workflow.R + TaxaHabitat/inst/workflows/assign_habitat_workflow.R

occurrences <- {{input_var}}

# Step 0: classify any institution-proximity flags from filter_gbif_quality()
# (institution_flag=TRUE for records near a biodiversity institution -- field
# stations/marine labs are often sited exactly where good habitat is, so
# these are tiered "high"/"low"/"ambiguous" for review, never auto-removed).
# Silently skipped if institution_flag isn't present (e.g. flag_institution
# was FALSE, or occurrences didn't come from filter_gbif_quality()).
if ("institution_flag" %in% names(occurrences)) {
  occurrences <- TaxaHabitat::flag_institution_candidates(occurrences)
  n_high <- sum(occurrences$institution_suspicion == "high", na.rm = TRUE)
  if (n_high > 0L) {
    message(n_high, " record(s) flagged high-suspicion for institution-collection origin -- review before treating as wild detections")
  }
}

# Step 1: Get unique taxa for habitat assignment
unique_taxa <- unique(occurrences$taxon_name)
unique_taxa <- unique_taxa[!is.na(unique_taxa) & nzchar(unique_taxa)]

# Step 2: Build habitat prompt and get LLM response
prompt <- TaxaHabitat::build_habitat_prompt(
  taxon_list         = unique_taxa,
  habitat_scheme     = {{habitat_scheme}},
  geographic_context = {{geographic_hint}}
)
raw_texts <- character(prompt$n_chunks)
for (i in seq_len(prompt$n_chunks)) {
  raw_texts[i] <- {{llm_fn}}(prompt$prompts[[i]])
}

# Step 3: Parse response into habitat weights
habitat_lookup <- TaxaHabitat::parse_hierarchical_habitat_response(
  response       = raw_texts,
  habitat_prompt = prompt
)

# Step 4: Assign habitat to occurrences
std_occurrences <- TaxaHabitat::assign_habitat_biological(
  occurrence_data = occurrences,
  habitats_df = habitat_lookup,
  threshold   = 0.5
)
message("Assigned habitat to ", nrow(std_occurrences), " occurrences")
std_occurrences

# Edge: occurrences -> std_occurrences
# Source: TaxaHabitat/inst/Habitat_workflow.R + TaxaFetch/inst/Habitat_assign_workflow.R

# Step 1: Get unique taxa for habitat assignment
unique_taxa <- unique({{input_var}}$taxon_name)
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
  data        = {{input_var}},
  habitats_df = habitat_lookup,
  threshold   = 0.5
)
message("Assigned habitat to ", nrow(std_occurrences), " occurrences")
std_occurrences
